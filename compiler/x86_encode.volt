use asm_object

const X_REG: i64 = 1
const X_XMM: i64 = 2
const X_MEM: i64 = 3
const X_IMM: i64 = 4
const X_LABEL: i64 = 5
const X_ST: i64 = 6

struct XOperand:
    kind: i64
    width: i64
    reg: i64
    index: i64
    scale: i64
    rip: bool
    imm: u64
    displacement: i64
    symbol: i64

let x_regs: i64 = 0
let x_conditions: i64 = 0
let x_simple: i64 = 0
let x_groups: i64 = 0

unsafe fn x_words(value: string) -> i64:
    return cv_split(cv_text(value), 0, 0)

unsafe fn x_table(table: i64, names: string, value: i64):
    let keys: i64 = x_words(names)
    for i in 0..cv_len(keys): cv_set(table, cv_at(keys, i), cv_i(value))

unsafe fn x_init():
    x_regs = cv_dict()
    let rows: i64 = cv_split(cv_text("al cl dl bl spl bpl sil dil r8b r9b r10b r11b r12b r13b r14b r15b;ax cx dx bx sp bp si di r8w r9w r10w r11w r12w r13w r14w r15w;eax ecx edx ebx esp ebp esi edi r8d r9d r10d r11d r12d r13d r14d r15d;rax rcx rdx rbx rsp rbp rsi rdi r8 r9 r10 r11 r12 r13 r14 r15;xmm0 xmm1 xmm2 xmm3 xmm4 xmm5 xmm6 xmm7 xmm8 xmm9 xmm10 xmm11 xmm12 xmm13 xmm14 xmm15"), cv_text(";"), 0)
    for row in 0..5:
        let names: i64 = cv_split(cv_at(rows, row), 0, 0)
        for i in 0..16: cv_set(x_regs, cv_at(names, i), cv_i((row + 1) * 16 + i))
    x_conditions = cv_dict()
    let codes: i64 = cv_split(cv_text("o;no;b c nae;ae nb nc;e z;ne nz;be na;a nbe;s;ns;p pe;np po;l nge;ge nl;le ng;g nle"), cv_text(";"), 0)
    for i in 0..16: x_table(x_conditions, cv_cptr(cv_at(codes, i)) as string, i)
    x_simple = cv_dict()
    let instructions: i64 = x_words("ret leave cld nop cqo cdq syscall ud2 pause fld1 fsin fcos fptan fpatan fyl2x movsb stosb")
    let opcodes: [17]i64 = [0xc3, 0xc9, 0xfc, 0x90, 0x4899, 0x99, 0x0f05, 0x0f0b, 0xf390, 0xd9e8, 0xd9fe, 0xd9ff, 0xd9f2, 0xd9f3, 0xd9f1, 0xa4, 0xaa]
    for i in 0..len(opcodes): cv_set(x_simple, cv_at(instructions, i), cv_i(opcodes[i]))
    x_groups = cv_dict()
    let groups: i64 = x_words("add or adc sbb and sub xor cmp")
    for i in 0..8: cv_set(x_groups, cv_at(groups, i), cv_i(i))

unsafe fn x_require(pass: bool, reason: string):
    if not pass: cc_error(cv_cat(cv_text("x86-64: "), cv_text(reason)), 0, 0)

unsafe fn x_symbol(v: i64) -> bool:
    if cv_len(v) == 0: return false
    for i in 0..cv_len(v):
        let c: char = cv_byte(v, i)
        if c != '.' and c != '$' and not cc_lex_letter(c) and not cc_lex_digit(c): return false
    return true

unsafe fn x_number(value: i64) -> i64:
    let n: i64 = cv_len(value)
    if n == 0: return 0
    let data: ptr<char> = cv_cptr(value)
    let pos: i64 = 0
    let negative: bool = data[0] == '-'
    if negative or data[0] == '+':
        pos += 1
        while pos < n and cv_ascii_space(data[pos]): pos += 1
    if pos == n or not cc_lex_digit(data[pos]): return 0
    let base: u64 = 10
    if n - pos > 1 and data[pos] == '0':
        let next: char = cv_ascii_lower(data[pos + 1])
        if next == 'x':
            base = 16
            pos += 2
        elif next == 'b':
            base = 2
            pos += 2
        else:
            base = 8
    if pos == n: return 0
    let v: u64 = 0
    while pos < n:
        let number: i64 = cv_digit(data[pos])
        if number < 0 or (number as u64) >= base: return 0
        if v > (0xffffffffffffffff - (number as u64)) / base: return 0
        v = v * base + (number as u64)
        pos += 1
    if negative and v > 0x8000000000000000: return 0
    return cv_words(v, 0, negative)

