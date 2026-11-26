# VOLT compiler, native self-hosted implementation.
use asm_object
use volt_types

# Line programs start at line 1; statement lines can move backwards, so the
# signed path must encode negative deltas correctly.
unsafe fn dwarf_leb(out: ptr<ByteBuffer>, value: i64, signed: bool):
    if signed:
        # Signed LEB128: sign-extending shift, stop when the sign bit fits.
        let more: bool = true
        while more:
            let byte: i64 = value & 127
            value >>= 7
            if (value == 0 and byte & 64 == 0) or (value == -1 and byte & 64 != 0):
                more = false
            else:
                byte = byte | 128
            cc_bytes_word(out, byte as u64, 1)
        return
    while value >= 128:
        cc_bytes_word(out, ((value & 127) | 128) as u64, 1)
        value >>= 7
    cc_bytes_word(out, value as u64, 1)

unsafe fn dwarf_string(out: ptr<ByteBuffer>, value: i64):
    cc_bytes_append(out, cv_cptr(value), cv_len(value) + 1)

unsafe fn dwarf_line_file(out: ptr<ByteBuffer>, files: i64, file: i64):
    cv_set(files, file, cv_i(cv_len(files) + 1))
    dwarf_string(out, file)
    cc_bytes_word(out, 0, 3)  # directory index, modification time, file size

# DWARF 4 / DWARF32, with absolute source filenames and 64-bit target addresses.
unsafe fn dwarf_line_table(out: ptr<ByteBuffer>, rows: i64, entry: i64, text: i64):
    let files: i64 = cv_dict()
    let start: i64 = out.len
    cc_bytes_word(out, 0, 4)  # unit length
    cc_bytes_word(out, 4, 2)
    cc_bytes_word(out, 0, 4)  # header length
    let header: i64 = out.len
    # Instruction sizes, is_stmt, line base (-5), line range and opcode base.
    let params: [6]u8 = [1, 1, 1, 251, 14, 13]
    let operands: [12]u8 = [0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1]
    cc_bytes_append(out, (&params[0]) as ptr<char>, len(params))
    cc_bytes_append(out, (&operands[0]) as ptr<char>, len(operands))
    cc_bytes_word(out, 0, 1)  # no include directories
    dwarf_line_file(out, files, entry)
    for i in 0..cv_len(rows):
        let row: ptr<AsmSourceFunction> = cv_at(rows, i) as ptr<AsmSourceFunction>
        if not cv_has(files, row.file): dwarf_line_file(out, files, row.file)
    cc_bytes_word(out, 0, 1)  # end of file table
    cc_bytes_set(out, header - 4, (out.len - header) as u64, 4)

    # One sequence per function: the prologue keeps the declaration line and each
    # statement marker adds a row, so debuggers step through statements with `next`.
    for i in 0..cv_len(rows):
        let row: ptr<AsmSourceFunction> = cv_at(rows, i) as ptr<AsmSourceFunction>
        let file_index: i64 = cv_index(cv_get(files, row.file, 0))
        cc_bytes_word(out, 0x020900, 3)  # DW_LNE_set_address (8-byte operand)
        cc_bytes_word(out, (text + row.start) as u64, 8)
        if file_index != 1:
            cc_bytes_word(out, 4, 1)  # DW_LNS_set_file
            dwarf_leb(out, file_index, false)
        if row.line != 1:
            cc_bytes_word(out, 3, 1)  # DW_LNS_advance_line
            dwarf_leb(out, row.line - 1, true)
        cc_bytes_word(out, 1, 1)  # DW_LNS_copy
        let pc: i64 = row.start
        let line: i64 = row.line
        for j in 0..cv_len(row.marks):
            let mark: i64 = cv_at(row.marks, j)
            let mark_line: i64 = cv_index(cv_at(mark, 0))
            let mark_pc: i64 = cv_index(cv_at(mark, 1))
            if mark_pc < pc or mark_pc >= row.end: continue
            if mark_pc == pc and mark_line == line: continue
            if mark_pc > pc:
                cc_bytes_word(out, 2, 1)  # DW_LNS_advance_pc
                dwarf_leb(out, mark_pc - pc, false)
                pc = mark_pc
            if mark_line != line:
                cc_bytes_word(out, 3, 1)  # DW_LNS_advance_line
                dwarf_leb(out, mark_line - line, true)
                line = mark_line
            cc_bytes_word(out, 1, 1)  # DW_LNS_copy
        cc_bytes_word(out, 2, 1)  # DW_LNS_advance_pc to exclusive end of function
        dwarf_leb(out, row.end - pc, false)
        cc_bytes_word(out, 0x010100, 3)  # DW_LNE_end_sequence
    cc_bytes_set(out, start, (out.len - start - 4) as u64, 4)

