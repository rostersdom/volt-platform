use elf_imports
use dwarf_line

struct ElfLayout:
    offsets: [4]i64
    read_end: i64
    writable: i64
    end: i64
    memory_end: i64
    dynstr: i64
    dynsym: i64
    hash: i64
    versym: i64
    verneed: i64
    rela: i64
    got: i64
    dynamic: i64
    linker: i64

struct ElfSections:
    names: ByteBuffer
    headers: ByteBuffer

struct ElfSection:
    flags: i64
    start: i64
    size: i64
    align: i64
    linked: i64
    info: i64
    entry: i64

unsafe fn elf_align(at: i64, alignment: i64) -> i64:
    return (at + alignment - 1) & (0 - alignment)

unsafe fn elf_interp() -> i64:
    let loaders: i64 = x_words("/lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2 /lib/ld-musl-x86_64.so.1")
    for i in 0..cv_len(loaders):
        let path: i64 = cv_at(loaders, i)
        if cc_regular(path): return path
    cc_error(cv_text("не найден динамический загрузчик Linux x86-64"), 0, 0)
    return 0

unsafe fn elf_tag(buf: ptr<ByteBuffer>, name: i64, value: i64):
    cc_bytes_word(buf, name as u64, 8)
    cc_bytes_word(buf, value as u64, 8)

unsafe fn elf_rel32(buf: ptr<ByteBuffer>, at: i64, displacement: i64):
    if not x_fits(displacement, 4): cc_error(cv_text("ELF: относительное смещение вне диапазона x86-64"), 0, 0)
    cc_bytes_set(buf, at, x_bits(cv_i(displacement)), 4)

unsafe fn elf_lay_out(code: ptr<AsmObject>, imp: ptr<ElfImports>, file: ptr<ElfLayout>, tags: ptr<ByteBuffer>, rela: ptr<ByteBuffer>):
    let dynamic: bool = cv_len(imp.needed) > 0
    file.offsets[ASM_TEXT] = 4096
    file.offsets[ASM_RO] = elf_align(4096 + code.sections[ASM_TEXT].len, 4096)
    file.read_end = file.offsets[ASM_RO] + code.sections[ASM_RO].len
    if dynamic:
        file.linker = elf_interp()
        file.dynstr = file.read_end
        file.dynsym = elf_align(file.dynstr + imp.strings.len, 8)
        file.hash = file.dynsym + imp.symbols.len
        file.versym = file.hash + imp.hash.len
        file.verneed = elf_align(file.versym, 4)
        if imp.verneed_count != 0: file.verneed = elf_align(file.versym + imp.versym.len, 4)
        file.rela = elf_align(file.verneed + imp.verneed.len, 8)
        file.read_end = file.rela + 24 * cv_len(imp.stubs)
    file.writable = elf_align(file.read_end, 4096)
    if dynamic:
        file.got = file.writable
        file.dynamic = file.got + 8 * cv_len(imp.stubs)
        for i in 0..cv_len(imp.needed): elf_tag(tags, 1, cv_index(cv_at(imp.needed, i)))
        elf_tag(tags, 4, ELF_BASE + file.hash)
        elf_tag(tags, 5, ELF_BASE + file.dynstr)
        elf_tag(tags, 10, imp.strings.len)
        elf_tag(tags, 6, ELF_BASE + file.dynsym)
        elf_tag(tags, 11, 24)
        if imp.verneed_count != 0:
            elf_tag(tags, 0x6ffffff0, ELF_BASE + file.versym)
            elf_tag(tags, 0x6ffffffe, ELF_BASE + file.verneed)
            elf_tag(tags, 0x6fffffff, imp.verneed_count)
        elf_tag(tags, 7, ELF_BASE + file.rela)
        elf_tag(tags, 9, 24)
        elf_tag(tags, 8, 24 * cv_len(imp.stubs))
        elf_tag(tags, 21, 0)
        elf_tag(tags, 30, 8)
        elf_tag(tags, 0, 0)
        for i in 0..cv_len(imp.stubs):
            let slot: i64 = file.got + 8 * i
            let stub: i64 = cv_index(cv_at(imp.stubs, i))
            elf_rel32(&code.sections[ASM_TEXT], stub + 2, slot - (file.offsets[ASM_TEXT] + stub + 6))
            cc_bytes_word(rela, (ELF_BASE + slot) as u64, 8)
            cc_bytes_word(rela, ((i + 1) as u64) << 32 | 6, 8)
            cc_bytes_word(rela, 0, 8)
        file.offsets[ASM_DATA] = elf_align(file.dynamic + tags.len, 4096)
    else:
        file.offsets[ASM_DATA] = file.writable
    file.end = file.offsets[ASM_DATA] + code.sections[ASM_DATA].len
    file.offsets[ASM_BSS] = elf_align(file.end, code.alignments[ASM_BSS])
    file.memory_end = file.offsets[ASM_BSS] + code.bss

