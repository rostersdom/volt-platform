use browser_youtube_url
use html
use utf8

struct YoutubeMetadata:
    title: [513]char
    media: [8193]char

const YOUTUBE_JSON_DEPTH: i64 = 64
const YOUTUBE_METADATA_MEDIA_BYTES: i64 = 33554432
const YOUTUBE_METADATA_BITRATE_LIMIT: i64 = 2147483647

struct YoutubeJson:
    text: ptr<char>
    at: i64
    stop: i64

struct YoutubeJsonSpan:
    start: i64
    stop: i64

unsafe fn youtube_json_peek(json: ptr<YoutubeJson>) -> char:
    if json.at == json.stop: return '\0'
    return json.text[json.at]

unsafe fn youtube_json_space(json: ptr<YoutubeJson>):
    while html_space(youtube_json_peek(json)): json.at += 1

unsafe fn youtube_json_take(json: ptr<YoutubeJson>, c: char) -> bool:
    youtube_json_space(json)
    if youtube_json_peek(json) != c: return false
    json.at += 1
    return true

fn youtube_json_digit(c: char) -> bool:
    return c >= '0' and c <= '9'

fn youtube_json_hex(c: char) -> i64:
    let byte: i64 = c as i64
    if c >= '0' and c <= '9': return byte - 48
    if c >= 'a' and c <= 'f': return byte - 87
    if c >= 'A' and c <= 'F': return byte - 55
    return -1

unsafe fn youtube_json_hex4(json: ptr<YoutubeJson>) -> i64:
    if json.stop - json.at < 4: return -1
    let code: i64 = 0
    for i in 0..4:
        let digit: i64 = youtube_json_hex(json.text[json.at + i])
        if digit < 0: return -1
        code = code * 16 + digit
    json.at += 4
    return code

unsafe fn youtube_json_escape(json: ptr<YoutubeJson>) -> i64:
    let escape: char = youtube_json_peek(json)
    if escape == '\0': return -1
    json.at += 1
    if escape == '"' or escape == '\\' or escape == '/': return escape as i64
    if escape == 'b': return 8
    if escape == 'f': return 12
    if escape == 'n': return 10
    if escape == 'r': return 13
    if escape == 't': return 9
    if escape != 'u': return -1
    let code: i64 = youtube_json_hex4(json)
    if code >= 0xd800 and code <= 0xdbff and html_match(json.text, json.at, json.stop, "\\u"):
        let next: i64 = json.at
        json.at += 2
        let low: i64 = youtube_json_hex4(json)
        if low >= 0xdc00 and low <= 0xdfff:
            return 0x10000 + (code - 0xd800) * 1024 + low - 0xdc00
        json.at = next
    return code

fn youtube_metadata_printable(code: i64) -> bool:
    if not utf8_is_scalar(code) or code < 32 or (code >= 0x7f and code <= 0x9f): return false
    if code == 0x061c or code == 0x200e or code == 0x200f or (code >= 0x2028 and code <= 0x202e): return false
    if (code >= 0x2066 and code <= 0x206f) or code == 0xfeff: return false
    return (code < 0xfdd0 or code > 0xfdef) and (code & 0xffff) < 0xfffe

# capacity 0 validates/skips. -7 means a valid JSON string cannot be copied as printable UTF-8.
unsafe fn youtube_json_string(json: ptr<YoutubeJson>, output: ptr<char>, capacity: i64) -> i64:
    if youtube_json_peek(json) != '"': return -1
    json.at += 1
    let used: i64 = 0
    let fits: bool = true
    while json.at < json.stop:
        let c: char = json.text[json.at]
        if c == '"':
            json.at += 1
            if capacity > 0: output[used] = '\0'
            if not fits: return -7
            return used
        let code: i64 = c as i64
        if code < 32: return -1
        if c == '\\':
            json.at += 1
            code = youtube_json_escape(json)
            if code < 0: return -1
        elif code >= 128:
            let start: i64 = json.at
            code = utf8_next(json.text, &json.at, json.stop)
            if code == 0xfffd and json.at == start + 1: return -1
        else:
            json.at += 1
        if capacity > 0 and fits:
            if not youtube_metadata_printable(code):
                fits = false
            else:
                let n: i64 = utf8_write(code, output + used, capacity - 1 - used)
                if n < 0: fits = false
                else: used += n
    return -1