# DWARF 4 abbreviations: единица компиляции с базовыми типами, подпрограммами,
# формальными параметрами, переменными и лексическими блоками.
unsafe fn dwarf_abbrev(out: ptr<ByteBuffer>):
    # 1: compile_unit, есть дети: name, stmt_list, low_pc, high_pc, language
    let a1: [15]u8 = [1, 0x11, 1, 0x03, 0x08, 0x10, 0x17, 0x11, 0x01, 0x12, 0x01, 0x13, 0x0b, 0, 0]
    # 2: base_type: name, encoding, byte_size
    let a2: [11]u8 = [2, 0x24, 0, 0x03, 0x08, 0x3e, 0x0b, 0x0b, 0x0b, 0, 0]
    # 3: subprogram, есть дети: name, low_pc, high_pc
    let a3: [11]u8 = [3, 0x2e, 1, 0x03, 0x08, 0x11, 0x01, 0x12, 0x01, 0, 0]
    # 4: variable: name, type, location
    let a4: [11]u8 = [4, 0x34, 0, 0x03, 0x08, 0x49, 0x13, 0x02, 0x18, 0, 0]
    # 5: formal_parameter: name, type, location
    let a5: [11]u8 = [5, 0x05, 0, 0x03, 0x08, 0x49, 0x13, 0x02, 0x18, 0, 0]
    # 6: lexical_block, есть дети: low_pc, high_pc
    let a6: [9]u8 = [6, 0x0b, 1, 0x11, 0x01, 0x12, 0x01, 0, 0]
    # 7: pointer_type с именем: name, type
    let a7: [9]u8 = [7, 0x0f, 0, 0x03, 0x08, 0x49, 0x13, 0, 0]
    # 8: pointer_type без типа (void*): byte_size
    let a8: [7]u8 = [8, 0x0f, 0, 0x0b, 0x0b, 0, 0]
    # 9: structure_type, есть дети: name, byte_size
    let a9: [9]u8 = [9, 0x13, 1, 0x03, 0x08, 0x0b, 0x0f, 0, 0]
    # 10: member: name, type, data_member_location
    let a10: [11]u8 = [10, 0x0d, 0, 0x03, 0x08, 0x49, 0x13, 0x38, 0x0f, 0, 0]
    # 11/12: unsupported local/parameter, with a name but no location.
    let a11: [7]u8 = [11, 0x34, 0, 0x03, 0x08, 0, 0]
    let a12: [7]u8 = [12, 0x05, 0, 0x03, 0x08, 0, 0]
    cc_bytes_append(out, (&a1[0]) as ptr<char>, len(a1))
    cc_bytes_append(out, (&a2[0]) as ptr<char>, len(a2))
    cc_bytes_append(out, (&a3[0]) as ptr<char>, len(a3))
    cc_bytes_append(out, (&a4[0]) as ptr<char>, len(a4))
    cc_bytes_append(out, (&a5[0]) as ptr<char>, len(a5))
    cc_bytes_append(out, (&a6[0]) as ptr<char>, len(a6))
    cc_bytes_append(out, (&a7[0]) as ptr<char>, len(a7))
    cc_bytes_append(out, (&a8[0]) as ptr<char>, len(a8))
    cc_bytes_append(out, (&a9[0]) as ptr<char>, len(a9))
    cc_bytes_append(out, (&a10[0]) as ptr<char>, len(a10))
    cc_bytes_append(out, (&a11[0]) as ptr<char>, len(a11))
    cc_bytes_append(out, (&a12[0]) as ptr<char>, len(a12))
    cc_bytes_word(out, 0, 1)

