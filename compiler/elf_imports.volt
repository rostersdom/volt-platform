use x86_encode

const ELF_BASE: i64 = 0x400000

struct ElfLibrary:
    name: i64
    exports: i64

struct ElfTable:
    kind: i64
    start: i64
    size: i64
    linked: i64

struct ElfImports:
    strings: ByteBuffer
    symbols: ByteBuffer
    hash: ByteBuffer
    versym: ByteBuffer
    verneed: ByteBuffer
    needed: i64
    stubs: i64
    verneed_count: i64

unsafe fn elf_u(buf: ptr<ByteBuffer>, at: i64, width: i64) -> u64:
    if at < 0 or width < 1 or at > buf.len - width: cc_error(cv_text("ELF: повреждённая таблица"), 0, 0)
    let result: u64 = 0
    for i in 0..width: result |= (buf.data[at + i] as u64) << (8 * i)
    return result

unsafe fn elf_n(buf: ptr<ByteBuffer>, at: i64, width: i64) -> i64:
    let n: u64 = elf_u(buf, at, width)
    if n > 0x7fffffffffffffff: cc_error(cv_text("ELF: смещение вне диапазона"), 0, 0)
    return n as i64

unsafe fn elf_read_section(buf: ptr<ByteBuffer>, base: i64, count: i64, index: i64) -> ElfTable:
    if index < 0 or index >= count: cc_error(cv_text("ELF: неверный индекс секции"), 0, 0)
    let at: i64 = base + index * 64
    let kind: i64 = elf_n(buf, at + 4, 4)
    let start: i64 = elf_n(buf, at + 24, 8)
    let size: i64 = elf_n(buf, at + 32, 8)
    let linked: i64 = elf_n(buf, at + 40, 4)
    if kind != 8 and (start > buf.len or size > buf.len - start): cc_error(cv_text("ELF: секция за пределами файла"), 0, 0)
    return ElfTable(kind, start, size, linked)

unsafe fn elf_table_n(buf: ptr<ByteBuffer>, table: ElfTable, offset: i64, width: i64) -> i64:
    if offset < 0 or offset > table.size - width: cc_error(cv_text("ELF: запись за пределами секции"), 0, 0)
    return elf_n(buf, table.start + offset, width)

unsafe fn elf_read_str(buf: ptr<ByteBuffer>, table: ElfTable, at: i64) -> i64:
    if table.kind != 3 or at < 0 or at >= table.size: cc_error(cv_text("ELF: неверное смещение строки"), 0, 0)
    let p: ptr<u8> = buf.data + table.start
    let end: i64 = at
    while end < table.size and p[end] != 0: end += 1
    if end == table.size: cc_error(cv_text("ELF: строка без завершающего нуля"), 0, 0)
    return cv_text(cv_cstring((p + at) as ptr<char>, end - at))

