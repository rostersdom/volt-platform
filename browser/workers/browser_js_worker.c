/* Isolated JavaScript worker. Descriptor 0 is a private, bidirectional socket. */
#define _GNU_SOURCE
#ifdef VOLT_QUICKJS
#include <quickjs.h>
#else
#include <duktape.h>
#endif
#include <errno.h>
#include <seccomp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

enum { ELEMENTS = 64, ID_BYTES = 256, TEXT_BYTES = 4096, SCRIPTS = 16, CODE_BYTES = 65536,
       FETCH_BYTES = 262144, TYPE_BYTES = 128, URL_BYTES = 8192, DOM_BYTES = 16384,
       FRAME_MAX = 40 + URL_BYTES + TYPE_BYTES + FETCH_BYTES };
static struct { int64_t node, length; int modified; unsigned char text[TEXT_BYTES]; } elements[ELEMENTS];
static size_t element_count;
static char code[CODE_BYTES + 1];
static int dirty;
static unsigned char fetch_url[URL_BYTES];
static unsigned char fetch_ct[TYPE_BYTES];
static unsigned char fetch_body[FETCH_BYTES];
static union { unsigned char bytes[FRAME_MAX]; int64_t words[(FRAME_MAX + 7) / 8]; } frame;
static size_t fetch_url_len, fetch_ct_len, fetch_body_len;
static unsigned char dom[DOM_BYTES];
static size_t dom_len;
static int dom_failed;

static void dom_reset(void) {
    dom_len = 0;
    dom_failed = 0;
}

/* Wire format, mirrored in browser/modules/browser_dom.volt:
 *   append = [op=1, parent_kind, parent_ref, html_len] (four i64) + html bytes.
 * parent_kind 0 is a page node index, 1 is a JS-created temporary id. */
enum { DOM_OP_APPEND = 1, DOM_OP_HEADER = 32 };
static int64_t dom_append(int64_t kind, int64_t ref, const unsigned char *html, size_t len) {
    if (len > DOM_BYTES - dom_len - DOM_OP_HEADER) {
        dom_failed = 1;
        return -1;
    }
    int64_t head[4] = {DOM_OP_APPEND, kind, ref, (int64_t)len};
    memcpy(dom + dom_len, head, sizeof(head));
    dom_len += sizeof(head);
    memcpy(dom + dom_len, html, len);
    dom_len += len;
    return 0;
}