unsafe fn elf_address(location: i64, file: ptr<ElfLayout>) -> i64:
    return ELF_BASE + file.offsets[cv_index(cv_at(location, 0))] + cv_index(cv_at(location, 1))

unsafe fn elf_resolve(code: ptr<AsmObject>, file: ptr<ElfLayout>):
    for i in 0..cv_len(code.fixups):
        let f: ptr<AsmFixup> = cv_at(code.fixups, i) as ptr<AsmFixup>
        let target: i64 = elf_address(cv_get(code.names, f.symbol, 0), file) + f.addend
        let buf: ptr<ByteBuffer> = &code.sections[f.section]
        if f.relative:
            let next: i64 = ELF_BASE + file.offsets[f.section] + f.next
            elf_rel32(buf, f.offset, target - next)
        else:
            if f.width != 8 and (target as u64) >= (1 as u64) << (f.width * 8):
                cc_error(cv_text("ELF: абсолютный адрес не помещается в директиву данных"), 0, 0)
            cc_bytes_set(buf, f.offset, target as u64, f.width)

unsafe fn elf_data_at(out: ptr<ByteBuffer>, at: i64, buf: ptr<ByteBuffer>):
    if buf.len == 0: return
    if at < 0 or at > out.len - buf.len: panic("volt: ELF segment outside file\n")
    cv_copy((out.data + at) as ptr<char>, buf.data as ptr<char>, buf.len)

unsafe fn elf_phdr(out: ptr<ByteBuffer>, kind: i64, flags: i64, at: i64, sizes: ptr<i64>, align: i64):
    let location: u64 = (ELF_BASE + at) as u64
    if kind == 0x6474e551: location = 0
    cc_bytes_word(out, kind as u64, 4)
    cc_bytes_word(out, flags as u64, 4)
    cc_bytes_word(out, at as u64, 8)
    cc_bytes_word(out, location, 8)
    cc_bytes_word(out, location, 8)
    cc_bytes_word(out, sizes[0] as u64, 8)
    cc_bytes_word(out, sizes[1] as u64, 8)
    cc_bytes_word(out, align as u64, 8)

unsafe fn elf_load_header(out: ptr<ByteBuffer>, flags: i64, at: i64, size: i64, mem: i64):
    let sizes: [2]i64 = [size, mem]
    elf_phdr(out, 1, flags, at, &sizes[0], 4096)

unsafe fn elf_plain_header(out: ptr<ByteBuffer>, kind: i64, flags: i64, at: i64, size: i64, align: i64):
    let sizes: [2]i64 = [size, size]
    elf_phdr(out, kind, flags, at, &sizes[0], align)

unsafe fn elf_shdr(table: ptr<ElfSections>, name: string, typ: i64, desc: ElfSection) -> i64:
    let index: i64 = table.headers.len / 64
    let addr: i64 = 0
    if desc.flags & 2 != 0: addr = ELF_BASE + desc.start
    cc_bytes_word(&table.headers, elf_add_str(&table.names, cv_text(name)), 4)
    cc_bytes_word(&table.headers, typ as u64, 4)
    cc_bytes_word(&table.headers, desc.flags as u64, 8)
    cc_bytes_word(&table.headers, addr as u64, 8)
    cc_bytes_word(&table.headers, desc.start as u64, 8)
    cc_bytes_word(&table.headers, desc.size as u64, 8)
    cc_bytes_word(&table.headers, desc.linked as u64, 4)
    cc_bytes_word(&table.headers, desc.info as u64, 4)
    cc_bytes_word(&table.headers, desc.align as u64, 8)
    cc_bytes_word(&table.headers, desc.entry as u64, 8)
    return index