unsafe fn elf_library(path: i64, buf: ptr<ByteBuffer>) -> i64:
    let out: ptr<ElfLibrary> = cv_alloc(sizeof(ElfLibrary)) as ptr<ElfLibrary>
    out.name = cc_basename(path)
    out.exports = cv_dict()
    let sections: i64 = elf_n(buf, 40, 8)
    let count: i64 = elf_n(buf, 60, 2)
    if sections > buf.len or count > (buf.len - sections) / 64 or elf_n(buf, 58, 2) != 64 or count == 0:
        cc_error(cv_text("ELF: повреждённые заголовки секций"), path, cv_i(1))
    let versions: i64 = cv_dict()
    let versym: ElfTable
    let symbols: ElfTable
    let strings: ElfTable
    for i in 1..count:
        let table: ElfTable = elf_read_section(buf, sections, count, i)
        if table.kind == 6:
            let string_table: ElfTable = elf_read_section(buf, sections, count, table.linked)
            for j in 0..table.size / 16:
                let tag: i64 = elf_table_n(buf, table, j * 16, 8)
                if tag == 0: break
                if tag == 14: out.name = elf_read_str(buf, string_table, elf_table_n(buf, table, j * 16 + 8, 8))
        elif table.kind == 11:
            symbols = table
            strings = elf_read_section(buf, sections, count, table.linked)
        elif table.kind == 0x6fffffff:
            versym = table
        elif table.kind == 0x6ffffffd:
            let string_table: ElfTable = elf_read_section(buf, sections, count, table.linked)
            let at: i64 = 0
            while at < table.size:
                let revision: i64 = elf_table_n(buf, table, at, 2)
                let id: i64 = elf_table_n(buf, table, at + 4, 2)
                let aux_count: i64 = elf_table_n(buf, table, at + 6, 2)
                let hash: i64 = elf_table_n(buf, table, at + 8, 4)
                let aux: i64 = elf_table_n(buf, table, at + 12, 4)
                let next: i64 = elf_table_n(buf, table, at + 16, 4)
                if revision != 1 or aux_count == 0 or aux < 20: cc_error(cv_text("ELF: неверное описание версии символа"), path, cv_i(1))
                if id > 1:
                    let name: i64 = elf_read_str(buf, string_table, elf_table_n(buf, table, at + aux, 4))
                    cv_set(versions, cv_i(id), cv_pair(name, cv_i(hash)))
                if next == 0: break
                if next < 20 or next >= table.size - at: cc_error(cv_text("ELF: неверное смещение версии символа"), path, cv_i(1))
                at += next
    let plain: i64 = cv_pair(cv_text(""), cv_i(0))
    for i in 1..symbols.size / 24:
        let pos: i64 = i * 24
        let id: i64 = elf_table_n(buf, symbols, pos, 4)
        let info: i64 = elf_table_n(buf, symbols, pos + 4, 1)
        let visible: i64 = elf_table_n(buf, symbols, pos + 5, 1) & 3
        let section: i64 = elf_table_n(buf, symbols, pos + 6, 2)
        let binding: i64 = info >> 4
        let typ: i64 = info & 15
        if id == 0 or section == 0 or (binding != 1 and binding != 2): continue
        if visible != 0 and visible != 3: continue
        if typ != 0 and typ != 2 and typ != 10: continue
        let ver: i64 = 1
        if versym.size != 0: ver = elf_table_n(buf, versym, i * 2, 2)
        if ver == 0 or ver & 0x8000 != 0: continue
        let name: i64 = elf_read_str(buf, strings, id)
        let value: i64 = plain
        if ver != 1:
            value = cv_get(versions, cv_i(ver), 0)
            if value == 0: cc_error(cv_cat(cv_text("ELF: не найдена версия символа "), name), path, cv_i(1))
        if not cv_has(out.exports, name): cv_set(out.exports, name, value)
    return out as i64

unsafe fn elf_find_lib(dirs: i64, name: i64, source: i64, line: i64) -> i64:
    let exact: bool = cv_starts(name, cv_text(":"))
    let file: i64 = cv_cat(cv_cat(cv_text("lib"), name), cv_text(".so"))
    if exact: file = cv_subtext(name, 1, cv_len(name) - 1)
    for i in 0..cv_len(dirs):
        let path: i64 = cc_path_join(cv_at(dirs, i), file)
        if not cc_regular(path): continue
        let data: ByteBuffer
        cc_read_file(path, &data, 268435456)
        # glibc distributes lib{c,m}.so as linker scripts.
        if data.len > 4 and elf_n(&data, 0, 4) != 0x464c457f and not exact and (cv_name(name, "c") or cv_name(name, "m")):
            bytes_free(&data)
            path = cv_cat(path, cv_text(".6"))
            if not cc_regular(path): continue
            cc_read_file(path, &data, 268435456)
        if data.len >= 64 and elf_n(&data, 0, 4) == 0x464c457f and data.data[4] == 2 and data.data[5] == 1 and elf_n(&data, 18, 2) == 62 and elf_n(&data, 16, 2) == 3:
            let library: i64 = elf_library(path, &data)
            bytes_free(&data)
            return library
        bytes_free(&data)
    cc_error(cv_cat(cv_text("link: разделяемая библиотека x86-64 не найдена: -l"), name), source, line)
    return 0

unsafe fn elf_libname(name: i64) -> bool:
    let n: i64 = cv_len(name)
    let start: i64 = 0
    if n == 0: return false
    if cv_byte(name, 0) == ':': start = 1
    if start == n: return false
    if cv_name(cv_subtext(name, start, n - start), ".") or cv_name(cv_subtext(name, start, n - start), ".."): return false
    for i in start..n:
        let c: char = cv_byte(name, i)
        if not cc_lex_letter(c) and not cc_lex_digit(c) and c != '.' and c != '-' and c != '+': return false
    return true