static const char bootstrap[] =
    "(function(record, request, domAppend) {'use strict';"
    "var create=Object.create, define=Object.defineProperty, str=String;"
    "var apply=Function.prototype.call.bind(Function.prototype.apply);"
    "var ids=create(null), nodes=create(null), api=create(null), made=create(null);"
    "var domNext=1, domTags=create(null), REF_NODE=0, REF_TEMP=1;"
    "var domTagList='div span p a button b i em strong small code pre ul ol li section header footer h1 h2 h3 h4 h5 h6'.split(' ');"
    "for(var dt=0;dt<domTagList.length;dt++)domTags[domTagList[dt]]=true;"
    "var failed=false;"
    "function invoke(fn,target,ev){try{apply(fn,target,[ev]);}catch(e){failed=true;}}"
    "function listeners(target) {"
    " var slots=create(null);"
    " target.addEventListener=function(type, fn){"
    "   if((type!=='click'&&type!=='DOMContentLoaded')||typeof fn!=='function')return;"
    "   var list=slots[type];if(!list){list=slots[type]=create(null);list.length=0;}"
    "   for(var i=0;i<list.length;i++)if(list[i].fn===fn)return;"
    "   if(list.length<32)list[list.length++]={fn:fn,removed:false};"
    " };"
    " target.removeEventListener=function(type,fn){"
    "   if(type!=='click'&&type!=='DOMContentLoaded')return;"
    "   var list=slots[type];if(!list)return;"
    "   for(var i=0;i<list.length;i++)if(list[i].fn===fn){"
    "     list[i].removed=true;for(var j=i+1;j<list.length;j++)list[j-1]=list[j];"
    "     delete list[--list.length];return;"
    "   }"
    " };"
    " return function(type,ev){"
    "   ev.currentTarget=target;var list=slots[type], snapshot=create(null), n=list?list.length:0;"
    "   for(var i=0;i<n;i++)snapshot[i]=list[i];"
    "   for(var j=0;j<n;j++)if(!snapshot[j].removed)invoke(snapshot[j].fn,target,ev);"
    "   if(type==='click')try{var f=target.onclick;if(typeof f==='function')invoke(f,target,ev);}catch(e){failed=true;}"
    " };"
    "}"
    "var doc=create(null), docFire=listeners(doc);"
    "doc.getElementById=function(id){return ids[str(id)]||null;};"
    "doc.querySelector=function(s){s=str(s);return s[0]==='#'?doc.getElementById(s.slice(1)):null;};"
    "api.document=doc;"
    "function domEsc(s){s=str(s);if(s.indexOf('\\u0000')>=0)throw new Error('NUL in DOM text');return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;').replace(/'/g,'&#39;');}"
    "function domAttrName(n){n=str(n).toLowerCase();if(!/^[a-z][a-z0-9_-]*$/.test(n)||n.slice(0,2)==='on'||n==='data-volt-id')throw new Error('invalid attribute');return n;}"
    "function domConnect(el){el.__connected=true;for(var i=0;i<el.__children.length;i++)domConnect(el.__children[i]);}"
    "function domClass(el){return el.__attrs['class']||'';}"
    "function domSetClass(el,value){if(value)el.__attrs['class']=value;else delete el.__attrs['class'];}"
    "function domSerialize(el){"
    " var out='<'+el.__tag, k;"
    " for(k in el.__attrs)if(Object.prototype.hasOwnProperty.call(el.__attrs,k))out+=' '+k+'=\"'+domEsc(el.__attrs[k])+'\"';"
    " out+=' data-volt-id=\"'+el.__temp+'\">';"
    " if(el.__text)out+=domEsc(el.__text);"
    " for(var i=0;i<el.__children.length;i++)out+=domSerialize(el.__children[i]);"
    " return out+'</'+el.__tag+'>';"
    "}"
    "function makeElement(tag){"
    " tag=str(tag).toLowerCase();if(!domTags[tag])throw new Error('unsupported element');"
    " var el=create(null), fire=listeners(el);"
    " el.__tag=tag;el.__attrs=create(null);el.__children=[];el.__text='';el.__temp=domNext++;el.__connected=false;"
    " define(el,'tagName',{value:tag,enumerable:true});"
    " define(el,'id',{get:function(){return el.__attrs['id']||'';},set:function(v){if(el.__connected)throw new Error('connected element is immutable');var s=str(v);if(s)el.__attrs['id']=s;else delete el.__attrs['id'];if(s)ids[s]=el;},enumerable:true});"
    " define(el,'className',{get:function(){return domClass(el);},set:function(v){if(el.__connected)throw new Error('connected element is immutable');domSetClass(el,str(v));},enumerable:true});"
    " el.setAttribute=function(name,value){if(el.__connected)throw new Error('connected element is immutable');name=domAttrName(name);if(value===null||value===undefined)delete el.__attrs[name];else el.__attrs[name]=str(value);if(name==='id'&&value)ids[str(value)]=el;};"
    " el.getAttribute=function(name){name=domAttrName(name);return el.__attrs[name]===undefined?null:el.__attrs[name];};"
    " el.hasAttribute=function(name){name=domAttrName(name);return el.__attrs[name]!==undefined;};"
    " el.removeAttribute=function(name){name=domAttrName(name);if(el.__connected)throw new Error('connected element is immutable');delete el.__attrs[name];};"
    " el.classList={"
    "  add:function(){if(el.__connected)throw new Error('connected element is immutable');for(var i=0;i<arguments.length;i++){var v=str(arguments[i]),list=domClass(el).split(/\\s+/),found=false;for(var j=0;j<list.length;j++)if(list[j]===v)found=true;if(!found)domSetClass(el,domClass(el)?domClass(el)+' '+v:v);}},"
    "  remove:function(){if(el.__connected)throw new Error('connected element is immutable');var v=str(arguments[0]),out=[],list=domClass(el).split(/\\s+/);for(var i=0;i<list.length;i++)if(list[i]&&list[i]!==v)out.push(list[i]);domSetClass(el,out.join(' '));},"
    "  toggle:function(v){v=str(v);if(el.classList.contains(v)){el.classList.remove(v);return false;}el.classList.add(v);return true;},"
    "  contains:function(v){v=str(v);var list=domClass(el).split(/\\s+/);for(var i=0;i<list.length;i++)if(list[i]===v)return true;return false;}"
    " };"
    " define(el,'textContent',{get:function(){var out=el.__text;for(var i=0;i<el.__children.length;i++)out+=el.__children[i].textContent;return out;},set:function(v){if(el.__connected)throw new Error('connected element is immutable');el.__text=v===null?'':str(v);el.__children=[];},enumerable:true});"
    " el.appendChild=function(child){if(el.__connected)throw new Error('connected element is immutable');if(!child||!child.__tag)throw new Error('not an element');if(child.__connected)throw new Error('already connected');el.__children.push(child);child.__parent=el;return child;};"
    " el.onclick=null;"
    " made[el.__temp]=[el,fire];"
    " return el;"
    "}"
    "doc.createElement=makeElement;"
    "function clickPair(v){if(v>0)return nodes[v]||null;return made[-v]||null;}"
    "api.add=function(node,slot,id,text){"
    " var el=create(null), fire=listeners(el);"
    " define(el,'id',{value:id,enumerable:true});"
    " define(el,'textContent',{get:function(){return text;},set:function(v){"
    "   var s=v===null?'':str(v);if(s!==text){record(slot,s);text=s;}"
    " },enumerable:true});"
    " el.__node=node;el.__connected=true;el.__children=[];"
    " el.appendChild=function(child){"
    "   if(!child||!child.__tag)throw new Error('not an element');"
    "   if(child.__connected)throw new Error('already connected');"
    "   var html=domSerialize(child);"
    "   domAppend(REF_NODE,node,html);"
    "   domConnect(child);"
    "   return child;"
    " };"
    " if(!ids[id])ids[id]=el;nodes[node]=[el,fire];"
    "};"
    "api.ready=function(){failed=false;docFire('DOMContentLoaded',{type:'DOMContentLoaded',target:doc,currentTarget:doc});return failed;};"
    "api.click=function(path){"
    " failed=false;var first=null, stopped=false, prevented=false;"
    " for(var i=0;i<path.length;i++){var pair=clickPair(path[i]);if(pair){first=pair[0];break;}}"
    " var ev={type:'click',target:first,currentTarget:null,defaultPrevented:false,"
    "   preventDefault:function(){prevented=true;ev.defaultPrevented=true;},"
    "   stopPropagation:function(){stopped=true;}};"
    " for(var j=0;j<path.length&&!stopped;j++){var pair=clickPair(path[j]);if(pair)pair[1]('click',ev);}"
    " if(!stopped)docFire('click',ev);return (prevented?2:0)+(failed?1:0);"
    "};"
    "api.promise=function(value,failed){return{"
    " then:function(ok){if(failed)return api.promise(value,true);"
    "  try{var r=ok?ok(value):value;if(r&&typeof r.then==='function')return r;return api.promise(r,false);}"
    "  catch(e){return api.promise(e,true);}},"
    " catch:function(fn){if(failed){try{if(fn)fn(value);}catch(e){}}return api.promise(value,failed);}"
    "};};"
    "function makeHeaders(type){"
    " var h={'content-type':type};"
    " h.get=function(name){var key=str(name).toLowerCase();return h[key]===undefined?null:h[key];};"
    " h.has=function(name){return h[str(name).toLowerCase()]!==undefined;};"
    " return h;"
    "}"
    "function response(status,body,type,url){"
    " return{ok:status>=200&&status<300,status:status,statusText:'',url:url,"
    "  headers:makeHeaders(type),"
    "  text:function(){return api.promise(body,false);},"
    "  json:function(){return api.promise(JSON.parse(body),false);}};"
    "}"
    "api.fetch=function(input,init){"
    " try{"
    "  var method=0,body='',type='',url=str(input);"
    "  if(init){"
    "   if(init.method&&str(init.method).toUpperCase()==='POST')method=1;"
    "   if(init.body!==undefined&&init.body!==null)body=str(init.body);"
    "   var h=init.headers;"
    "   if(h){if(typeof h==='string')type=h;else if(h['Content-Type'])type=str(h['Content-Type']);else if(h['content-type'])type=str(h['content-type']);}"
    "  }"
    "  if(method&&!type)type='text/plain;charset=UTF-8';"
    "  var r=request(method,url,type,body);"
    "  if(!r||r[0]===0)throw new Error('network error');"
    "  return api.promise(response(r[0],r[1],r[2],r[3]),false);"
    " }catch(e){"
    "  return api.promise(e,true);"
    " }"
    "};"
    "function XMLHttpRequest(){"
    " var self=this;"
    " this.readyState=0;this.status=0;this.responseText='';this.responseURL='';this._method='GET';this._url='';this._type='';"
    " this.open=function(method,url,async){self._method=str(method).toUpperCase();self._url=str(url);self.readyState=1;};"
    " this.setRequestHeader=function(name,value){if(str(name).toLowerCase()==='content-type')self._type=str(value);};"
    " this.getResponseHeader=function(name){return str(name).toLowerCase()==='content-type'?(self._type||''):null;};"
    " this.send=function(body){"
    "  var post=self._method==='POST'?1:0,text=(body===undefined||body===null)?'':str(body);"
    "  if(post&&!self._type)self._type='text/plain;charset=UTF-8';"
    "  var r=request(post,self._url,self._type,text);"
    "  self.readyState=4;"
    "  if(r){self.status=r[0];self.responseText=r[1];self._type=r[2];self.responseURL=r[3];}"
    "  else{self.status=0;self.responseText='';}"
    "  try{if(typeof self.onreadystatechange==='function')self.onreadystatechange();}catch(e){}"
    "  try{if(self.status>=200&&self.status<300&&typeof self.onload==='function')self.onload();}catch(e){}"
    " };"
    "}"
    "api.XMLHttpRequest=XMLHttpRequest;"
    "return api;"
    "})";