unsafe fn elf_add_symbols(out: ptr<ByteBuffer>, table: ptr<ElfSections>, code: ptr<AsmObject>, file: ptr<ElfLayout>):
    let strings: ByteBuffer
    let symbols: ByteBuffer
    cc_bytes_fill(&strings, 1, 0)
    cc_bytes_fill(&symbols, 24, 0)
    let labels: i64 = cv_list()
    for i in 0..cv_len(code.names):
        let name: i64 = cv_at(code.names, i)
        if not cv_starts(name, cv_text("VOLT_L")) and not cv_starts(name, cv_text(".L")): cv_push(labels, name)
    labels = cv_sorted(labels)
    for i in 0..cv_len(labels):
        let name: i64 = cv_at(labels, i)
        let loc: i64 = cv_get(code.names, name, 0)
        let sec: i64 = cv_index(cv_at(loc, 0))
        let typ: u64 = 1
        if sec == ASM_TEXT: typ = 2
        cc_bytes_word(&symbols, elf_add_str(&strings, name), 4)
        cc_bytes_word(&symbols, typ, 1)
        cc_bytes_word(&symbols, 0, 1)
        cc_bytes_word(&symbols, (sec + 1) as u64, 2)
        cc_bytes_word(&symbols, elf_address(loc, file) as u64, 8)
        cc_bytes_word(&symbols, 0, 8)
    let index: i64 = elf_shdr(table, ".strtab", 3, ElfSection(0, out.len, strings.len, 1, 0, 0, 0))
    cc_bytes_append(out, strings.data as ptr<char>, strings.len)
    cc_bytes_fill(out, elf_align(out.len, 8) - out.len, 0)
    elf_shdr(table, ".symtab", 2, ElfSection(0, out.len, symbols.len, 8, index, symbols.len / 24, 24))
    cc_bytes_append(out, symbols.data as ptr<char>, symbols.len)
    bytes_free(&strings)
    bytes_free(&symbols)

unsafe fn elf_add_debug(out: ptr<ByteBuffer>, sections: ptr<ElfSections>, rows: i64, entry: i64, text: i64):
    let start: i64 = out.len
    dwarf_line_table(out, rows, entry, text)
    elf_shdr(sections, ".debug_line", 1, ElfSection(0, start, out.len - start, 1, 0, 0, 0))
    start = out.len
    dwarf_abbrev(out)
    elf_shdr(sections, ".debug_abbrev", 1, ElfSection(0, start, out.len - start, 1, 0, 0, 0))
    start = out.len
    dwarf_info(out, rows, entry, text)
    elf_shdr(sections, ".debug_info", 1, ElfSection(0, start, out.len - start, 1, 0, 0, 0))