unsafe fn elf_link_words(line: i64) -> i64:
    let out: i64 = cv_list()
    let n: i64 = cv_len(line)
    let at: i64 = 0
    let text: ptr<char> = cv_cptr(line)
    let part: ptr<char> = cv_alloc(n + 1)
    while at < n:
        if cv_ascii_space(text[at]):
            at += 1
            continue
        let pos: i64 = 0
        let quote: char = '\0'
        while at < n and (quote != '\0' or not cv_ascii_space(text[at])):
            let c: char = text[at]
            at += 1
            if c == '\\' and quote != '\'':
                if at == n: cc_error(cv_text("незаконченный escape в link"), 0, 0)
                c = text[at]
                at += 1
            elif quote != '\0':
                if c == quote:
                    quote = '\0'
                    continue
            elif c == '"' or c == '\'':
                quote = c
                continue
            part[pos] = c
            pos += 1
        if quote != '\0': cc_error(cv_text("незакрытая кавычка в link"), 0, 0)
        cv_push(out, cv_text(cv_cstring(part, pos)))
    return out

unsafe fn elf_link_manifest(file: i64, dirs: i64, names: i64, origins: i64):
    let source: i64 = cc_read_text_limit(file, 65536)
    let length: i64 = cv_len(source)
    let at: i64 = 0
    let line_number: i64 = 0
    let count: i64 = 0
    while at < length:
        let start: i64 = at
        while at < length and cv_byte(source, at) != '\n': at += 1
        let line: i64 = cv_strip(cv_subtext(source, start, at - start))
        at += 1
        line_number += 1
        if cv_len(line) == 0 or cv_starts(line, cv_text("#")): continue
        let number: i64 = cv_i(line_number)
        count += 1
        if count > 64: cc_error(cv_text("volt.mod: не более 64 записей"), file, number)
        let eq: i64 = cv_find(line, cv_text("="), 0)
        if eq <= 0: cc_error(cv_text("volt.mod: ожидалось имя = значение"), file, number)
        let key: i64 = cv_strip(cv_subtext(line, 0, eq))
        let value: i64 = cv_strip(cv_subtext(line, eq + 1, cv_len(line) - eq - 1))
        if cv_name(key, "library"):
            if not elf_libname(value): cc_error(cv_text("volt.mod: неверное имя разделяемой библиотеки"), file, number)
            if not cv_has(names, value):
                cv_add_set(names, value)
                cv_set(origins, value, number)
        elif cv_name(key, "library-dir"):
            if cv_len(value) == 0: cc_error(cv_text("volt.mod: пустой путь к библиотекам"), file, number)
            # This is one literal path, never a shell word or a linker option.
            cv_push(dirs, cc_path_join(cc_dirname(file), value))
        else:
            cc_error(cv_text("volt.mod: допустимы только library и library-dir"), file, number)

unsafe fn elf_libraries(directives: i64, manifest: i64) -> i64:
    let dirs: i64 = cv_list()
    let names: i64 = cv_vector(CV_SET)
    for i in 0..cv_len(directives):
        let words: i64 = elf_link_words(cv_at(directives, i))
        let at: i64 = 0
        while at < cv_len(words):
            let word: i64 = cv_at(words, at)
            at += 1
            if cv_starts(word, cv_text("-l")) and elf_libname(cv_subtext(word, 2, cv_len(word) - 2)):
                cv_add_set(names, cv_subtext(word, 2, cv_len(word) - 2))
            elif cv_starts(word, cv_text("-L")) and cv_len(word) > 2:
                cv_push(dirs, cv_subtext(word, 2, cv_len(word) - 2))
            elif cv_name(word, "-L") and at < cv_len(words) and not cv_starts(cv_at(words, at), cv_text("-")):
                cv_push(dirs, cv_at(words, at))
                at += 1
            else:
                cc_error(cv_cat(cv_text("запрещённый аргумент линковщика в link: "), cv_repr(word)), 0, 0)
    let origins: i64 = 0
    if manifest != 0:
        origins = cv_dict()
        elf_link_manifest(manifest, dirs, names, origins)
    cv_extend(dirs, x_words("/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib64 /lib /usr/lib /usr/local/lib"))
    let libs: i64 = cv_list()
    let seen: i64 = cv_vector(CV_SET)
    for i in 0..cv_len(names):
        let name: i64 = cv_at(names, i)
        let line: i64 = cv_get(origins, name, 0)
        let source: i64 = 0
        if line != 0: source = manifest
        let lib: ptr<ElfLibrary> = elf_find_lib(dirs, name, source, line) as ptr<ElfLibrary>
        if not cv_has(seen, lib.name):
            cv_add_set(seen, lib.name)
            cv_push(libs, lib as i64)
    return libs

