use volt_lex

const ASM_TEXT: i64 = 0
const ASM_RO: i64 = 1
const ASM_DATA: i64 = 2
const ASM_BSS: i64 = 3

struct AsmObject:
    sections: [3]ByteBuffer
    alignments: [4]i64
    bss: i64
    section: i64
    names: i64
    fixups: i64
    debug_functions: i64
    debug_marks: i64
    debug_events: i64

struct AsmFixup:
    section: i64
    offset: i64
    symbol: i64
    addend: i64
    next: i64
    width: i64
    relative: bool

struct AsmSourceFunction:
    file: i64
    line: i64
    start: i64
    end: i64
    marks: i64
    title: i64
    params: i64
    scopes: i64

unsafe fn asm_setup(code: ptr<AsmObject>):
    code.names = cv_dict()
    code.fixups = cv_list()
    for i in 0..4: code.alignments[i] = 16

unsafe fn asm_buffer(code: ptr<AsmObject>) -> ptr<ByteBuffer>:
    return &code.sections[code.section]

unsafe fn asm_offset(code: ptr<AsmObject>) -> i64:
    if code.section == ASM_BSS: return code.bss
    return asm_buffer(code).len

unsafe fn cc_bytes_room(buf: ptr<ByteBuffer>, n: i64):
    if n < 0 or n > 268435456 or buf.len > 268435456 - n: panic("volt: binary section too large\n")
    if buf.len + n > buf.cap:
        if bytes_reserve(buf, buf.len + n) < 0: panic("volt: binary allocation failed\n")

unsafe fn cc_bytes_word(buf: ptr<ByteBuffer>, bits: u64, width: i64):
    cc_bytes_room(buf, width)
    for i in 0..width:
        buf.data[buf.len] = ((bits >> (i * 8)) & 255) as u8
        buf.len += 1

unsafe fn cc_bytes_append(buf: ptr<ByteBuffer>, data: ptr<char>, count: i64):
    cc_bytes_room(buf, count)
    cv_copy((buf.data + buf.len) as ptr<char>, data, count)
    buf.len += count

unsafe fn cc_bytes_set(buf: ptr<ByteBuffer>, at: i64, bits: u64, width: i64):
    if at < 0 or width < 0 or at + width > buf.len: panic("volt: binary fixup outside section\n")
    for i in 0..width: buf.data[at + i] = ((bits >> (i * 8)) & 255) as u8

unsafe native fn cc_fill(p: ptr<u8>, count: i64, value: u8):
{
    mov rcx, rsi
    mov al, dl
    cld
    rep stosb
}

unsafe fn cc_bytes_fill(buf: ptr<ByteBuffer>, count: i64, value: u8):
    if count == 0: return
    cc_bytes_room(buf, count)
    cc_fill(buf.data + buf.len, count, value)
    buf.len += count

unsafe fn asm_pad(code: ptr<AsmObject>, count: i64, value: u8):
    if count < 0 or count > 134217728: cc_error(cv_text("слишком большой размер секции"), 0, 0)
    if code.section == ASM_BSS:
        if code.bss > 134217728 - count: cc_error(cv_text("слишком большой размер секции"), 0, 0)
        code.bss += count
    else:
        cc_bytes_fill(asm_buffer(code), count, value)

unsafe fn asm_align(code: ptr<AsmObject>, n: i64):
    if n <= 0 or n > 4096 or n & (n - 1) != 0: cc_error(cv_text("неверное выравнивание"), 0, 0)
    code.alignments[code.section] = max(code.alignments[code.section], n)
    let fill: u8 = 0
    if code.section == ASM_TEXT: fill = 0x90
    asm_pad(code, (0 - asm_offset(code)) & (n - 1), fill)

unsafe fn asm_label(code: ptr<AsmObject>, name: i64):
    if cv_has(code.names, name): cc_error(cv_cat(cv_text("повторная метка "), name), 0, 0)
    cv_set(code.names, name, cv_pair(cv_i(code.section), cv_i(asm_offset(code))))

unsafe fn asm_debug_open(roots: i64, stack: i64, at: i64, vars: i64, declaration: i64):
    let scope: i64 = cv_node("DbgScope")
    cv_field(scope, "vars", vars)
    cv_field(scope, "children", cv_list())
    cv_field(scope, "start", at)
    cv_field(scope, "end", cv_i(-1))
    cv_field(scope, "declaration", declaration)
    if cv_len(stack) == 0:
        cv_push(roots, scope)
    else:
        cv_push(cv_getkey(cv_at(stack, -1), "children"), scope)
    cv_push(stack, scope)

# Inlined cleanup runs in the scope where the defer was registered, not in
# the scope of the return or break that triggered it. Keep common ancestors
# open and split only the ranges whose visible bindings change.
unsafe fn asm_debug_switch(roots: i64, stack: i64, target: i64, at: i64):
    let common: i64 = 0
    while common < cv_len(stack) and common < cv_len(target):
        if cv_getkey(cv_at(stack, common), "vars") != cv_getkey(cv_at(target, common), "vars"): break
        common += 1
    while cv_len(stack) > common:
        cv_field(cv_pop(stack), "end", at)
    for i in common..cv_len(target):
        let scope: i64 = cv_at(target, i)
        asm_debug_open(roots, stack, at, cv_getkey(scope, "vars"), cv_getkey(scope, "declaration"))