static void io_exact(void *buffer, size_t length, int output) {
    unsigned char *cursor = buffer;
    while (length) {
        ssize_t n = output ? write(0, cursor, length) : read(0, cursor, length);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) _exit(n == 0 && !output ? 0 : 1);
        cursor += n;
        length -= (size_t)n;
    }
}

static int64_t receive_word(int64_t min, int64_t max) {
    int64_t n;
    io_exact(&n, sizeof(n), 0);
    if (n < min || n > max) _exit(1);
    return n;
}

static void send_word(int64_t value) { io_exact(&value, sizeof(value), 1); }

/* Ask the browser for one bounded same-origin request. The reply is read here,
 * while the JavaScript call that requested it is still on the stack. */
static int64_t perform_fetch(int post, const unsigned char *url, size_t url_len,
                             const unsigned char *type, size_t type_len,
                             const unsigned char *body, size_t body_len) {
    if (url_len < 1 || url_len > URL_BYTES || type_len > TYPE_BYTES || body_len > FETCH_BYTES) return -1;
    int64_t length = 40 + (int64_t)url_len + (int64_t)type_len + (int64_t)body_len;
    send_word(length);
    int64_t head[5] = {1, post ? 1 : 0, (int64_t)url_len, (int64_t)type_len, (int64_t)body_len};
    io_exact(head, sizeof(head), 1);
    io_exact((void *)url, url_len, 1);
    if (type_len) io_exact((void *)type, type_len, 1);
    if (body_len) io_exact((void *)body, body_len, 1);
    int64_t reply_length;
    io_exact(&reply_length, sizeof(reply_length), 0);
    if (reply_length < 40 || reply_length > FRAME_MAX) _exit(1);
    int64_t reply_head[5];
    io_exact(reply_head, sizeof(reply_head), 0);
    if (reply_head[0] != 1) _exit(1);
    int64_t status = reply_head[1], ct = reply_head[2], n = reply_head[3], final = reply_head[4];
    if (ct < 0 || ct > TYPE_BYTES || n < 0 || n > FETCH_BYTES || final < 0 || final > URL_BYTES) _exit(1);
    if (reply_length != 40 + ct + n + final) _exit(1);
    fetch_ct_len = (size_t)ct;
    fetch_body_len = (size_t)n;
    fetch_url_len = (size_t)final;
    io_exact(fetch_ct, fetch_ct_len, 0);
    io_exact(fetch_body, fetch_body_len, 0);
    io_exact(fetch_url, fetch_url_len, 0);
    return status;
}