unsafe fn x_bits(v: i64) -> u64:
    let n: CVWide = cv_wide(v)
    if n.negative: return cv_usub(0, n.low)
    return n.low

unsafe native fn x_signed(bits: u64) -> i64:
{
    mov rax, rdi
}

unsafe fn x_fits(value: i64, width: i64) -> bool:
    let bound: i64 = 1 << (width * 8 - 1)
    return value >= 0 - bound and value < bound

unsafe fn x_immediate(value: u64, width: i64) -> bool:
    return width == 8 or value < ((1 as u64) << (8 * width)) or x_fits(x_signed(value), width)

unsafe fn x_register(spell: i64, arg: ptr<XOperand>) -> bool:
    let tag: i64 = cv_get(x_regs, cv_lower(spell), 0)
    if tag == 0: return false
    let reg: i64 = cv_index(tag)
    arg.kind = X_REG
    arg.reg = reg % 16
    arg.width = 1 << (reg / 16 - 1)
    if arg.width == 16: arg.kind = X_XMM
    arg.index = -1
    return true

unsafe fn x_memory(input: i64, open: i64, arg: ptr<XOperand>):
    arg.kind = X_MEM
    arg.reg = -1
    arg.index = -1
    let prefix: i64 = cv_split(cv_subtext(input, 0, open), 0, 0)
    if cv_len(prefix) > 0:
        x_require(cv_len(prefix) == 2 and cv_name(cv_lower(cv_at(prefix, 1)), "ptr"), "ожидалось ptr после размера операнда")
        let size: i64 = cv_lower(cv_at(prefix, 0))
        if cv_name(size, "byte"): arg.width = 1
        elif cv_name(size, "word"): arg.width = 2
        elif cv_name(size, "dword"): arg.width = 4
        elif cv_name(size, "qword"): arg.width = 8
        elif cv_name(size, "xmmword"): arg.width = 16
        else: x_require(false, "неизвестный размер операнда памяти")
    let n: i64 = cv_len(input)
    x_require(cv_byte(input, n - 1) == ']', "ожидалось ]")
    let pieces: ptr<char> = cv_alloc(n - open)
    let count: i64 = 0
    for i in (open + 1)..(n - 1):
        let c: char = cv_byte(input, i)
        if not cv_ascii_space(c):
            pieces[count] = c
            count += 1
    let cursor: i64 = 0
    let negative: bool = false
    let source: i64 = cv_text(pieces as string)
    while cursor < count:
        let start: i64 = cursor
        while cursor < count and pieces[cursor] != '+' and pieces[cursor] != '-': cursor += 1
        x_require(cursor > start, "пустой член адреса")
        let term: i64 = cv_subtext(source, start, cursor - start)
        let star: i64 = cv_find(term, cv_text("*"), 0)
        let regname: i64 = term
        if star >= 0: regname = cv_subtext(term, 0, star)
        let reg: XOperand
        if cv_name(cv_lower(term), "rip"):
            x_require(not negative and not arg.rip, "неверная RIP-адресация")
            arg.rip = true
        elif x_register(regname, &reg):
            x_require(not negative and reg.kind == X_REG and reg.width == 8, "ожидался 64-битный регистр адреса")
            if star < 0 and arg.reg < 0:
                arg.reg = reg.reg
            else:
                x_require(arg.index < 0 and reg.reg != 4, "неверный индекс адреса")
                arg.index = reg.reg
                if star >= 0:
                    let scale: i64 = x_number(cv_subtext(term, star + 1, cv_len(term) - star - 1))
                    x_require(scale != 0, "неверный масштаб адреса")
                    let size: i64 = cv_index(scale)
                    if size == 8: arg.scale = 3
                    elif size == 4: arg.scale = 2
                    elif size == 2: arg.scale = 1
                    else: x_require(size == 1, "неверный масштаб адреса")
        else:
            let number: i64 = x_number(term)
            if number != 0:
                x_require(cv_le(number, cv_i(2147483648)), "смещение адреса вне диапазона")
                let delta: i64 = cv_index(number)
                if negative: arg.displacement -= delta
                else: arg.displacement += delta
            else:
                x_require(not negative and arg.symbol == 0 and x_symbol(term), "неверный символ в адресе")
                arg.symbol = term
        if cursor == count: break
        negative = pieces[cursor] == '-'
        cursor += 1
        x_require(cursor < count, "незавершённый адрес")
    x_require(x_fits(arg.displacement, 4), "смещение адреса вне диапазона")
    x_require(not arg.rip or (arg.reg < 0 and arg.index < 0), "RIP-адрес не может содержать другие регистры")
    x_require(arg.symbol == 0 or arg.rip, "для символа в памяти требуется [rip+символ]")
    x_require(arg.rip or arg.reg >= 0 or arg.index >= 0, "ожидался регистр адреса")