unsafe fn youtube_json_number(json: ptr<YoutubeJson>) -> bool:
    if youtube_json_peek(json) == '-': json.at += 1
    let first: char = youtube_json_peek(json)
    if not youtube_json_digit(first): return false
    json.at += 1
    if first != '0':
        while youtube_json_digit(youtube_json_peek(json)): json.at += 1
    if youtube_json_peek(json) == '.':
        json.at += 1
        if not youtube_json_digit(youtube_json_peek(json)): return false
        while youtube_json_digit(youtube_json_peek(json)): json.at += 1
    let exponent: char = youtube_json_peek(json)
    if exponent == 'e' or exponent == 'E':
        json.at += 1
        let sign: char = youtube_json_peek(json)
        if sign == '+' or sign == '-': json.at += 1
        if not youtube_json_digit(youtube_json_peek(json)): return false
        while youtube_json_digit(youtube_json_peek(json)): json.at += 1
    return true

unsafe fn youtube_json_skip(json: ptr<YoutubeJson>, depth: i64) -> bool:
    if depth > YOUTUBE_JSON_DEPTH: return false
    youtube_json_space(json)
    let c: char = youtube_json_peek(json)
    if c == '"': return youtube_json_string(json, 0 as ptr<char>, 0) >= 0
    if c == '{' or c == '[':
        json.at += 1
        let close: char = ']'
        if c == '{': close = '}'
        if youtube_json_take(json, close): return true
        while true:
            if c == '{':
                youtube_json_space(json)
                if youtube_json_string(json, 0 as ptr<char>, 0) < 0 or not youtube_json_take(json, ':'): return false
            if not youtube_json_skip(json, depth + 1): return false
            if youtube_json_take(json, close): return true
            if not youtube_json_take(json, ','): return false
    let word: string = ""
    if c == 't': word = "true"
    elif c == 'f': word = "false"
    elif c == 'n': word = "null"
    if word == "": return youtube_json_number(json)
    if not html_match(json.text, json.at, json.stop, word): return false
    json.at += __volt_strlen(word)
    return true

unsafe fn youtube_json_protection(key: ptr<char>, length: i64) -> bool:
    if length >= 3 and (key[0] == 'd' or key[0] == 'D') and (key[1] == 'r' or key[1] == 'R') and (key[2] == 'm' or key[2] == 'M'): return true
    return html_name_in(key as string, 0, length, "cipher signaturecipher widevine license licenseinfo licenseinfos licenseurl licenseserverurl encrypted isencrypted encryptioninfo encryptionscheme contentprotection protectioninfo protectionscheme isdrm isdrmprotected isprotected keysystem keysystems pssh")

# Record direct members only; decoded key names prevent escaped duplicates from hiding.
unsafe fn youtube_json_fields(json: ptr<YoutubeJson>, names: ptr<string>, fields: ptr<YoutubeJsonSpan>, count: i64) -> i64:
    for i in 0..count: fields[i] = YoutubeJsonSpan(-1, -1)
    if not youtube_json_take(json, '{'): return 0
    if youtube_json_take(json, '}'): return 1
    let protected: bool = false
    let key: [32]char
    while true:
        youtube_json_space(json)
        let length: i64 = youtube_json_string(json, &key[0], 32)
        if length == -1 or not youtube_json_take(json, ':'): return -1
        youtube_json_space(json)
        let start: i64 = json.at
        if not youtube_json_skip(json, 1): return -1
        let key_size: i64 = length
        if key_size < 0: key_size = __volt_strlen(&key[0])
        if youtube_json_protection(&key[0], key_size): protected = true
        if length >= 0:
            for i in 0..count:
                if (&key[0]) as string == names[i]:
                    if fields[i].start >= 0: return -1
                    fields[i] = YoutubeJsonSpan(start, json.at)
        if youtube_json_take(json, '}'):
            if protected: return 0
            return 1
        if not youtube_json_take(json, ','): return -1
    return -1