static void save_text(unsigned slot, const void *text, size_t size) {
    elements[slot].modified = 1;
    dirty = 1;
    elements[slot].length = (int64_t)size;
    memcpy(elements[slot].text, text, size);
}

#ifndef VOLT_QUICKJS
static unsigned char fetch_text[FETCH_BYTES * 2];

/* Convert astral UTF-8 to CESU-8 into a caller buffer. */
static size_t utf8_to_cesu8(unsigned char *out, size_t capacity, const unsigned char *s, size_t n) {
    size_t at = 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] >= 0xf0 && s[i] <= 0xf4 && n - i >= 4 &&
            (s[i+1] & 0xc0) == 0x80 && (s[i+2] & 0xc0) == 0x80 && (s[i+3] & 0xc0) == 0x80) {
            unsigned cp = ((s[i]&7u)<<18) | ((s[i+1]&63u)<<12) | ((s[i+2]&63u)<<6) | (s[i+3]&63u);
            if (cp >= 0x10000 && cp <= 0x10ffff) {
                cp -= 0x10000;
                unsigned hi = 0xd800 + (cp >> 10), lo = 0xdc00 + (cp & 1023u);
                if (at + 6 <= capacity) {
                    out[at++] = 0xed; out[at++] = 0x80 | ((hi >> 6) & 63u); out[at++] = 0x80 | (hi & 63u);
                    out[at++] = 0xed; out[at++] = 0x80 | ((lo >> 6) & 63u); out[at++] = 0x80 | (lo & 63u);
                }
                i += 3;
                continue;
            }
        }
        if (at < capacity) out[at++] = s[i];
    }
    return at;
}

/* Return a string on Duktape's stack, converting astral UTF-8 to CESU-8. */
static void push_utf8(duk_context *ctx, const unsigned char *s, size_t n) {
    unsigned char out[TEXT_BYTES * 2];
    size_t at = 0;
    for (size_t i = 0; i < n; i++) {
        if (s[i] >= 0xf0 && s[i] <= 0xf4 && n - i >= 4 &&
            (s[i+1] & 0xc0) == 0x80 && (s[i+2] & 0xc0) == 0x80 && (s[i+3] & 0xc0) == 0x80) {
            unsigned cp = ((s[i]&7u)<<18) | ((s[i+1]&63u)<<12) | ((s[i+2]&63u)<<6) | (s[i+3]&63u);
            if (cp >= 0x10000 && cp <= 0x10ffff) {
                cp -= 0x10000;
                unsigned hi = 0xd800 + (cp >> 10), lo = 0xdc00 + (cp & 1023u);
                out[at++] = 0xed; out[at++] = 0x80 | ((hi >> 6) & 63u); out[at++] = 0x80 | (hi & 63u);
                out[at++] = 0xed; out[at++] = 0x80 | ((lo >> 6) & 63u); out[at++] = 0x80 | (lo & 63u);
                i += 3;
                continue;
            }
        }
        out[at++] = s[i];
    }
    duk_push_lstring(ctx, (const char *)out, at);
}
#endif

struct utf8_text { unsigned pending; size_t used; unsigned char bytes[TEXT_BYTES]; };

static void utf8_append(struct utf8_text *out, unsigned cp) {
    if (cp == 0 || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) cp = 0xfffd;
    unsigned width = cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    size_t at = out->used;
    if (at + width <= TEXT_BYTES) {
        for (unsigned i = width - 1; i; i--) {
            out->bytes[at + i] = 0x80 | (cp & 63u);
            cp >>= 6;
        }
        static const unsigned char prefix[] = {0, 0, 0xc0, 0xe0, 0xf0};
        out->bytes[at] = prefix[width] | cp;
    }
    if (at <= TEXT_BYTES) out->used += width;
}

#ifndef VOLT_QUICKJS
static void utf8_char(void *arg, duk_codepoint_t cp) {
    struct utf8_text *out = arg;
    if (out->pending) {
        unsigned hi = out->pending;
        out->pending = 0;
        if (cp >= 0xdc00 && cp <= 0xdfff) {
            utf8_append(out, 0x10000 + ((hi - 0xd800) << 10) + (cp - 0xdc00));
            return;
        }
        utf8_append(out, 0xfffd);
    }
    if (cp >= 0xd800 && cp <= 0xdbff) out->pending = cp;
    else utf8_append(out, cp);
}

static duk_ret_t record_text(duk_context *ctx) {
    unsigned slot = duk_require_uint(ctx, 0);
    duk_size_t size;
    duk_require_lstring(ctx, 1, &size);
    if (slot >= element_count || size > TEXT_BYTES * 2) return DUK_RET_RANGE_ERROR;
    struct utf8_text out = {0};
    duk_decode_string(ctx, 1, utf8_char, &out);
    if (out.pending) utf8_append(&out, 0xfffd);
    if (out.used > TEXT_BYTES) return DUK_RET_RANGE_ERROR;
    save_text(slot, out.bytes, out.used);
    return 0;
}