unsafe fn x_operand(raw: i64, arg: ptr<XOperand>):
    let input: i64 = cv_strip(raw)
    x_require(cv_len(input) > 0, "пустой операнд")
    let bracket: i64 = cv_find(input, cv_text("["), 0)
    if bracket >= 0:
        x_memory(input, bracket, arg)
        return
    if x_register(input, arg): return
    arg.reg = -1
    arg.index = -1
    let number: i64 = x_number(input)
    if number != 0:
        arg.kind = X_IMM
        arg.imm = x_bits(number)
    elif cv_len(input) == 3 and cv_byte(input, 0) == '\'' and cv_byte(input, 2) == '\'':
        arg.kind = X_IMM
        arg.imm = cv_byte(input, 1) as u64
    elif cv_name(input, "st(0)") or cv_name(input, "st ( 0 )"):
        arg.kind = X_ST
    else:
        x_require(x_symbol(input) and not cc_lex_digit(cv_byte(input, 0)), "недопустимый операнд")
        arg.kind = X_LABEL
        arg.symbol = input

unsafe fn x_reg(arg: ptr<XOperand>) -> bool:
    return arg.kind == X_REG

unsafe fn x_gpr(arg: ptr<XOperand>) -> bool:
    return arg.kind == X_REG or arg.kind == X_MEM

unsafe fn x_float_operand(arg: ptr<XOperand>) -> bool:
    return arg.kind == X_XMM or arg.kind == X_MEM

unsafe fn x_byte_reg(arg: ptr<XOperand>) -> bool:
    return arg.kind == X_REG and arg.width == 1 and arg.reg >= 4

unsafe fn x_width(a: ptr<XOperand>, b: ptr<XOperand>) -> i64:
    x_require(x_gpr(a) and x_gpr(b), "ожидались целочисленные операнды")
    let width: i64 = a.width
    if width == 0: width = b.width
    x_require(width >= 1 and width <= 8 and (b.width == 0 or b.width == width), "несовместимые размеры операндов")
    return width

unsafe fn x_rex(code: ptr<AsmObject>, width: i64, reg: i64, base: i64, index: i64, low: bool):
    let rex: i64 = 0x40
    if width == 8: rex |= 8
    if reg >= 8: rex |= 4
    if index >= 8: rex |= 2
    if base >= 8: rex |= 1
    if rex != 0x40 or low: asm_byte(code, rex)

unsafe fn x_modrm(code: ptr<AsmObject>, reg: i64, b: ptr<XOperand>):
    let r: i64 = (reg & 7) << 3
    if b.kind != X_MEM:
        asm_byte(code, 0xc0 | r | (b.reg & 7))
        return
    if b.rip:
        asm_byte(code, r | 5)
        if b.symbol == 0: asm_word(code, x_bits(cv_i(b.displacement)), 4)
        else: asm_fixup(code, b.symbol, 4, true, b.displacement)
        return
    let sib: bool = b.index >= 0 or b.reg < 0 or b.reg & 7 == 4
    let mode: i64 = 0
    if b.reg >= 0 and (b.displacement != 0 or b.reg & 7 == 5):
        mode = 2
        if x_fits(b.displacement, 1): mode = 1
    let rm: i64 = b.reg & 7
    if sib: rm = 4
    asm_byte(code, (mode << 6) | r | rm)
    if sib:
        let index: i64 = b.index & 7
        let base: i64 = b.reg & 7
        if b.index < 0: index = 4
        if b.reg < 0: base = 5
        asm_byte(code, (b.scale << 6) | (index << 3) | base)
    if mode != 0 or b.reg < 0:
        let width: i64 = 4
        if mode == 1: width = 1
        asm_word(code, x_bits(cv_i(b.displacement)), width)

unsafe fn x_bytes(code: ptr<AsmObject>, packed: i64):
    if packed > 255: asm_byte(code, packed >> 8)
    asm_byte(code, packed & 255)