unsafe fn youtube_json_members(text: ptr<char>, span: YoutubeJsonSpan, names: ptr<string>, fields: ptr<YoutubeJsonSpan>, count: i64) -> i64:
    if span.start < 0: return 0
    let json: YoutubeJson = YoutubeJson(text, span.start, span.stop)
    return youtube_json_fields(&json, names, fields, count)

unsafe fn youtube_json_text(text: ptr<char>, span: YoutubeJsonSpan, out: ptr<char>, capacity: i64) -> i64:
    if span.start < 0: return -1
    let json: YoutubeJson = YoutubeJson(text, span.start, span.stop)
    return youtube_json_string(&json, out, capacity)

unsafe fn youtube_json_positive(text: ptr<char>, span: YoutubeJsonSpan, limit: i64) -> i64:
    if span.start < 0: return 0
    let p: ptr<char> = text + span.start
    let length: i64 = span.stop - span.start
    let decoded: [16]char
    if p[0] == '"':
        length = youtube_json_text(text, span, &decoded[0], 16)
        p = &decoded[0]
    if length <= 0 or length > 15: return -1
    let number: i64 = 0
    for i in 0..length:
        if not youtube_json_digit(p[i]): return -1
        number = number * 10 + (p[i] as i64) - 48
        if number > limit: return -1
    if number == 0: return -1
    return number

unsafe fn youtube_metadata_player_start(text: ptr<char>, start: i64, stop: i64) -> i64:
    let json: YoutubeJson = YoutubeJson(text, start, stop)
    youtube_json_space(&json)
    let declarations: [3]string = ["var", "let", "const"]
    for i in 0..3:
        let n: i64 = __volt_strlen(declarations[i])
        if json.at + n < stop and html_space(text[json.at + n]) and html_match(text, json.at, stop, declarations[i]):
            json.at += n
            youtube_json_space(&json)
            break
    let marker: string = "ytInitialPlayerResponse"
    if not html_match(text, json.at, stop, marker): return -1
    json.at += __volt_strlen(marker)
    if not youtube_json_take(&json, '='): return -1
    return json.at