static duk_ret_t js_request(duk_context *ctx) {
    if (duk_get_top(ctx) < 4) return duk_error(ctx, DUK_ERR_TYPE_ERROR, "request expects four arguments");
    int post = duk_get_int(ctx, 0) != 0 ? 1 : 0;
    duk_size_t url_len = 0, type_len = 0, body_len = 0;
    const char *url = duk_require_lstring(ctx, 1, &url_len);
    const char *type = "";
    const char *body = "";
    if (!duk_is_null_or_undefined(ctx, 2)) type = duk_require_lstring(ctx, 2, &type_len);
    if (!duk_is_null_or_undefined(ctx, 3)) body = duk_require_lstring(ctx, 3, &body_len);
    if (url_len > URL_BYTES || type_len > TYPE_BYTES || body_len > FETCH_BYTES)
        return duk_error(ctx, DUK_ERR_RANGE_ERROR, "fetch exceeds the limit");
    int64_t status = perform_fetch(post, (const unsigned char *)url, url_len,
                                   (const unsigned char *)type, type_len,
                                   (const unsigned char *)body, body_len);
    if (status < 0) {
        duk_push_null(ctx);
        return 1;
    }
    duk_idx_t array = duk_push_array(ctx);
    duk_push_int(ctx, (int)status);
    duk_put_prop_index(ctx, array, 0);
    size_t converted = utf8_to_cesu8(fetch_text, sizeof(fetch_text), fetch_body, fetch_body_len);
    duk_push_lstring(ctx, (const char *)fetch_text, converted);
    duk_put_prop_index(ctx, array, 1);
    push_utf8(ctx, fetch_ct, fetch_ct_len);
    duk_put_prop_index(ctx, array, 2);
    push_utf8(ctx, fetch_url, fetch_url_len);
    duk_put_prop_index(ctx, array, 3);
    return 1;
}

static duk_ret_t js_dom_append(duk_context *ctx) {
    if (duk_get_top(ctx) < 3) return duk_error(ctx, DUK_ERR_TYPE_ERROR, "domAppend expects three arguments");
    int64_t kind = duk_get_int(ctx, 0);
    int64_t ref = duk_get_int(ctx, 1);
    duk_size_t length = 0;
    const char *html = duk_require_lstring(ctx, 2, &length);
    if (dom_append(kind, ref, (const unsigned char *)html, length) < 0)
        return duk_error(ctx, DUK_ERR_RANGE_ERROR, "DOM patch exceeds the limit");
    return 0;
}
#endif

static int isolate(void) {
    const struct rlimit memory = {96u * 1024 * 1024, 96u * 1024 * 1024};
    const struct rlimit cpu = {3, 3}, core = {0, 0};
    if (setrlimit(RLIMIT_AS, &memory) || setrlimit(RLIMIT_CPU, &cpu) || setrlimit(RLIMIT_CORE, &core) ||
        prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || prctl(PR_SET_DUMPABLE, 0, 0, 0, 0)) return -1;
    scmp_filter_ctx f = seccomp_init(SCMP_ACT_KILL_PROCESS);
    if (!f) return -1;
    const int syscalls[] = {SCMP_SYS(brk), SCMP_SYS(munmap), SCMP_SYS(mremap),
                            SCMP_SYS(madvise), SCMP_SYS(clock_gettime), SCMP_SYS(gettimeofday),
                            SCMP_SYS(futex), SCMP_SYS(exit), SCMP_SYS(exit_group), SCMP_SYS(rt_sigreturn)};
    for (size_t i = 0; i < sizeof(syscalls) / sizeof(*syscalls); i++) {
        if (seccomp_rule_add(f, SCMP_ACT_ALLOW, syscalls[i], 0)) return -1;
    }
    if (seccomp_rule_add(f, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 1, SCMP_A2(SCMP_CMP_MASKED_EQ, PROT_EXEC, 0)) ||
        seccomp_rule_add(f, SCMP_ACT_ALLOW, SCMP_SYS(read), 1, SCMP_A0(SCMP_CMP_EQ, 0)) ||
        seccomp_rule_add(f, SCMP_ACT_ALLOW, SCMP_SYS(write), 1, SCMP_A0(SCMP_CMP_EQ, 0))) return -1;
    return seccomp_load(f);
}

static void reply(int error, int prevent) {
    int64_t text_count = 0;
    if (dirty) for (size_t i = 0; i < element_count; i++) if (elements[i].modified) text_count++;
    int64_t dom_out = (int64_t)dom_len;
    if (dom_failed) error = 1;
    int64_t length = 40 + dom_out;
    if (dirty) for (size_t i = 0; i < element_count; i++) if (elements[i].modified) length += 16 + elements[i].length;
    send_word(length);
    send_word(0); /* typed frame: 0 is the final DOM reply */
    send_word(error);
    send_word(prevent);
    send_word(text_count);
    send_word(dom_out);
    if (dirty) for (size_t i = 0; i < element_count; i++) if (elements[i].modified) {
        send_word(elements[i].node);
        send_word(elements[i].length);
        io_exact(elements[i].text, (size_t)elements[i].length, 1);
    }
    if (dom_out) io_exact(dom, (size_t)dom_out, 1);
    dirty = 0;
    dom_reset();
}