# format: low 8 bits legacy prefix, bit 8 forces REX for the low-byte GPRs.
unsafe fn x_encode_rm(code: ptr<AsmObject>, opcode: i64, width: i64, reg: i64, b: ptr<XOperand>, format: i64):
    x_require(x_gpr(b) or b.kind == X_XMM, "ожидался регистр или операнд памяти")
    if format & 255 != 0: asm_byte(code, format & 255)
    elif width == 2: asm_byte(code, 0x66)
    x_rex(code, width, reg, b.reg, b.index, format & 256 != 0 or x_byte_reg(b))
    x_bytes(code, opcode)
    x_modrm(code, reg, b)

unsafe fn x_low(arg: ptr<XOperand>) -> i64:
    if x_byte_reg(arg): return 256
    return 0

unsafe fn x_move(code: ptr<AsmObject>, a: ptr<XOperand>, b: ptr<XOperand>):
    if b.kind == X_IMM:
        let width: i64 = a.width
        x_require(x_gpr(a) and width >= 1 and width <= 8, "mov: нужен целочисленный операнд с размером")
        x_require(x_immediate(b.imm, width), "mov: константа вне диапазона")
        let small: bool = width == 8 and x_fits(x_signed(b.imm), 4)
        if a.kind == X_REG and not small:
            if width == 2: asm_byte(code, 0x66)
            x_rex(code, width, -1, a.reg, -1, x_byte_reg(a))
            let op: i64 = 0xb8
            if width == 1: op = 0xb0
            asm_byte(code, op + (a.reg & 7))
            asm_word(code, b.imm, width)
        else:
            x_require(width != 8 or small, "mov: память принимает только знаковую imm32")
            let op: i64 = 0xc7
            if width == 1: op = 0xc6
            x_encode_rm(code, op, width, 0, a, 0)
            asm_word(code, b.imm, min(width, 4))
        return
    let width: i64 = x_width(a, b)
    let other: i64 = 0
    if width != 1: other = 1
    if b.kind == X_REG: x_encode_rm(code, 0x88 + other, width, b.reg, a, x_low(b))
    elif a.kind == X_REG: x_encode_rm(code, 0x8a + other, width, a.reg, b, x_low(a))
    else: x_require(false, "mov: ожидался регистр")

unsafe fn x_alu(code: ptr<AsmObject>, group: i64, a: ptr<XOperand>, b: ptr<XOperand>):
    if b.kind == X_IMM:
        let width: i64 = a.width
        x_require(x_gpr(a) and width >= 1 and width <= 8, "нужен целочисленный операнд с размером")
        if width == 8: x_require(x_fits(x_signed(b.imm), 4), "константа операции вне диапазона")
        else: x_require(x_immediate(b.imm, width), "константа операции вне диапазона")
        let small: bool = x_fits(x_signed(b.imm), 1)
        let op: i64 = 0x81
        let imm_width: i64 = min(width, 4)
        if width == 1: op = 0x80
        elif small:
            op = 0x83
            imm_width = 1
        x_encode_rm(code, op, width, group, a, 0)
        asm_word(code, b.imm, imm_width)
    else:
        let width: i64 = x_width(a, b)
        let op: i64 = group * 8
        if width != 1: op += 1
        if b.kind == X_REG: x_encode_rm(code, op, width, b.reg, a, x_low(b))
        elif a.kind == X_REG: x_encode_rm(code, op + 2, width, a.reg, b, x_low(a))
        else: x_require(false, "ожидался регистр")

unsafe fn x_count(got: i64, want: i64):
    x_require(got == want, "неверное число операндов")

unsafe fn x_cc(name: i64, prefix: string) -> i64:
    let n: i64 = str_len(prefix)
    if not cv_starts(name, cv_text(prefix)): return -1
    let c: i64 = cv_get(x_conditions, cv_subtext(name, n, cv_len(name) - n), 0)
    if c == 0: return -1
    return cv_index(c)

