use asm_object

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

unsafe fn dwarf_abbrev(out: ptr<ByteBuffer>):
    # One DW_TAG_compile_unit with name, stmt_list, low_pc and high_pc.
    let abbrev: [14]u8 = [1, 0x11, 0, 3, 8, 0x10, 0x17, 0x11, 1, 0x12, 1, 0, 0, 0]
    cc_bytes_append(out, (&abbrev[0]) as ptr<char>, len(abbrev))

unsafe fn dwarf_info(out: ptr<ByteBuffer>, rows: i64, entry: i64, text: i64):
    let first: ptr<AsmSourceFunction> = cv_at(rows, 0) as ptr<AsmSourceFunction>
    let last: ptr<AsmSourceFunction> = cv_at(rows, cv_len(rows) - 1) as ptr<AsmSourceFunction>
    let start: i64 = out.len
    cc_bytes_word(out, 0, 4)  # unit length
    cc_bytes_word(out, 4, 2)  # version
    cc_bytes_word(out, 0, 4)  # .debug_abbrev offset
    cc_bytes_word(out, 8, 1)  # target address size
    cc_bytes_word(out, 1, 1)  # abbreviation code
    dwarf_string(out, entry)
    cc_bytes_word(out, 0, 4)  # .debug_line offset
    cc_bytes_word(out, (text + first.start) as u64, 8)
    cc_bytes_word(out, (text + last.end) as u64, 8)
    cc_bytes_set(out, start, (out.len - start - 4) as u64, 4)