# Verify the shared tokenizer's tag bounds; a stray quote in a bare attribute must not expose a fake script.
unsafe fn youtube_metadata_tag(text: ptr<char>, token: ptr<HtmlToken>, script: bool) -> i64:
    let name: i64 = token.raw_start + 1
    if token.kind == HTML_END_TAG: name += 1
    if token.start != name: return -1
    let first: char = text[name]
    if not ((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z')): return -1
    let at: i64 = token.start + token.length
    let end: i64 = token.raw_start + token.raw_length - 1
    for i in name..at:
        let c: char = text[i]
        if c <= 32 or c == '<' or c == '\'' or c == '"': return -1
    let inline: bool = script
    let source: string = text as string
    while at < end:
        while at < end and html_space(text[at]): at += 1
        if at == end: break
        if text[at] == '/':
            if at + 1 != end: return -1
            inline = false
            break
        let key: i64 = at
        while at < end and not html_space(text[at]) and text[at] != '=' and text[at] != '/':
            let c: char = text[at]
            if c <= 32 or c == '<' or c == '\'' or c == '"' or c == '`': return -1
            at += 1
        let key_size: i64 = at - key
        if key_size == 0: return -1
        while at < end and html_space(text[at]): at += 1
        let value: i64 = at
        let value_size: i64 = 0
        if at < end and text[at] == '=':
            at += 1
            while at < end and html_space(text[at]): at += 1
            let quote: char = '\0'
            if at < end and (text[at] == '\'' or text[at] == '"'):
                quote = text[at]
                at += 1
            value = at
            if quote == '\0':
                while at < end and not html_space(text[at]):
                    let c: char = text[at]
                    if c <= 32 or c == '<' or c == '\'' or c == '"' or c == '`': return -1
                    at += 1
                value_size = at - value
            else:
                while at < end and text[at] != quote: at += 1
                if at == end: return -1
                value_size = at - value
                at += 1
                if at < end and text[at] != '/' and not html_space(text[at]): return -1
        if inline and html_name_in(source, key, key_size, "src href xlink:href"): inline = false
        if inline and value_size > 0 and html_name_in(source, key, key_size, "type"):
            if not html_name_in(source, value, value_size, "text/javascript application/javascript text/ecmascript application/ecmascript"): inline = false
    if inline: return 1
    return 0

unsafe fn youtube_metadata_raw_end(text: ptr<char>, length: i64, start: i64, tag: string) -> i64:
    let size: i64 = __volt_strlen(tag)
    let script: bool = tag == "script"
    let comment: bool = false
    for i in start..length:
        if comment and text[i] == '-' and html_match(text, i, length, "-->"): comment = false
        if text[i] != '<': continue
        if script and html_match(text, i, length, "<!--"): comment = true
        let name: i64 = i + 1
        let closing: bool = name < length and text[name] == '/'
        if closing: name += 1
        elif not comment: continue
        if size >= length - name: continue
        let after: char = text[name + size]
        if after != '>' and after != '/' and after != 12 as char and not html_space(after): continue
        if not html_name_in(text as string, name, size, tag): continue
        # A legacy escaped <script> can hide the apparent end tag. Don't recover it.
        if not closing or after == 12 as char: return -1
        return i
    return length

# shortcut: the existing tokenizer covers ordinary watch-page HTML, not HTML5 error recovery.
unsafe fn youtube_metadata_script(text: ptr<char>, length: i64, script: ptr<YoutubeJsonSpan>) -> i64:
    let source: string = text as string
    let at: i64 = 0
    let templates: i64 = 0
    script[0] = YoutubeJsonSpan(-1, -1)
    while at < length:
        # The shared tokenizer treats <! as a short declaration, not foreign CDATA.
        if text[at] == '<' and html_match(text, at, length, "<![CDATA["): return -1
        let token: HtmlToken
        let kind: i64 = html_next_range(text, length, &at, &token)
        if kind < 0: return -1
        if kind == HTML_DOCTYPE and token.raw_length > 9 and html_name_in(source, token.raw_start + 2, 7, "doctype"):
            # The short declaration scanner does not handle quoted legacy doctypes.
            for i in token.raw_start + 9..at - 1:
                if text[i] == '\'' or text[i] == '"': return -1
        if kind != HTML_START_TAG and kind != HTML_END_TAG: continue
        let inline: i64 = youtube_metadata_tag(text, &token, kind == HTML_START_TAG and html_token_is(source, &token, "script"))
        if inline < 0: return -1
        if kind == HTML_END_TAG and templates > 0 and html_token_is(source, &token, "template"):
            templates -= 1
        if kind != HTML_START_TAG: continue
        if html_token_is(source, &token, "template"): templates += 1
        let raw: string = html_raw_tag(source, &token, true)
        if raw == "": continue
        if raw == "plaintext": break
        let stop: i64 = youtube_metadata_raw_end(text, length, at, raw)
        if stop < 0: return -1
        if inline == 1 and templates == 0:
            let start: i64 = youtube_metadata_player_start(text, at, stop)
            if start >= 0:
                if stop == length or script.start >= 0: return -1
                script[0] = YoutubeJsonSpan(start, stop)
        at = stop
    if script.start < 0: return 0
    return 1

unsafe fn youtube_metadata_video_codec(codec: string, mp4: bool) -> bool:
    if not mp4:
        if codec == "vp8" or codec == "vp8.0" or codec == "vp9" or codec == "vp9.0": return true
        let text: ptr<char> = codec as ptr<char>
        if __volt_strlen(codec) != 13 or not html_match(text, 0, 13, "vp09."): return false
        for i in 5..13:
            if i == 7 or i == 10:
                if text[i] != '.': return false
            elif not youtube_json_digit(text[i]): return false
        return true
    if codec == "avc1" or codec == "avc3": return true
    let text: ptr<char> = codec as ptr<char>
    if __volt_strlen(codec) != 11: return false
    if not html_match(text, 0, 11, "avc1.") and not html_match(text, 0, 11, "avc3."): return false
    for i in 5..11:
        if youtube_json_hex(text[i]) < 0: return false
    return true

fn youtube_metadata_audio_codec(codec: string, mp4: bool) -> bool:
    if mp4: return codec == "mp4a.40.2" or codec == "mp4a.40.5" or codec == "mp4a.40.29"
    return codec == "opus" or codec == "vorbis"

unsafe fn youtube_metadata_mime(text: ptr<char>, span: YoutubeJsonSpan, itag: i64) -> bool:
    let mime: [129]char
    let n: i64 = youtube_json_text(text, span, &mime[0], 129)
    let mp4: bool = html_match(&mime[0], 0, n, "video/mp4")
    if not mp4 and not html_match(&mime[0], 0, n, "video/webm"): return false
    let at: i64 = 10
    if mp4: at = 9
    while at < n and mime[at] == ' ': at += 1
    if at == n:
        if mp4: return itag == 18 or itag == 22
        return itag >= 43 and itag <= 46
    if mime[at] != ';': return false
    at += 1
    while at < n and mime[at] == ' ': at += 1
    if not html_match(&mime[0], at, n, "codecs"): return false
    at += 6
    while at < n and mime[at] == ' ': at += 1
    if at == n or mime[at] != '=': return false
    at += 1
    while at < n and mime[at] == ' ': at += 1
    if at == n or mime[at] != '"': return false
    at += 1
    while at < n and mime[at] == ' ': at += 1
    let first: i64 = at
    while at < n and mime[at] != ' ' and mime[at] != ',' and mime[at] != '"': at += 1
    let first_end: i64 = at
    while at < n and mime[at] == ' ': at += 1
    if at == n or mime[at] != ',': return false
    at += 1
    while at < n and mime[at] == ' ': at += 1
    let second: i64 = at
    while at < n and mime[at] != ' ' and mime[at] != ',' and mime[at] != '"': at += 1
    let second_end: i64 = at
    while at < n and mime[at] == ' ': at += 1
    if at == n or mime[at] != '"': return false
    at += 1
    while at < n and mime[at] == ' ': at += 1
    if at != n or first == first_end or second == second_end: return false
    mime[first_end] = '\0'
    mime[second_end] = '\0'
    let a: string = (&mime[0] + first) as string
    let b: string = (&mime[0] + second) as string
    return (youtube_metadata_video_codec(a, mp4) and youtube_metadata_audio_codec(b, mp4)) or (youtube_metadata_video_codec(b, mp4) and youtube_metadata_audio_codec(a, mp4))

struct YoutubeMetadataChoice:
    source: YoutubeJsonSpan
    bitrate: i64
    size: i64
    itag: i64

unsafe fn youtube_metadata_format(text: ptr<char>, span: YoutubeJsonSpan, choice: ptr<YoutubeMetadataChoice>) -> i64:
    let names: [7]string = ["url", "mimeType", "itag", "contentLength", "bitrate", "averageBitrate", "type"]
    let fields: [7]YoutubeJsonSpan
    let parsed: i64 = youtube_json_members(text, span, &names[0], &fields[0], 7)
    if parsed <= 0: return parsed
    let size: i64 = youtube_json_positive(text, fields[3], YOUTUBE_METADATA_MEDIA_BYTES)
    if size < 0: return 0
    if fields[6].start >= 0:
        let kind: [32]char
        if youtube_json_text(text, fields[6], &kind[0], 32) < 0 or (&kind[0]) as string != "FORMAT_STREAM_TYPE_DEFAULT": return 0
    let itag: i64 = youtube_json_positive(text, fields[2], YOUTUBE_METADATA_BITRATE_LIMIT)
    if not youtube_metadata_mime(text, fields[1], itag): return 0
    let url: [8193]char
    if youtube_json_text(text, fields[0], &url[0], 8193) <= 0 or not youtube_media_url((&url[0]) as string): return 0
    let rate: i64 = youtube_json_positive(text, fields[4], YOUTUBE_METADATA_BITRATE_LIMIT)
    if rate <= 0: rate = youtube_json_positive(text, fields[5], YOUTUBE_METADATA_BITRATE_LIMIT)
    if rate <= 0: rate = YOUTUBE_METADATA_BITRATE_LIMIT + 1
    if size == 0: size = YOUTUBE_METADATA_MEDIA_BYTES + 1
    let known: bool = size <= YOUTUBE_METADATA_MEDIA_BYTES
    let current_known: bool = choice.size <= YOUTUBE_METADATA_MEDIA_BYTES
    let better_rate: bool = rate < choice.bitrate or (rate == choice.bitrate and (size < choice.size or (size == choice.size and itag == 18 and choice.itag == 22)))
    let equal_size_class: bool = (known and current_known) or (not known and not current_known)
    if choice.source.start < 0 or (known and not current_known) or (equal_size_class and better_rate):
        choice[0] = YoutubeMetadataChoice(fields[0], rate, size, itag)
    return 1

unsafe fn youtube_metadata_formats(text: ptr<char>, span: YoutubeJsonSpan, choice: ptr<YoutubeMetadataChoice>) -> i64:
    if span.start < 0: return 0
    let json: YoutubeJson = YoutubeJson(text, span.start, span.stop)
    if not youtube_json_take(&json, '[') or youtube_json_take(&json, ']'): return 0
    while true:
        youtube_json_space(&json)
        let start: i64 = json.at
        if not youtube_json_skip(&json, 1): return -1
        if youtube_metadata_format(text, YoutubeJsonSpan(start, json.at), choice) < 0: return -1
        if youtube_json_take(&json, ']'): break
        if not youtube_json_take(&json, ','): return -1
    if choice.source.start < 0: return 0
    return 1

# Reads exactly `length` bytes. Only 1 publishes a source; 0 is unavailable and -1 is ambiguous or malformed.
# No JavaScript evaluation: only a standalone inline assignment to a JSON object.
unsafe fn youtube_metadata(markup: ptr<char>, length: i64, expected: string, out: ptr<YoutubeMetadata>) -> i64:
    if out == (0 as ptr<YoutubeMetadata>): return -1
    out.title[0] = '\0'
    out.media[0] = '\0'
    if markup == (0 as ptr<char>) or length < 0 or length > HTML_DOCUMENT_LIMIT or (expected as ptr<char>) == (0 as ptr<char>): return -1
    let script: YoutubeJsonSpan
    let located: i64 = youtube_metadata_script(markup, length, &script)
    if located <= 0: return located
    let json: YoutubeJson = YoutubeJson(markup, script.start, script.stop)
    let names: [3]string = ["playabilityStatus", "videoDetails", "streamingData"]
    let root: [3]YoutubeJsonSpan
    let parsed: i64 = youtube_json_fields(&json, &names[0], &root[0], 3)
    if parsed <= 0: return parsed
    youtube_json_take(&json, ';')
    youtube_json_space(&json)
    if json.at != json.stop: return -1

    let status_name: string = "status"
    let status: YoutubeJsonSpan
    parsed = youtube_json_members(markup, root[0], &status_name, &status, 1)
    if parsed <= 0: return parsed
    let state: [3]char
    if youtube_json_text(markup, status, &state[0], 3) != 2 or (&state[0]) as string != "OK": return 0

    let detail_names: [6]string = ["videoId", "title", "isPrivate", "isLive", "isLiveContent", "isUpcoming"]
    let details: [6]YoutubeJsonSpan
    parsed = youtube_json_members(markup, root[1], &detail_names[0], &details[0], 6)
    if parsed <= 0: return parsed
    for i in 2..6:
        let field: YoutubeJsonSpan = details[i]
        if field.start >= 0 and (field.stop - field.start != 5 or not html_match(markup, field.start, field.stop, "false")): return 0
    let id: [64]char
    let id_length: i64 = youtube_json_text(markup, details[0], &id[0], 64)
    if id_length <= 0: return 0
    let want: ptr<char> = expected as ptr<char>
    for i in 0..id_length:
        if id[i] != want[i]: return 0
    if want[id_length] != '\0': return 0
    if youtube_json_text(markup, details[1], &out.title[0], 513) < 0: out.title[0] = '\0'

    let formats_name: string = "formats"
    let formats: YoutubeJsonSpan
    parsed = youtube_json_members(markup, root[2], &formats_name, &formats, 1)
    if parsed <= 0: return parsed
    let choice: YoutubeMetadataChoice = YoutubeMetadataChoice(YoutubeJsonSpan(-1, -1), 0, 0, 0)
    parsed = youtube_metadata_formats(markup, formats, &choice)
    if parsed <= 0: return parsed
    if youtube_json_text(markup, choice.source, &out.media[0], 8193) <= 0:
        out.media[0] = '\0'
        return -1
    return 1