unsafe fn x_sse(code: ptr<AsmObject>, name: i64, a: ptr<XOperand>, b: ptr<XOperand>)-> bool:
    let opcode: i64 = 0
    let prefix: i64 = 0x66
    if cv_name(name, "xorpd"): opcode = 0x57
    elif cv_name(name, "andpd"): opcode = 0x54
    elif cv_name(name, "ucomisd"): opcode = 0x2e
    elif cv_name(name, "ucomiss"):
        opcode = 0x2e
        prefix = 0
    elif cv_name(name, "cvtsd2ss"):
        opcode = 0x5a
        prefix = 0xf2
    elif cv_name(name, "cvtss2sd"):
        opcode = 0x5a
        prefix = 0xf3
    if opcode != 0:
        x_require(a.kind == X_XMM and x_float_operand(b), "SSE: ожидались xmm и xmm/память")
        x_encode_rm(code, 0xf00 | opcode, 0, a.reg, b, prefix)
        return true
    let single: bool = cv_ends(name, cv_text("ss"))
    if not single and not cv_ends(name, cv_text("sd")): return false
    prefix = 0xf2
    let width: i64 = 8
    if single:
        prefix = 0xf3
        width = 4
    let op: i64 = cv_subtext(name, 0, cv_len(name) - 2)
    if cv_name(op, "cvtsi2"):
        x_require(a.kind == X_XMM and x_gpr(b) and (b.width == 4 or b.width == 8), "cvtsi2s: неверные операнды")
        x_encode_rm(code, 0x0f2a, b.width, a.reg, b, prefix)
        return true
    if cv_name(op, "mov") and a.kind == X_MEM:
        x_require(b.kind == X_XMM and (a.width == 0 or a.width == width), "movs: неверные операнды")
        x_encode_rm(code, 0x0f11, 0, b.reg, a, prefix)
        return true
    if cv_name(op, "mov"): opcode = 0x10
    elif cv_name(op, "add"): opcode = 0x58
    elif cv_name(op, "sub"): opcode = 0x5c
    elif cv_name(op, "mul"): opcode = 0x59
    elif cv_name(op, "div"): opcode = 0x5e
    elif cv_name(op, "min"): opcode = 0x5d
    elif cv_name(op, "max"): opcode = 0x5f
    elif cv_name(op, "sqrt"): opcode = 0x51
    if opcode == 0: return false
    x_require(a.kind == X_XMM and x_float_operand(b) and (b.kind == X_XMM or b.width == 0 or b.width == width), "неверные операнды SSE")
    x_encode_rm(code, 0xf00 | opcode, 0, a.reg, b, prefix)
    return true