unsafe fn dwarf_collect_member(members: i64, name: i64, key: i64, off: i64):
    let m: i64 = cv_tuple()
    cv_push(m, name)
    cv_push(m, key)
    cv_push(m, off)
    cv_push(members, m)

unsafe fn dwarf_collect_type(types: i64, seen: i64, typ: i64) -> i64:
    if typ == 0: return 0
    # Key on the compiler type, not its display name: different modules can
    # export structs with the same name and different layouts.
    if cv_has(seen, typ): return typ
    if cv_classes(typ, "TInt") or cv_classes(typ, "TFloat") or cv_classes(typ, "TBool") or cv_classes(typ, "TEnum"):
        cv_set(seen, typ, CV_TRUE)
        cv_push(types, cv_pair(cv_text("base"), typ))
    elif cv_classes(typ, "TString") or cv_classes(typ, "TPtr") or cv_classes(typ, "TFnPtr"):
        cv_set(seen, typ, CV_TRUE)
        let elem: i64 = cv_getkey(typ, "elem")
        if cv_classes(typ, "TString"): elem = cc_k_char_type
        cv_push(types, cv_pair(cv_text("ptr"), cv_pair(typ, dwarf_collect_type(types, seen, elem))))
    elif cv_classes(typ, "TSlice") or cv_classes(typ, "TStruct"):
        # A generic struct behind a pointer may never have been laid out.
        if cv_classes(typ, "TStruct") and cv_getkey(typ, "size") == 0: return 0
        cv_set(seen, typ, CV_TRUE)  # recursive fields can refer to this DIE
        let members: i64 = cv_list()
        cv_push(types, cv_pair(cv_text("struct"), cv_pair(typ, members)))
        if cv_classes(typ, "TSlice"):
            let data: i64 = dwarf_collect_type(types, seen, cc_TPtr(cv_getkey(typ, "elem")))
            let length: i64 = dwarf_collect_type(types, seen, cc_int(CV_TRUE, cv_i(64)))
            dwarf_collect_member(members, cv_text("data"), data, cv_i(0))
            dwarf_collect_member(members, cv_text("len"), length, cv_i(8))
        let fields: i64 = cv_getkey(typ, "fields")
        for i in 0..cv_len(fields):
            let field: i64 = cv_at(fields, i)
            let fkey: i64 = dwarf_collect_type(types, seen, cv_at(field, 1))
            if fkey != 0:
                dwarf_collect_member(members, cv_at(field, 0), fkey, cv_at(field, 2))
    else:
        return 0
    return typ

unsafe fn dwarf_collect_scopes(types: i64, seen: i64, scopes: i64):
    let pending: i64 = cv_aslist(scopes)
    while cv_len(pending) != 0:
        let item: i64 = cv_pop(pending)
        let vars: i64 = cv_getkey(item, "vars")
        for i in 0..cv_len(vars):
            dwarf_collect_type(types, seen, cv_getkey(cv_at(vars, i), "typ"))
        cv_extend(pending, cv_getkey(item, "children"))

# Один DIE типа. ref4 имеет фиксированный размер, поэтому в первом проходе
# refs может быть неполным (отсутствующая ссылка кодируется нулём).
unsafe fn dwarf_type_ref(refs: i64, key: i64) -> i64:
    let tref: i64 = cv_get(refs, key, 0)
    if tref == 0: return 0
    return cv_index(tref)

