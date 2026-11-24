use host_files

unsafe fn cc_lex_digit(c: char) -> bool:
    return c >= '0' and c <= '9'

unsafe fn cc_lex_letter(c: char) -> bool:
    return c == '_' or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

unsafe fn cc_lex_token(tokens: i64, kind: string, value: i64, line: i64, indent: i64, floating: bool):
    let t: i64 = cv_dict()
    cv_field(t, "k", cv_text(kind))
    cv_field(t, "t", value)
    cv_field(t, "line", cv_i(line))
    cv_field(t, "ind", cv_i(indent))
    if floating: cv_field(t, "f", CV_TRUE)
    cv_push(tokens, t)

unsafe fn cc_escape(code: char, file: i64, line: i64, column: i64) -> char:
    if code == 'n': return '\n'
    if code == 't': return '\t'
    if code == 'r': return '\r'
    if code == '0': return '\0'
    if code == '\\' or code == '"' or code == '\'': return code
    cc_error_at(cv_cat(cv_text("неизвестный escape \\"), cv_char(code as i64)), file, cv_i(line), column)
    return '\0'

unsafe fn cc_utf8(p: ptr<char>, pos: ptr<i64>, length: i64) -> i64:
    let first: i64 = p[pos[0]] as i64
    pos[0] += 1
    if first < 128: return first
    let need: i64 = 0
    if first >= 240 and first <= 244: need = 3
    elif first >= 224 and first < 240: need = 2
    elif first >= 194 and first < 224: need = 1
    if need == 0 or pos[0] + need > length: return 65533
    let code: i64 = first & (127 >> (need + 1))
    for k in 0..need:
        let ch: i64 = p[pos[0]] as i64
        if ch & 192 != 128: return 65533
        pos[0] += 1
        code = code * 64 + (ch & 63)
    if code > 1114111 or (code >= 55296 and code <= 57343): return 65533
    if (need == 1 and code < 128) or (need == 2 and code < 2048) or (need == 3 and code < 65536): return 65533
    return code