unsafe fn x_dispatch(code: ptr<AsmObject>, name: i64, args: ptr<XOperand>, argc: i64):
    let a: ptr<XOperand> = args
    let b: ptr<XOperand> = args + 1
    let c: ptr<XOperand> = args + 2
    let simple: i64 = cv_get(x_simple, name, 0)
    if simple != 0:
        x_count(argc, 0)
        x_bytes(code, cv_index(simple))
        return
    if cv_name(name, "mov"):
        x_count(argc, 2)
        x_move(code, a, b)
        return
    if cv_name(name, "lea"):
        x_count(argc, 2)
        x_require(x_reg(a) and a.width >= 2 and b.kind == X_MEM, "lea: ожидались регистр и адрес")
        x_encode_rm(code, 0x8d, a.width, a.reg, b, 0)
        return
    if cv_name(name, "movsx") or cv_name(name, "movsxd") or cv_name(name, "movzx"):
        x_count(argc, 2)
        x_require(x_reg(a) and x_gpr(b) and b.width > 0 and a.width > b.width, "movsx/movzx: неверный размер")
        let zero: bool = cv_name(name, "movzx")
        if b.width == 4 and not zero:
            x_encode_rm(code, 0x63, a.width, a.reg, b, 0)
        else:
            x_require(b.width <= 2 and not cv_name(name, "movsxd"), "movsx/movzx: неверный источник")
            let op: i64 = 0x0fbe
            if zero: op = 0x0fb6
            if b.width == 2: op += 1
            x_encode_rm(code, op, a.width, a.reg, b, 0)
        return
    if cv_name(name, "push") or cv_name(name, "pop"):
        x_count(argc, 1)
        x_require(x_reg(a) and a.width == 8, "push/pop: ожидался 64-битный регистр")
        x_rex(code, 0, -1, a.reg, -1, false)
        let op: i64 = 0x50
        if cv_name(name, "pop"): op = 0x58
        asm_byte(code, op + (a.reg & 7))
        return
    if cv_name(name, "call") or cv_name(name, "jmp"):
        x_count(argc, 1)
        let call: bool = cv_name(name, "call")
        if a.kind == X_LABEL:
            let op: i64 = 0xe9
            if call: op = 0xe8
            asm_byte(code, op)
            asm_fixup(code, a.symbol, 4, true, 0)
        else:
            x_require(x_gpr(a) and (a.width == 0 or a.width == 8), "call/jmp: ожидалась метка или 64-битный операнд")
            let group: i64 = 4
            if call: group = 2
            x_encode_rm(code, 0xff, 0, group, a, 0)
        return
    let condition: i64 = x_cc(name, "j")
    if condition >= 0:
        x_count(argc, 1)
        x_require(a.kind == X_LABEL, "условный переход требует метку")
        x_bytes(code, 0x0f80 + condition)
        asm_fixup(code, a.symbol, 4, true, 0)
        return
    condition = x_cc(name, "set")
    if condition >= 0:
        x_count(argc, 1)
        x_require(x_gpr(a) and (a.width == 0 or a.width == 1), "setcc: ожидался байт")
        x_encode_rm(code, 0x0f90 + condition, 1, 0, a, 0)
        return
    condition = x_cc(name, "cmov")
    if condition >= 0:
        x_count(argc, 2)
        x_require(x_reg(a) and a.width >= 2, "cmovcc: ожидался регистр назначения")
        x_encode_rm(code, 0x0f40 + condition, x_width(a, b), a.reg, b, 0)
        return
    let group: i64 = cv_get(x_groups, name, 0)
    if group != 0:
        x_count(argc, 2)
        x_alu(code, cv_index(group), a, b)
        return
    if cv_name(name, "test") or cv_name(name, "xchg") or cv_name(name, "cmpxchg"):
        x_count(argc, 2)
        let op: i64 = 0x84
        if cv_name(name, "xchg"): op = 0x86
        if cv_name(name, "cmpxchg"): op = 0x0fb0
        if op == 0x84 and b.kind == X_IMM:
            x_require(x_gpr(a) and a.width >= 1 and a.width <= 8, "test: нужен операнд с размером")
            if a.width == 8: x_require(x_fits(x_signed(b.imm), 4), "test: константа вне диапазона")
            else: x_require(x_immediate(b.imm, a.width), "test: константа вне диапазона")
            op = 0xf7
            if a.width == 1: op = 0xf6
            x_encode_rm(code, op, a.width, 0, a, 0)
            asm_word(code, b.imm, min(a.width, 4))
        else:
            x_require(x_reg(b), "ожидался регистр источника")
            let width: i64 = x_width(a, b)
            if width != 1: op += 1
            x_encode_rm(code, op, width, b.reg, a, x_low(b))
        return
    if cv_name(name, "imul") and argc > 1:
        x_require(x_reg(a) and a.width >= 2, "imul: ожидался регистр назначения")
        let width: i64 = x_width(a, b)
        if argc == 2:
            x_encode_rm(code, 0x0faf, width, a.reg, b, 0)
        else:
            x_count(argc, 3)
            x_require(c.kind == X_IMM and x_fits(x_signed(c.imm), min(width, 4)), "imul: константа вне диапазона")
            let op: i64 = 0x69
            let imm_width: i64 = min(width, 4)
            if x_fits(x_signed(c.imm), 1):
                op = 0x6b
                imm_width = 1
            x_encode_rm(code, op, width, a.reg, b, 0)
            asm_word(code, c.imm, imm_width)
        return
    let unary: i64 = -1
    if cv_name(name, "not"): unary = 2
    elif cv_name(name, "neg"): unary = 3
    elif cv_name(name, "mul"): unary = 4
    elif cv_name(name, "imul"): unary = 5
    elif cv_name(name, "div"): unary = 6
    elif cv_name(name, "idiv"): unary = 7
    if unary >= 0:
        x_count(argc, 1)
        x_require(x_gpr(a) and a.width >= 1 and a.width <= 8, "нужен целочисленный операнд с размером")
        let op: i64 = 0xf7
        if a.width == 1: op = 0xf6
        x_encode_rm(code, op, a.width, unary, a, 0)
        return
    if cv_name(name, "inc") or cv_name(name, "dec"):
        x_count(argc, 1)
        x_require(x_gpr(a) and a.width >= 1 and a.width <= 8, "нужен целочисленный операнд с размером")
        let op: i64 = 0xff
        let slot: i64 = 0
        if a.width == 1: op = 0xfe
        if cv_name(name, "dec"): slot = 1
        x_encode_rm(code, op, a.width, slot, a, 0)
        return
    let shift: i64 = -1
    if cv_name(name, "shl") or cv_name(name, "sal"): shift = 4
    elif cv_name(name, "shr"): shift = 5
    elif cv_name(name, "sar"): shift = 7
    if shift >= 0:
        x_count(argc, 2)
        x_require(x_gpr(a) and a.width >= 1 and a.width <= 8, "сдвиг требует целочисленный операнд")
        let op: i64 = 0xc1
        if a.width == 1: op = 0xc0
        if x_reg(b):
            x_require(b.reg == 1 and b.width == 1, "сдвиг: ожидался cl")
            x_encode_rm(code, op + 0x12, a.width, shift, a, 0)
        else:
            x_require(b.kind == X_IMM and b.imm <= 255, "сдвиг: неверная константа")
            x_encode_rm(code, op, a.width, shift, a, 0)
            asm_byte(code, b.imm as i64)
        return
    if cv_name(name, "bts"):
        x_count(argc, 2)
        x_require(x_gpr(a) and a.width >= 2 and a.width <= 8 and b.kind == X_IMM and b.imm <= 255, "bts: неверные операнды")
        x_encode_rm(code, 0x0fba, a.width, 5, a, 0)
        asm_byte(code, b.imm as i64)
        return
    if cv_name(name, "fld") or cv_name(name, "fstp"):
        x_count(argc, 1)
        let load: bool = cv_name(name, "fld")
        if not load and a.kind == X_ST:
            x_bytes(code, 0xddd8)
            return
        x_require(a.kind == X_MEM and (a.width == 4 or a.width == 8), "x87: ожидался dword/qword ptr")
        let op: i64 = 0xdd
        let slot: i64 = 3
        if a.width == 4: op = 0xd9
        if load: slot = 0
        x_encode_rm(code, op, 0, slot, a, 0)
        return
    if cv_name(name, "cvttsd2si") or cv_name(name, "cvttss2si"):
        x_count(argc, 2)
        x_require(x_reg(a) and (a.width == 4 or a.width == 8) and x_float_operand(b), "cvtts2si: неверные операнды")
        let prefix: i64 = 0xf2
        if cv_name(name, "cvttss2si"): prefix = 0xf3
        x_encode_rm(code, 0x0f2c, a.width, a.reg, b, prefix)
        return
    if argc == 2 and x_sse(code, name, a, b): return
    cc_error(cv_cat(cv_text("x86-64: неподдерживаемая инструкция "), name), 0, 0)