#ifdef VOLT_QUICKJS
static JSContext *ctx;
static JSRuntime *runtime;
static JSValue api;

static JSValue record_text(JSContext *context, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self;
    if (argc != 2 || JS_VALUE_GET_TAG(argv[0]) != JS_TAG_INT || !JS_IsString(argv[1]))
        return JS_ThrowTypeError(context, "Invalid text edit");
    unsigned slot = (unsigned)JS_VALUE_GET_INT(argv[0]);
    if (slot >= element_count) return JS_ThrowRangeError(context, "Invalid text slot");
    int64_t units;
    if (JS_GetLength(context, argv[1], &units) < 0) return JS_EXCEPTION;
    if (units > TEXT_BYTES) return JS_ThrowRangeError(context, "Text exceeds the DOM limit");
    size_t n;
    const uint16_t *s = JS_ToCStringLenUTF16(context, &n, argv[1]);
    if (!s) return JS_EXCEPTION;
    struct utf8_text out = {0};
    for (size_t i = 0; i < n && out.used <= TEXT_BYTES; i++) {
        unsigned cp = s[i];
        if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < n && s[i + 1] >= 0xdc00 && s[i + 1] <= 0xdfff)
            cp = 0x10000 + ((cp - 0xd800) << 10) + (s[++i] - 0xdc00);
        utf8_append(&out, cp);
    }
    JS_FreeCStringUTF16(context, s);
    if (out.used > TEXT_BYTES) return JS_ThrowRangeError(context, "Text exceeds the DOM limit");
    save_text(slot, out.bytes, out.used);
    return JS_UNDEFINED;
}

static JSValue js_request(JSContext *context, JSValueConst self, int argc, JSValueConst *argv);
static JSValue js_dom_append(JSContext *context, JSValueConst self, int argc, JSValueConst *argv);