# A declaration adds a binding only after its initializer has run.
unsafe fn asm_debug_scopes(events: i64) -> i64:
    let roots: i64 = cv_list()
    let stack: i64 = cv_list()
    let defers: i64 = cv_dict()
    let resume: i64 = 0
    for i in 0..cv_len(events):
        let ev: i64 = cv_at(events, i)
        let tag: i64 = cv_at(ev, 0)
        let rest: i64 = cv_at(ev, 1)
        let payload: i64 = cv_at(rest, 0)
        let at: i64 = cv_at(rest, 1)
        if cv_name(tag, ".voltblk"):
            asm_debug_open(roots, stack, at, cv_list(), CV_FALSE)
        elif cv_name(tag, ".voltvar"):
            asm_debug_open(roots, stack, at, cv_single(payload), CV_TRUE)
        elif cv_name(tag, ".voltend"):
            while cv_len(stack) != 0:
                let scope: i64 = cv_pop(stack)
                cv_field(scope, "end", at)
                if not cv_truth(cv_getkey(scope, "declaration")): break
        elif cv_name(tag, ".voltdefer"):
            cv_set(defers, cv_i(payload), cv_aslist(stack))
        elif cv_name(tag, ".voltcleanup"):
            resume = cv_aslist(stack)
            asm_debug_switch(roots, stack, cv_get(defers, cv_i(payload), 0), at)
        elif cv_name(tag, ".voltresume"):
            asm_debug_switch(roots, stack, resume, at)
    return roots

unsafe fn asm_source_function(code: ptr<AsmObject>, name: i64, file: i64, line: i64, title: i64, fn_def: i64):
    # Statement markers and scope events accumulate per function; consume them even when no row is recorded.
    let marks: i64 = code.debug_marks
    code.debug_marks = cv_list()
    let events: i64 = code.debug_events
    code.debug_events = cv_list()
    let location: i64 = cv_get(code.names, name, 0)
    if file == 0 or line < 1 or location == 0 or cv_index(cv_at(location, 0)) != ASM_TEXT: return
    let start: i64 = cv_index(cv_at(location, 1))
    let end: i64 = code.sections[ASM_TEXT].len
    if end <= start: return
    let params: i64 = 0
    if fn_def != 0:
        let slots: i64 = cv_get(fn_def, cv_text("slots"), 0)
        if slots != 0:
            params = cv_list()
            for i in 0..cv_len(slots):
                let slot: i64 = cv_at(slots, i)
                if cv_name(cv_getkey(slot, "kind"), "param"): cv_push(params, slot)
    if title == 0: title = name
    let fn_range: ptr<AsmSourceFunction> = cv_alloc(sizeof(AsmSourceFunction)) as ptr<AsmSourceFunction>
    fn_range[0] = AsmSourceFunction(file, line, start, end, marks, title, params, asm_debug_scopes(events))
    cv_push(code.debug_functions, fn_range as i64)

unsafe fn asm_fixup(code: ptr<AsmObject>, name: i64, width: i64, relative: bool, addend: i64):
    let fix: ptr<AsmFixup> = cv_alloc(sizeof(AsmFixup)) as ptr<AsmFixup>
    fix.section = code.section
    fix.offset = asm_offset(code)
    fix.symbol = name
    fix.addend = addend
    fix.width = width
    fix.relative = relative
    cv_push(code.fixups, fix as i64)
    asm_pad(code, width, 0)

unsafe fn asm_word(code: ptr<AsmObject>, bits: u64, width: i64):
    cc_bytes_word(asm_buffer(code), bits, width)

unsafe fn asm_byte(code: ptr<AsmObject>, byte: i64):
    let buf: ptr<ByteBuffer> = asm_buffer(code)
    cc_bytes_room(buf, 1)
    buf.data[buf.len] = byte as u8
    buf.len += 1

unsafe fn cc_mod_of(file: i64) -> i64:
    let stem: i64 = cc_basename(file)
    if cv_ends(stem, cv_text(".volt")): stem = cv_subtext(stem, 0, cv_len(stem) - 5)
    let escape: bool = false
    for i in 0..cv_len(stem):
        let c: char = cv_byte(stem, i)
        if not cc_lex_letter(c) and not cc_lex_digit(c) and c != '.': escape = true
    if not escape: return stem
    let bytes: ptr<char> = cv_alloc(2 * cv_len(stem) + 2)
    let digits: ptr<char> = "0123456789abcdef" as ptr<char>
    bytes[0] = '$'
    for i in 0..cv_len(stem):
        let ch: i64 = cv_byte(stem, i) as i64
        bytes[1 + 2 * i] = digits[ch >> 4]
        bytes[2 + 2 * i] = digits[ch & 15]
    return cv_text(bytes as string)

unsafe fn cc_function_label(name: i64, file: i64) -> i64:
    return cv_cat(cv_cat(cv_text("VOLT_f_"), cc_mod_of(file)), cv_cat(cv_text("_"), name))

unsafe fn cc_global_label(name: i64, file: i64) -> i64:
    return cv_cat(cv_cat(cv_text("VOLT_g_"), cc_mod_of(file)), cv_cat(cv_text("_"), name))