unsafe fn x_string_data(code: ptr<AsmObject>, arg: i64):
    let n: i64 = cv_len(arg)
    x_require(code.section != ASM_BSS and n >= 2 and cv_byte(arg, 0) == '"' and cv_byte(arg, n - 1) == '"', "ожидалась строка в инициализированной секции")
    let i: i64 = 1
    while i < n - 1:
        let c: i64 = cv_byte(arg, i) as i64
        i += 1
        if c == 92:
            x_require(i < n - 1, "незаконченный escape в .string")
            c = cv_byte(arg, i) as i64
            i += 1
            if c >= 48 and c <= 55:
                c -= 48
                for digit in 0..2:
                    if i >= n - 1: break
                    let d: i64 = cv_byte(arg, i) as i64
                    if d < 48 or d > 55: break
                    i += 1
                    c = c * 8 + d - 48
            elif c == 110: c = 10
            elif c == 114: c = 13
            elif c == 116: c = 9
        x_require(c <= 255, "байт строки вне диапазона")
        asm_byte(code, c)
    asm_byte(code, 0)

unsafe fn x_directive(code: ptr<AsmObject>, name: i64, rest: i64):
    if cv_name(name, ".globl") or cv_name(name, ".global") or cv_name(name, ".intel_syntax"): return
    if cv_name(name, ".section"):
        if cv_starts(rest, cv_text(".note.GNU-stack")): return
        x_directive(code, rest, cv_text(""))
        return
    if cv_name(name, ".text"):
        code.section = ASM_TEXT
        return
    if cv_name(name, ".rodata"):
        code.section = ASM_RO
        return
    if cv_name(name, ".data"):
        code.section = ASM_DATA
        return
    if cv_name(name, ".bss"):
        code.section = ASM_BSS
        return
    if cv_name(name, ".string") or cv_name(name, ".asciz"):
        x_string_data(code, rest)
        return
    if cv_name(name, ".align") or cv_name(name, ".balign") or cv_name(name, ".space") or cv_name(name, ".zero"):
        let n: i64 = x_number(rest)
        x_require(n != 0, "директива требует число")
        if cv_name(name, ".align") or cv_name(name, ".balign"): asm_align(code, cv_index(n))
        else: asm_pad(code, cv_index(n), 0)
        return
    if cv_name(name, ".lcomm"):
        let params: i64 = cv_split(rest, cv_text(","), 0)
        x_require(cv_len(params) == 2, "ожидалось .lcomm имя, размер")
        let n: i64 = x_number(cv_strip(cv_at(params, 1)))
        let tag: i64 = cv_strip(cv_at(params, 0))
        x_require(n != 0 and x_symbol(tag), "неверный .lcomm")
        let previous: i64 = code.section
        code.section = ASM_BSS
        let size: i64 = cv_index(n)
        let align: i64 = 1
        while align < 16 and align * 2 <= size: align *= 2
        asm_align(code, align)
        asm_label(code, tag)
        asm_pad(code, size, 0)
        code.section = previous
        return
    let width: i64 = 0
    if cv_name(name, ".byte"): width = 1
    elif cv_name(name, ".word"): width = 2
    elif cv_name(name, ".long"): width = 4
    elif cv_name(name, ".quad"): width = 8
    if width != 0:
        let values: i64 = cv_split(rest, cv_text(","), 0)
        for i in 0..cv_len(values):
            let v: i64 = cv_strip(cv_at(values, i))
            let num: i64 = x_number(v)
            if num != 0:
                let bits: u64 = x_bits(num)
                x_require(x_immediate(bits, width), "константа директивы вне диапазона")
                if code.section == ASM_BSS:
                    x_require(bits == 0, "секция .bss допускает только нули")
                    asm_pad(code, width, 0)
                else: asm_word(code, bits, width)
            else:
                x_require(code.section != ASM_BSS and x_symbol(v), "ожидались число или метка")
                asm_fixup(code, v, width, false, 0)
        return
    cc_error(cv_cat(cv_text("x86-64: неподдерживаемая директива "), name), 0, 0)