unsafe fn dwarf_type_die(out: ptr<ByteBuffer>, refs: i64, rec: i64):
    let kind: i64 = cv_at(rec, 0)
    let data: i64 = cv_at(rec, 1)
    if cv_name(kind, "base"):
        let typ: i64 = data
        let enc: i64 = 5  # DW_ATE_signed
        let size: i64 = 8
        if cv_classes(typ, "TBool"):
            enc = 2  # DW_ATE_boolean
            size = 1
        elif cv_classes(typ, "TFloat"):
            enc = 4  # DW_ATE_float
            size = cv_index(cv_getkey(typ, "bits")) / 8
        elif cv_classes(typ, "TEnum"):
            enc = 5
            size = cv_index(cv_getkey(typ, "bits")) / 8
        else:
            size = cv_index(cv_getkey(typ, "bits")) / 8
            if cv_getkey(typ, "alias") != 0:
                enc = 8  # DW_ATE_unsigned_char: char печатается символом
            elif not cv_truth(cv_getkey(typ, "signed")):
                enc = 7  # DW_ATE_unsigned
        dwarf_leb(out, 2, false)
        dwarf_string(out, cc_display(typ))
        cc_bytes_word(out, enc as u64, 1)
        cc_bytes_word(out, size as u64, 1)
    elif cv_name(kind, "ptr"):
        let target: i64 = cv_at(data, 1)
        if target == 0:
            dwarf_leb(out, 8, false)
            cc_bytes_word(out, 8, 1)
        else:
            dwarf_leb(out, 7, false)
            dwarf_string(out, cc_display(cv_at(data, 0)))
            cc_bytes_word(out, dwarf_type_ref(refs, target) as u64, 4)
    else:
        dwarf_leb(out, 9, false)
        let typ: i64 = cv_at(data, 0)
        dwarf_string(out, cc_display(typ))
        dwarf_leb(out, cv_index(cc_type_size(typ)), false)
        let members: i64 = cv_at(data, 1)
        for i in 0..cv_len(members):
            let member: i64 = cv_at(members, i)
            dwarf_leb(out, 10, false)
            dwarf_string(out, cv_at(member, 0))
            cc_bytes_word(out, dwarf_type_ref(refs, cv_at(member, 1)) as u64, 4)
            dwarf_leb(out, cv_index(cv_at(member, 2)), false)
        cc_bytes_word(out, 0, 1)

# Базовые, указательные и структурные типы — дети единицы компиляции;
# refs[ключ] = смещение DIE от начала единицы.
unsafe fn dwarf_type_dies(out: ptr<ByteBuffer>, types: i64, refs: i64, start: i64):
    let scratch: ByteBuffer
    let base: i64 = out.len - start
    for i in 0..cv_len(types):
        let rec: i64 = cv_at(types, i)
        let key: i64 = cv_at(rec, 1)
        if not cv_name(cv_at(rec, 0), "base"): key = cv_at(key, 0)
        cv_set(refs, key, cv_i(base + scratch.len))
        dwarf_type_die(&scratch, refs, rec)
    for i in 0..cv_len(types):
        dwarf_type_die(out, refs, cv_at(types, i))
    bytes_free(&scratch)

# DIE переменной или параметра: имя, тип и расположение [rbp - 16 - off]
# (та же адресация, что в cce_soff).
unsafe fn dwarf_var_die(out: ptr<ByteBuffer>, refs: i64, slot: i64, code: i64):
    let tref: i64 = dwarf_type_ref(refs, cv_getkey(slot, "typ"))
    if tref == 0:
        # Retain the binding even if we cannot describe the value. Otherwise
        # the debugger incorrectly falls back to a shadowed outer variable.
        dwarf_leb(out, code + 7, false)
        dwarf_string(out, cv_getkey(slot, "name"))
        return
    dwarf_leb(out, code, false)
    dwarf_string(out, cv_getkey(slot, "name"))
    cc_bytes_word(out, tref as u64, 4)
    let length: i64 = out.len
    cc_bytes_word(out, 0, 1)  # a register opcode and one SLEB always fit in 127 bytes
    cc_bytes_word(out, 0x76, 1)  # DW_OP_breg6 (rbp)
    dwarf_leb(out, -16 - cv_index(cv_getkey(slot, "off")), true)
    cc_bytes_set(out, length, (out.len - length - 1) as u64, 1)