unsafe fn elf_executable(code: ptr<AsmObject>, libraries: i64, entry: i64, out: ptr<ByteBuffer>):
    let imp: ElfImports
    let file: ElfLayout
    let tags: ByteBuffer
    let rela: ByteBuffer
    elf_imports(code, libraries, &imp)
    elf_lay_out(code, &imp, &file, &tags, &rela)
    elf_resolve(code, &file)
    let sections: ElfSections
    cc_bytes_fill(&sections.names, 1, 0)
    cc_bytes_fill(&sections.headers, 64, 0)
    cc_bytes_fill(out, file.end, 0)
    elf_shdr(&sections, ".text", 1, ElfSection(6, file.offsets[ASM_TEXT], code.sections[ASM_TEXT].len, code.alignments[ASM_TEXT], 0, 0, 0))
    elf_shdr(&sections, ".rodata", 1, ElfSection(2, file.offsets[ASM_RO], code.sections[ASM_RO].len, code.alignments[ASM_RO], 0, 0, 0))
    elf_shdr(&sections, ".data", 1, ElfSection(3, file.offsets[ASM_DATA], code.sections[ASM_DATA].len, code.alignments[ASM_DATA], 0, 0, 0))
    elf_shdr(&sections, ".bss", 8, ElfSection(3, file.offsets[ASM_BSS], code.bss, code.alignments[ASM_BSS], 0, 0, 0))
    for i in 0..3: elf_data_at(out, file.offsets[i], &code.sections[i])
    let phnum: i64 = 5
    let linker: i64 = 0
    if file.linker != 0:
        phnum = 8
        linker = cv_len(file.linker) + 1
        cv_copy((out.data + 512) as ptr<char>, cv_cptr(file.linker), linker)
        elf_shdr(&sections, ".interp", 1, ElfSection(2, 512, linker, 1, 0, 0, 0))
        let dynstr: i64 = elf_shdr(&sections, ".dynstr", 3, ElfSection(2, file.dynstr, imp.strings.len, 1, 0, 0, 0))
        let dynsym: i64 = elf_shdr(&sections, ".dynsym", 11, ElfSection(2, file.dynsym, imp.symbols.len, 8, dynstr, 1, 24))
        elf_shdr(&sections, ".hash", 5, ElfSection(2, file.hash, imp.hash.len, 4, dynsym, 0, 4))
        if imp.verneed_count != 0:
            elf_shdr(&sections, ".gnu.version", 0x6fffffff, ElfSection(2, file.versym, imp.versym.len, 2, dynsym, 0, 2))
            elf_shdr(&sections, ".gnu.version_r", 0x6ffffffe, ElfSection(2, file.verneed, imp.verneed.len, 4, dynstr, imp.verneed_count, 0))
            elf_data_at(out, file.versym, &imp.versym)
            elf_data_at(out, file.verneed, &imp.verneed)
        elf_shdr(&sections, ".rela.dyn", 4, ElfSection(2, file.rela, rela.len, 8, dynsym, 0, 24))
        elf_shdr(&sections, ".got", 1, ElfSection(3, file.got, cv_len(imp.stubs) * 8, 8, 0, 0, 8))
        elf_shdr(&sections, ".dynamic", 6, ElfSection(3, file.dynamic, tags.len, 8, dynstr, 0, 16))
        elf_data_at(out, file.dynstr, &imp.strings)
        elf_data_at(out, file.dynsym, &imp.symbols)
        elf_data_at(out, file.hash, &imp.hash)
        elf_data_at(out, file.rela, &rela)
        elf_data_at(out, file.dynamic, &tags)
    elf_add_symbols(out, &sections, code, &file)
    if cv_len(code.debug_functions) != 0:
        elf_add_debug(out, &sections, code.debug_functions, entry, ELF_BASE + file.offsets[ASM_TEXT])
    let shstr: i64 = elf_shdr(&sections, ".shstrtab", 3, ElfSection(0, out.len, sections.names.len + 10, 1, 0, 0, 0))
    cc_bytes_append(out, sections.names.data as ptr<char>, sections.names.len)
    cc_bytes_fill(out, elf_align(out.len, 8) - out.len, 0)
    let shoff: i64 = out.len
    cc_bytes_append(out, sections.headers.data as ptr<char>, sections.headers.len)

    let headers: ByteBuffer
    cc_bytes_word(&headers, 0x00010102464c457f, 8)
    cc_bytes_word(&headers, 0, 8)
    cc_bytes_word(&headers, 2, 2)
    cc_bytes_word(&headers, 62, 2)
    cc_bytes_word(&headers, 1, 4)
    cc_bytes_word(&headers, elf_address(cv_getkey(code.names, "_start"), &file) as u64, 8)
    cc_bytes_word(&headers, 64, 8)
    cc_bytes_word(&headers, shoff as u64, 8)
    cc_bytes_word(&headers, 0, 4)
    cc_bytes_word(&headers, 64, 2)
    cc_bytes_word(&headers, 56, 2)
    cc_bytes_word(&headers, phnum as u64, 2)
    cc_bytes_word(&headers, 64, 2)
    cc_bytes_word(&headers, (sections.headers.len / 64) as u64, 2)
    cc_bytes_word(&headers, shstr as u64, 2)
    elf_plain_header(&headers, 6, 4, 64, phnum * 56, 8)
    if linker != 0: elf_plain_header(&headers, 3, 4, 512, linker, 1)
    let text_end: i64 = file.offsets[ASM_TEXT] + code.sections[ASM_TEXT].len
    elf_load_header(&headers, 5, 0, text_end, text_end)
    let ro_size: i64 = file.read_end - file.offsets[ASM_RO]
    elf_load_header(&headers, 4, file.offsets[ASM_RO], ro_size, ro_size)
    elf_load_header(&headers, 6, file.writable, file.end - file.writable, file.memory_end - file.writable)
    if linker != 0: elf_plain_header(&headers, 2, 6, file.dynamic, tags.len, 8)
    elf_plain_header(&headers, 0x6474e551, 6, 0, 0, 16)
    if linker != 0: elf_plain_header(&headers, 0x6474e552, 4, file.writable, file.offsets[ASM_DATA] - file.writable, 1)
    elf_data_at(out, 0, &headers)