unsafe fn x_line(code: ptr<AsmObject>, statement: i64):
    let line: i64 = cv_strip(statement)
    if cv_len(line) == 0: return
    let colon: i64 = cv_find(line, cv_text(":"), 0)
    if colon >= 0:
        let label: i64 = cv_strip(cv_subtext(line, 0, colon))
        if x_symbol(label):
            asm_label(code, label)
            line = cv_strip(cv_subtext(line, colon + 1, cv_len(line) - colon - 1))
            if cv_len(line) == 0: return
    let words: i64 = cv_split(line, 0, cv_i(1))
    let name: i64 = cv_lower(cv_at(words, 0))
    let rest: i64 = cv_text("")
    if cv_len(words) > 1: rest = cv_at(words, 1)
    if cv_byte(name, 0) == '.':
        x_directive(code, name, rest)
        return
    x_require(code.section == ASM_TEXT, "инструкции допустимы только в .text")
    let prefix: i64 = 0
    if cv_name(name, "lock") or cv_name(name, "rep"):
        prefix = 0xf0
        if cv_name(name, "rep"): prefix = 0xf3
        words = cv_split(rest, 0, cv_i(1))
        x_require(cv_len(words) > 0, "после префикса ожидается инструкция")
        name = cv_lower(cv_at(words, 0))
        rest = cv_text("")
        if cv_len(words) > 1: rest = cv_at(words, 1)
    let operands: [3]XOperand
    let argc: i64 = 0
    if cv_len(rest) != 0:
        let args: i64 = cv_split(rest, cv_text(","), 0)
        argc = cv_len(args)
        x_require(argc <= 3, "слишком много операндов")
        for i in 0..argc: x_operand(cv_at(args, i), &operands[i])
    if prefix != 0:
        if prefix == 0xf3: x_require(cv_name(name, "movsb") or cv_name(name, "stosb"), "неверный префикс инструкции")
        else: x_require(cv_name(name, "cmpxchg") and argc == 2 and operands[0].kind == X_MEM, "неверный префикс инструкции")
        asm_byte(code, prefix)
    let first_fixup: i64 = cv_len(code.fixups)
    x_dispatch(code, name, &operands[0], argc)
    for i in first_fixup..cv_len(code.fixups):
        let f: ptr<AsmFixup> = cv_at(code.fixups, i) as ptr<AsmFixup>
        f.next = asm_offset(code)

unsafe fn x_encode(code: ptr<AsmObject>, line: i64):
    let n: i64 = cv_len(line)
    let p: ptr<char> = cv_cptr(line)
    let start: i64 = 0
    let escaped: bool = false
    let quote: char = '\0'
    for i in 0..n:
        let ch: char = p[i]
        if escaped:
            escaped = false
        elif quote != '\0':
            if ch == '\\': escaped = true
            elif ch == quote: quote = '\0'
        elif ch == '"' or ch == '\'':
            quote = ch
        elif ch == '#':
            x_line(code, cv_subtext(line, start, i - start))
            return
        elif ch == ';':
            x_line(code, cv_subtext(line, start, i - start))
            start = i + 1
    if start == 0: x_line(code, line)
    else: x_line(code, cv_subtext(line, start, n - start))
