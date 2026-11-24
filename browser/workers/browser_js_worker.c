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

enum { ELEMENTS = 64, ID_BYTES = 256, TEXT_BYTES = 4096, SCRIPTS = 16, CODE_BYTES = 65536 };
static struct { int64_t node, length; int modified; unsigned char text[TEXT_BYTES]; } elements[ELEMENTS];
static size_t element_count;
static char code[CODE_BYTES + 1];
static int dirty;

static const char bootstrap[] =
    "(function(record) {'use strict';"
    "var create=Object.create, define=Object.defineProperty, str=String;"
    "var apply=Function.prototype.call.bind(Function.prototype.apply);"
    "var ids=create(null), nodes=create(null), api=create(null);"
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
    "api.add=function(node,slot,id,text){"
    " var el=create(null), fire=listeners(el);"
    " define(el,'id',{value:id,enumerable:true});"
    " define(el,'textContent',{get:function(){return text;},set:function(v){"
    "   var s=v===null?'':str(v);if(s!==text){record(slot,s);text=s;}"
    " },enumerable:true});"
    " if(!ids[id])ids[id]=el;nodes[node]=[el,fire];"
    "};"
    "api.ready=function(){failed=false;docFire('DOMContentLoaded',{type:'DOMContentLoaded',target:doc,currentTarget:doc});return failed;};"
    "api.click=function(path){"
    " failed=false;var first=null, stopped=false, prevented=false;"
    " for(var i=0;i<path.length;i++)if(nodes[path[i]]){first=nodes[path[i]][0];break;}"
    " var ev={type:'click',target:first,currentTarget:null,defaultPrevented:false,"
    "   preventDefault:function(){prevented=true;ev.defaultPrevented=true;},"
    "   stopPropagation:function(){stopped=true;}};"
    " for(var j=0;j<path.length&&!stopped;j++)if(nodes[path[j]])nodes[path[j]][1]('click',ev);"
    " if(!stopped)docFire('click',ev);return (prevented?2:0)+(failed?1:0);"
    "};return api;"
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

static void save_text(unsigned slot, const void *text, size_t size) {
    elements[slot].modified = 1;
    dirty = 1;
    elements[slot].length = (int64_t)size;
    memcpy(elements[slot].text, text, size);
}

#ifndef VOLT_QUICKJS
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
    int64_t length = 16;
    if (dirty) for (size_t i = 0; i < element_count; i++) if (elements[i].modified) length += 16 + elements[i].length;
    send_word(length);
    send_word(error);
    send_word(prevent);
    if (dirty) for (size_t i = 0; i < element_count; i++) if (elements[i].modified) {
        send_word(elements[i].node);
        send_word(elements[i].length);
        io_exact(elements[i].text, (size_t)elements[i].length, 1);
    }
    dirty = 0;
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
    if (JS_IsException(record)) return 1;
    api = JS_Call(ctx, fn, JS_UNDEFINED, 1, &record);
    JS_FreeValue(ctx, fn);
    JS_FreeValue(ctx, record);
    if (JS_IsException(api)) return 1;
    int ok = JS_SetPropertyStr(ctx, global, "document", JS_GetPropertyStr(ctx, api, "document")) >= 0 &&
             JS_SetPropertyStr(ctx, global, "window", JS_DupValue(ctx, global)) >= 0;
    JS_FreeValue(ctx, global);
    return !ok;
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
    if (duk_pcall(ctx, 1)) return 1;
    duk_push_heap_stash(ctx);
    duk_dup(ctx, -2);
    duk_put_prop_string(ctx, -2, "volt");
    duk_pop(ctx);
    duk_get_prop_string(ctx, -1, "document");
    duk_put_global_string(ctx, "document");
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
        duk_push_uint(ctx, (duk_uint_t)nodes[i]);
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
        int64_t nodes[128];
        size_t n = (size_t)receive_word(0, 128);
        for (size_t i = 0; i < n; i++) nodes[i] = receive_word(1, 65535);
        int result = engine_click(n, nodes);
        reply(result & 1, (result >> 1) & 1);
    }
}