static int engine_init(void) {
    runtime = JS_NewRuntime();
    if (!runtime) return 1;
    JS_SetMemoryLimit(runtime, 32u * 1024 * 1024);
    JS_SetMaxStackSize(runtime, 512u * 1024);
    JS_SetCanBlock(runtime, false);
    /* The core has no std/os modules, module loader, or native I/O hooks. */
    ctx = JS_NewContext(runtime);
    if (!ctx) return 1;
    JSValue global = JS_GetGlobalObject(ctx);
    JSValue error = JS_GetPropertyStr(ctx, global, "Error");
    /* Keep native DOM callbacks and other internal functions out of stack objects. */
    if (JS_IsException(error) || JS_DefinePropertyValueStr(ctx, error, "prepareStackTrace", JS_UNDEFINED, 0) != 1) return 1;
    JS_FreeValue(ctx, error);
    JSValue fn = JS_Eval(ctx, bootstrap, sizeof(bootstrap) - 1, "<volt-dom>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(fn)) return 1;
    JSValue record = JS_NewCFunction(ctx, record_text, "record", 2);
    if (JS_IsException(record)) {
        JS_FreeValue(ctx, fn);
        return 1;
    }
    JSValue request = JS_NewCFunction(ctx, js_request, "request", 4);
    if (JS_IsException(request)) {
        JS_FreeValue(ctx, fn);
        JS_FreeValue(ctx, record);
        return 1;
    }
    JSValue domAppend = JS_NewCFunction(ctx, js_dom_append, "domAppend", 3);
    if (JS_IsException(domAppend)) {
        JS_FreeValue(ctx, fn);
        JS_FreeValue(ctx, record);
        JS_FreeValue(ctx, request);
        return 1;
    }
    JSValue arguments[3] = {record, request, domAppend};
    api = JS_Call(ctx, fn, JS_UNDEFINED, 3, arguments);
    JS_FreeValue(ctx, fn);
    JS_FreeValue(ctx, record);
    JS_FreeValue(ctx, request);
    JS_FreeValue(ctx, domAppend);
    if (JS_IsException(api)) return 1;
    int ok = JS_SetPropertyStr(ctx, global, "document", JS_GetPropertyStr(ctx, api, "document")) >= 0 &&
             JS_SetPropertyStr(ctx, global, "window", JS_DupValue(ctx, global)) >= 0;
    JSValue fetch = JS_GetPropertyStr(ctx, api, "fetch");
    if (JS_IsException(fetch) || JS_SetPropertyStr(ctx, global, "fetch", fetch) < 0) ok = 0;
    JSValue xhr = JS_GetPropertyStr(ctx, api, "XMLHttpRequest");
    if (JS_IsException(xhr) || JS_SetPropertyStr(ctx, global, "XMLHttpRequest", xhr) < 0) ok = 0;
    JS_FreeValue(ctx, global);
    return !ok;
}

static JSValue js_request(JSContext *context, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self;
    if (argc < 4) return JS_ThrowTypeError(context, "request expects four arguments");
    int32_t post_flag = 0;
    if (JS_ToInt32(context, &post_flag, argv[0]) < 0) return JS_EXCEPTION;
    int post = post_flag != 0;
    size_t url_len = 0, type_len = 0, body_len = 0;
    const char *url = JS_ToCStringLen(context, &url_len, argv[1]);
    if (!url) return JS_EXCEPTION;
    const char *type = "";
    const char *body = "";
    int type_alloc = 0, body_alloc = 0, failed = 0;
    if (!JS_IsNull(argv[2]) && !JS_IsUndefined(argv[2])) {
        type = JS_ToCStringLen(context, &type_len, argv[2]);
        if (type) type_alloc = 1;
        else failed = 1;
    }
    if (!failed && !JS_IsNull(argv[3]) && !JS_IsUndefined(argv[3])) {
        body = JS_ToCStringLen(context, &body_len, argv[3]);
        if (body) body_alloc = 1;
        else failed = 1;
    }
    if (failed || url_len > URL_BYTES || type_len > TYPE_BYTES || body_len > FETCH_BYTES) {
        JS_FreeCString(context, url);
        if (type_alloc) JS_FreeCString(context, type);
        if (body_alloc) JS_FreeCString(context, body);
        if (failed) return JS_EXCEPTION;
        return JS_ThrowRangeError(context, "fetch exceeds the limit");
    }
    int64_t status = perform_fetch(post, (const unsigned char *)url, url_len,
                                   (const unsigned char *)type, type_len,
                                   (const unsigned char *)body, body_len);
    JS_FreeCString(context, url);
    if (type_alloc) JS_FreeCString(context, type);
    if (body_alloc) JS_FreeCString(context, body);
    if (status < 0) return JS_NULL;
    JSValue array = JS_NewArray(context);
    if (JS_IsException(array)) return JS_EXCEPTION;
    if (JS_SetPropertyUint32(context, array, 0, JS_NewInt32(context, (int32_t)status)) < 0 ||
        JS_SetPropertyUint32(context, array, 1, JS_NewStringLen(context, (const char *)fetch_body, fetch_body_len)) < 0 ||
        JS_SetPropertyUint32(context, array, 2, JS_NewStringLen(context, (const char *)fetch_ct, fetch_ct_len)) < 0 ||
        JS_SetPropertyUint32(context, array, 3, JS_NewStringLen(context, (const char *)fetch_url, fetch_url_len)) < 0)
        return JS_EXCEPTION;
    return array;
}

static JSValue js_dom_append(JSContext *context, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self;
    if (argc < 3) return JS_ThrowTypeError(context, "domAppend expects three arguments");
    int32_t kind = 0, ref = 0;
    if (JS_ToInt32(context, &kind, argv[0]) < 0 || JS_ToInt32(context, &ref, argv[1]) < 0)
        return JS_EXCEPTION;
    size_t length = 0;
    const char *html = JS_ToCStringLen(context, &length, argv[2]);
    if (!html) return JS_EXCEPTION;
    int64_t status = dom_append(kind, ref, (const unsigned char *)html, length);
    JS_FreeCString(context, html);
    if (status < 0) return JS_ThrowRangeError(context, "DOM patch exceeds the limit");
    return JS_UNDEFINED;
}

static JSValue dom_call(const char *name, int count, JSValue *args) {
    JSValue method = JS_GetPropertyStr(ctx, api, name);
    if (JS_IsException(method)) return method;
    JSValue result = JS_Call(ctx, method, JS_UNDEFINED, count, args);
    JS_FreeValue(ctx, method);
    return result;
}

static int engine_add(unsigned slot, const char *id, size_t id_len, const char *text, size_t text_len) {
    JSValue args[] = {JS_NewInt32(ctx, (int)elements[slot].node), JS_NewUint32(ctx, slot),
                      JS_NewStringLen(ctx, id, id_len), JS_NewStringLen(ctx, text, text_len)};
    JSValue result = JS_EXCEPTION;
    if (!JS_IsException(args[2]) && !JS_IsException(args[3])) result = dom_call("add", 4, args);
    for (size_t i = 0; i < sizeof(args) / sizeof(*args); i++) JS_FreeValue(ctx, args[i]);
    JS_FreeValue(ctx, result);
    return JS_IsException(result) || JS_HasException(ctx);
}

static int check_exception(JSContext *context, int failed) {
    if (!failed) {
        if (JS_HasException(context)) _exit(1);
        return 0;
    }
    JSValue exception = JS_GetException(context);
    if (JS_IsUncatchableError(exception)) _exit(1);
    JS_FreeValue(context, exception);
    return 1;
}

static int drain_jobs(void) {
    int errors = 0;
    for (unsigned i = 0; JS_IsJobPending(runtime); i++) {
        /* Do not publish a partial DOM reply for a never-empty microtask queue. */
        if (i == 1024) _exit(1);
        JSContext *job_ctx = NULL;
        int status = JS_ExecutePendingJob(runtime, &job_ctx);
        errors |= check_exception(job_ctx ? job_ctx : ctx, status < 0);
    }
    return errors;
}

static int engine_eval(size_t n) {
    JSValue result = JS_Eval(ctx, code, n, "<inline>", JS_EVAL_TYPE_GLOBAL);
    int errors = check_exception(ctx, JS_IsException(result));
    JS_FreeValue(ctx, result);
    return errors | drain_jobs();
}

static int engine_ready(void) {
    JSValue result = dom_call("ready", 0, NULL);
    int errors = check_exception(ctx, JS_IsException(result)) || JS_ToBool(ctx, result) != 0;
    JS_FreeValue(ctx, result);
    return errors | drain_jobs();
}

static int engine_click(size_t n, const int64_t *nodes) {
    JSValue path = JS_NewObjectProto(ctx, JS_NULL);
    if (JS_IsException(path) || JS_SetPropertyStr(ctx, path, "length", JS_NewUint32(ctx, (uint32_t)n)) < 0) _exit(1);
    for (size_t i = 0; i < n; i++)
        if (JS_SetPropertyUint32(ctx, path, (uint32_t)i, JS_NewInt32(ctx, (int)nodes[i])) < 0) _exit(1);
    JSValue result = dom_call("click", 1, &path);
    int32_t flags = 0;
    if (check_exception(ctx, JS_IsException(result)) || JS_ToInt32(ctx, &flags, result)) flags = 1;
    JS_FreeValue(ctx, result);
    JS_FreeValue(ctx, path);
    return flags | drain_jobs();
}
#else
static duk_context *ctx;

static void method(const char *name) {
    duk_push_heap_stash(ctx);
    duk_get_prop_string(ctx, -1, "volt");
    duk_get_prop_string(ctx, -1, name);
    duk_remove(ctx, -2);
    duk_remove(ctx, -2);
}

static int engine_init(void) {
    ctx = duk_create_heap_default();
    if (!ctx || duk_peval_lstring(ctx, bootstrap, sizeof(bootstrap) - 1)) return 1;
    duk_push_c_function(ctx, record_text, 2);
    duk_push_c_function(ctx, js_request, 4);
    duk_push_c_function(ctx, js_dom_append, 3);
    if (duk_pcall(ctx, 3)) return 1;
    duk_push_heap_stash(ctx);
    duk_dup(ctx, -2);
    duk_put_prop_string(ctx, -2, "volt");
    duk_pop(ctx);
    duk_get_prop_string(ctx, -1, "document");
    duk_put_global_string(ctx, "document");
    duk_get_prop_string(ctx, -1, "fetch");
    duk_put_global_string(ctx, "fetch");
    duk_get_prop_string(ctx, -1, "XMLHttpRequest");
    duk_put_global_string(ctx, "XMLHttpRequest");
    duk_pop(ctx);
    duk_push_global_object(ctx);
    duk_del_prop_string(ctx, -1, "Duktape");
    duk_dup(ctx, -1);
    duk_put_global_string(ctx, "window");
    duk_pop(ctx);
    return 0;
}

static int engine_add(unsigned slot, const char *id, size_t id_len, const char *text, size_t text_len) {
    method("add");
    duk_push_uint(ctx, (duk_uint_t)elements[slot].node);
    duk_push_uint(ctx, slot);
    push_utf8(ctx, (const unsigned char *)id, id_len);
    push_utf8(ctx, (const unsigned char *)text, text_len);
    int status = duk_pcall(ctx, 4);
    duk_pop(ctx);
    return status;
}

static int engine_eval(size_t n) {
    int error = duk_pcompile_lstring(ctx, 0, code, n) || duk_pcall(ctx, 0);
    duk_pop(ctx);
    return error;
}

static int engine_ready(void) {
    method("ready");
    int error = duk_pcall(ctx, 0) || duk_get_boolean_default(ctx, -1, 0);
    duk_pop(ctx);
    return error;
}

static int engine_click(size_t n, const int64_t *nodes) {
    method("click");
    duk_idx_t path = duk_push_bare_object(ctx);
    duk_push_uint(ctx, (duk_uint_t)n);
    duk_put_prop_string(ctx, path, "length");
    for (duk_uarridx_t i = 0; i < n; i++) {
        duk_push_int(ctx, (duk_int_t)nodes[i]);
        duk_put_prop_index(ctx, path, i);
    }
    int result = duk_pcall(ctx, 1) ? 1 : duk_get_int_default(ctx, -1, 1);
    duk_pop(ctx);
    return result;
}
#endif

int main(void) {
    /* libc's default local timezone may try to open a file on the first Date call. */
    if (setenv("TZ", "UTC0", 1)) return 1;
    tzset();
    /* No bytes from a document are read until the sandbox is installed. */
    if (isolate() || engine_init()) return 1;
    if (receive_word(1, 1) != 1) return 1; /* IPC version */
    element_count = (size_t)receive_word(0, ELEMENTS);
    size_t scripts = (size_t)receive_word(1, SCRIPTS);
    for (size_t i = 0; i < element_count; i++) {
        char id_text[ID_BYTES], text_bytes[TEXT_BYTES];
        elements[i].node = receive_word(1, 65535);
        size_t id = (size_t)receive_word(1, ID_BYTES);
        size_t text = (size_t)receive_word(0, TEXT_BYTES);
        io_exact(id_text, id, 0);
        io_exact(text_bytes, text, 0);
        if (engine_add((unsigned)i, id_text, id, text_bytes, text)) return 1;
    }
    size_t budget = CODE_BYTES;
    int errors = 0;
    dom_reset();
    for (size_t i = 0; i < scripts; i++) {
        size_t n = (size_t)receive_word(1, (int64_t)budget);
        budget -= n;
        io_exact(code, n, 0);
        code[n] = '\0';
        errors |= engine_eval(n);
    }
    errors |= engine_ready();
    reply(errors, 0);
    for (;;) {
        int64_t length;
        io_exact(&length, sizeof(length), 0);
        if (length < 16 || length > FRAME_MAX) _exit(1);
        io_exact(frame.bytes, (size_t)length, 0);
        int64_t *head = frame.words;
        if (head[0] != 0) _exit(1);
        int64_t n = head[1];
        if (n < 0 || n > 128 || length != 8 * (n + 2)) _exit(1);
        int64_t nodes[128];
        for (size_t i = 0; i < (size_t)n; i++) nodes[i] = head[2 + i];
        dom_reset();
        int result = engine_click((size_t)n, nodes);
        reply(result & 1, (result >> 1) & 1);
    }
}