unsafe fn cc_lex(source: i64, file: i64) -> i64:
    let out: i64 = cv_list()
    let p: ptr<char> = cv_cptr(source)
    let n: i64 = cv_len(source)
    let line: i64 = 1
    let begin: i64 = 0
    let pos: i64 = 0
    let keywords: i64 = cv_asset(cv_split(cv_text("fn let const defer if elif else while for in break continue unsafe return struct enum use extern as and or not true false sizeof alignof link native match mut"), 0, 0))
    let punct: i64 = cv_split(cv_text("<<= >>= ..= << >> <= >= == != -> .. += -= *= /= %= &= |= ^= + - * / % & | ^ < > = ( ) [ ] , . : ; ? { }"), 0, 0)
    while pos < n:
        let c: char = p[pos]
        if c == '\n':
            cc_lex_token(out, "nl", cv_text("\n"), line, -1, false)
            pos += 1
            begin = pos
            line += 1
            continue
        if c == ' ' or c == '\t' or c == '\r':
            pos += 1
            continue
        if c == '#' or (c == '/' and p[pos + 1] == '/'):
            while pos < n and p[pos] != '\n': pos += 1
            continue
        if c == '/' and p[pos + 1] == '*':
            let comment_line: i64 = line
            let comment_column: i64 = pos - begin + 1
            pos += 2
            while pos < n and (p[pos] != '*' or p[pos + 1] != '/'):
                if p[pos] == '\n':
                    line += 1
                    begin = pos + 1
                pos += 1
            if pos == n: cc_error_at(cv_text("незакрытый /* комментарий"), file, cv_i(comment_line), comment_column)
            pos += 2
            continue
        let ind: i64 = pos - begin
        let start: i64 = pos
        if c == '"':
            pos += 1
            let end: i64 = pos
            while end < n and p[end] != '"':
                if p[end] == '\\': end += 1
                if end == n or p[end] == '\n': break
                end += 1
            if end >= n or p[end] != '"': cc_error_at(cv_text("незакрытая строка"), file, cv_i(line), ind + 1)
            let text: ptr<char> = cv_alloc(end - pos + 1)
            let len: i64 = 0
            while pos < end:
                let ch: char = p[pos]
                let escape_column: i64 = pos - begin + 1
                pos += 1
                if ch == '\\':
                    ch = cc_escape(p[pos], file, line, escape_column)
                    pos += 1
                if ch == '\0': cc_error_at(cv_text("строковый литерал не может содержать NUL: строки завершаются NUL"), file, cv_i(line), escape_column)
                text[len] = ch
                len += 1
            pos += 1
            cc_lex_token(out, "str", cv_text(text as string), line, ind, false)
            continue
        if c == '\'':
            pos += 1
            let code: i64 = 0
            if pos >= n or p[pos] == '\n': cc_error_at(cv_text("незакрытый симв. литерал"), file, cv_i(line), ind + 1)
            if p[pos] == '\\':
                pos += 1
                if pos >= n or p[pos] == '\n': cc_error_at(cv_text("незакрытый симв. литерал"), file, cv_i(line), ind + 1)
                code = cc_escape(p[pos], file, line, pos - begin) as i64
                pos += 1
            else:
                code = cc_utf8(p, &pos, n)
            if p[pos] != '\'': cc_error_at(cv_text("незакрытый симв. литерал"), file, cv_i(line), ind + 1)
            if code > 255: cc_error_at(cv_text("char — один байт (0..255)"), file, cv_i(line), ind + 2)
            pos += 1
            cc_lex_token(out, "char", cv_char(code), line, ind, false)
            continue
        if cc_lex_digit(c):
            let floating: bool = false
            let base: i64 = 10
            if c == '0' and cv_ascii_lower(p[pos + 1]) == 'x': base = 16
            elif c == '0' and cv_ascii_lower(p[pos + 1]) == 'b': base = 2
            if base != 10:
                pos += 2
                let digits: i64 = 0
                while p[pos] == '_' or (cv_digit(p[pos]) >= 0 and cv_digit(p[pos]) < base):
                    if p[pos] != '_': digits += 1
                    pos += 1
                if digits == 0: cc_error_at(cv_text("в литерале ожидаются цифры"), file, cv_i(line), pos - begin + 1)
                if p[pos] == '.' and cc_lex_digit(p[pos + 1]):
                    cc_error_at(cv_text("некорректное число: точка допустима только в десятичном литерале"), file, cv_i(line), pos - begin + 1)
            else:
                while cc_lex_digit(p[pos]) or p[pos] == '_': pos += 1
                if p[pos] == '.' and cc_lex_digit(p[pos + 1]):
                    floating = true
                    pos += 1
                    while cc_lex_digit(p[pos]) or p[pos] == '_': pos += 1
                if p[pos] == 'e' or p[pos] == 'E':
                    floating = true
                    pos += 1
                    if p[pos] == '+' or p[pos] == '-': pos += 1
                    if not cc_lex_digit(p[pos]): cc_error_at(cv_text("в экспоненте ожидаются цифры"), file, cv_i(line), pos - begin + 1)
                    while cc_lex_digit(p[pos]): pos += 1
            let number: ptr<char> = cv_alloc(pos - start + 1)
            let count: i64 = 0
            for i in start..pos:
                if p[i] != '_':
                    number[count] = p[i]
                    count += 1
            cc_lex_token(out, "num", cv_text(number as string), line, ind, floating)
            continue
        let local_label: bool = c == '.' and cc_lex_letter(p[pos + 1]) and (pos == 0 or cv_ascii_space(p[pos - 1]))
        if cc_lex_letter(c) or local_label:
            pos += 1
            while cc_lex_letter(p[pos]) or cc_lex_digit(p[pos]): pos += 1
            let name: i64 = cv_subtext(source, start, pos - start)
            let kind: string = "id"
            if local_label: kind = "asmlabel"
            elif cv_has(keywords, name): kind = "kw"
            cc_lex_token(out, kind, name, line, ind, false)
            continue
        let matched: bool = false
        for i in 0..cv_len(punct):
            let spelling: i64 = cv_at(punct, i)
            let size: i64 = cv_len(spelling)
            if size <= n - pos and cc_prefix_bytes(p + pos, cv_cptr(spelling), size):
                cc_lex_token(out, "punct", spelling, line, ind, false)
                pos += size
                matched = true
                break
        if not matched: cc_error_at(cv_cat(cv_text("неожиданный символ "), cv_repr(cv_char(c as i64))), file, cv_i(line), ind + 1)
    return out

unsafe native fn cc_prefix_bytes(text: ptr<char>, prefix: ptr<char>, size: i64) -> bool:
{
    xor eax, eax
    xor ecx, ecx
.Llex_prefix:
    cmp rcx, rdx
    je .Llex_prefix_match
    mov r8b, byte ptr [rdi+rcx]
    cmp r8b, byte ptr [rsi+rcx]
    jne .Llex_prefix_done
    inc rcx
    jmp .Llex_prefix
.Llex_prefix_match:
    mov eax, 1
.Llex_prefix_done:
}