unsafe fn elf_add_str(buf: ptr<ByteBuffer>, value: i64) -> u64:
    let offset: i64 = buf.len
    cc_bytes_append(buf, cv_cptr(value), cv_len(value) + 1)
    return offset as u64

unsafe fn elf_imports(code: ptr<AsmObject>, libraries: i64, out: ptr<ElfImports>):
    out.needed = cv_list()
    out.stubs = cv_list()
    let requirements: i64 = cv_list()
    let count: i64 = cv_len(libraries)
    let missing: i64 = cv_vector(CV_SET)
    for i in 0..cv_len(code.fixups):
        let fix: ptr<AsmFixup> = cv_at(code.fixups, i) as ptr<AsmFixup>
        if not cv_has(code.names, fix.symbol): cv_add_set(missing, fix.symbol)
    cc_bytes_fill(&out.strings, 1, 0)
    cc_bytes_fill(&out.symbols, 24, 0)
    cc_bytes_fill(&out.versym, 2, 0)
    for i in 0..count:
        let library: ptr<ElfLibrary> = cv_at(libraries, i) as ptr<ElfLibrary>
        cv_push(out.needed, cv_u(elf_add_str(&out.strings, library.name)))
        cv_push(requirements, cv_dict())
    code.section = ASM_TEXT
    let symbols: i64 = cv_sorted(missing)
    let version_index: i64 = 2
    for i in 0..cv_len(symbols):
        let symbol: i64 = cv_at(symbols, i)
        let owner: i64 = -1
        let version: i64 = 0
        for j in 0..count:
            let library: ptr<ElfLibrary> = cv_at(libraries, j) as ptr<ElfLibrary>
            version = cv_get(library.exports, symbol, 0)
            if version != 0:
                owner = j
                break
        if owner < 0: cc_error(cv_cat(cv_text("link: неопределённый символ "), symbol), 0, 0)
        let ver_name: i64 = cv_at(version, 0)
        let index: i64 = 1
        if cv_len(ver_name) != 0:
            let group: i64 = cv_at(requirements, owner)
            let existing: i64 = cv_get(group, ver_name, 0)
            if existing == 0:
                if version_index >= 0x8000: cc_error(cv_text("ELF: слишком много версий импорта"), 0, 0)
                existing = cv_pair(cv_i(version_index), cv_at(version, 1))
                cv_set(group, ver_name, existing)
                version_index += 1
            index = cv_index(cv_at(existing, 0))
        cc_bytes_word(&out.versym, index as u64, 2)
        cc_bytes_word(&out.symbols, elf_add_str(&out.strings, symbol), 4)
        cc_bytes_word(&out.symbols, 0x12, 1)
        cc_bytes_fill(&out.symbols, 19, 0)
        cv_push(out.stubs, cv_i(asm_offset(code)))
        asm_label(code, symbol)
        asm_word(code, 0x25ff, 6)
    cc_bytes_word(&out.hash, 1, 4)
    cc_bytes_word(&out.hash, (cv_len(out.stubs) + 1) as u64, 4)
    cc_bytes_fill(&out.hash, 4 * (cv_len(out.stubs) + 2), 0)
    let previous: i64 = -1
    for i in 0..count:
        let group: i64 = cv_at(requirements, i)
        let n: i64 = cv_len(group)
        if n == 0: continue
        if previous >= 0: cc_bytes_set(&out.verneed, previous + 12, (out.verneed.len - previous) as u64, 4)
        previous = out.verneed.len
        out.verneed_count += 1
        cc_bytes_word(&out.verneed, 1, 2)
        cc_bytes_word(&out.verneed, n as u64, 2)
        cc_bytes_word(&out.verneed, x_bits(cv_at(out.needed, i)), 4)
        cc_bytes_word(&out.verneed, 16, 4)
        cc_bytes_word(&out.verneed, 0, 4)
        for j in 0..n:
            let name: i64 = cv_at(group, j)
            let metadata: i64 = cv_get(group, name, 0)
            cc_bytes_word(&out.verneed, x_bits(cv_at(metadata, 1)), 4)
            cc_bytes_word(&out.verneed, 0, 2)
            cc_bytes_word(&out.verneed, x_bits(cv_at(metadata, 0)), 2)
            cc_bytes_word(&out.verneed, elf_add_str(&out.strings, name), 4)
            let next: u64 = 0
            if j < n - 1: next = 16
            cc_bytes_word(&out.verneed, next, 4)