# Walk the tree iteratively: consecutive declarations can nest arbitrarily.
unsafe fn dwarf_scope_dies(out: ptr<ByteBuffer>, refs: i64, scopes: i64, text: i64):
    let pending: i64 = cv_reverse(scopes)
    while cv_len(pending) != 0:
        let item: i64 = cv_pop(pending)
        if item == 0:
            cc_bytes_word(out, 0, 1)
            continue
        let lo: i64 = cv_index(cv_getkey(item, "start"))
        let hi: i64 = cv_index(cv_getkey(item, "end"))
        if hi <= lo: continue
        dwarf_leb(out, 6, false)
        cc_bytes_word(out, (text + lo) as u64, 8)
        cc_bytes_word(out, (text + hi) as u64, 8)
        let vars: i64 = cv_getkey(item, "vars")
        for i in 0..cv_len(vars): dwarf_var_die(out, refs, cv_at(vars, i), 4)
        cv_push(pending, 0)
        let children: i64 = cv_getkey(item, "children")
        for i in 0..cv_len(children): cv_push(pending, cv_at(children, -1 - i))

unsafe fn dwarf_info(out: ptr<ByteBuffer>, rows: i64, entry: i64, text: i64):
    let first: ptr<AsmSourceFunction> = cv_at(rows, 0) as ptr<AsmSourceFunction>
    let last: ptr<AsmSourceFunction> = cv_at(rows, cv_len(rows) - 1) as ptr<AsmSourceFunction>
    let start: i64 = out.len
    cc_bytes_word(out, 0, 4)  # unit length
    cc_bytes_word(out, 4, 2)  # version
    cc_bytes_word(out, 0, 4)  # .debug_abbrev offset
    cc_bytes_word(out, 8, 1)  # target address size
    cc_bytes_word(out, 1, 1)  # compile_unit
    dwarf_string(out, entry)
    cc_bytes_word(out, 0, 4)  # .debug_line offset
    cc_bytes_word(out, (text + first.start) as u64, 8)
    cc_bytes_word(out, (text + last.end) as u64, 8)
    cc_bytes_word(out, 2, 1)  # DW_LANG_C
    # Сначала все типы, затем подпрограммы: ссылки ref4 разрешаются вперёд.
    let types: i64 = cv_list()
    let seen: i64 = cv_dict()
    for i in 0..cv_len(rows):
        let row: ptr<AsmSourceFunction> = cv_at(rows, i) as ptr<AsmSourceFunction>
        if row.params != 0:
            for j in 0..cv_len(row.params):
                dwarf_collect_type(types, seen, cv_getkey(cv_at(row.params, j), "typ"))
        dwarf_collect_scopes(types, seen, row.scopes)
    let refs: i64 = cv_dict()
    dwarf_type_dies(out, types, refs, start)
    for i in 0..cv_len(rows):
        let row: ptr<AsmSourceFunction> = cv_at(rows, i) as ptr<AsmSourceFunction>
        dwarf_leb(out, 3, false)  # subprogram
        dwarf_string(out, row.title)
        cc_bytes_word(out, (text + row.start) as u64, 8)
        cc_bytes_word(out, (text + row.end) as u64, 8)
        if row.params != 0:
            for j in 0..cv_len(row.params):
                dwarf_var_die(out, refs, cv_at(row.params, j), 5)
        dwarf_scope_dies(out, refs, row.scopes, text)
        cc_bytes_word(out, 0, 1)  # конец детей подпрограммы
    cc_bytes_word(out, 0, 1)  # конец детей единицы компиляции
    cc_bytes_set(out, start, (out.len - start - 4) as u64, 4)
