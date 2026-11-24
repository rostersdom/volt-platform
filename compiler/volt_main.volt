use volt_lower
use elf_write
use volt_runtime

struct CCOptions:
    source: i64
    output: i64
    listing: i64
    manifest: i64
    args: i64
    parse: bool
    asm_only: bool
    quiet: bool
    run: bool
    debug: bool

unsafe fn cc_args(first: i64) -> i64:
    let out: i64 = cv_list()
    let argv: ptr<ptr<char>> = VOLT_rt_argv()
    for i in first..argc(): cv_push(out, cv_text(argv[i] as string))
    return out

unsafe fn cc_run(path: i64, args: i64) -> i64:
    let count: i64 = cv_len(args)
    let argv: ptr<ptr<char>> = cv_alloc((count + 2) * 8) as ptr<ptr<char>>
    argv[0] = cv_cptr(path)
    for i in 0..count: argv[1 + i] = cv_cptr(cv_at(args, i))
    argv[count + 1] = 0 as ptr<char>
    match process_exec_wait(cv_cptr(path) as string, argv):
        Ok(status): return status
        Err(error): return 127

unsafe fn cc_output_name(source: i64) -> i64:
    if cv_ends(source, cv_text(".volt")):
        return cv_cat(cv_subtext(source, 0, cv_len(source) - 5), cv_text(".s"))
    return cv_cat(source, cv_text(".s"))

unsafe fn cc_same_existing_file(a: i64, b: i64) -> bool:
    let first: [32]u64
    let second: [32]u64
    if cc_file_metadata(cv_cptr(a), &first[0]) < 0: return false
    if cc_file_metadata(cv_cptr(b), &second[0]) < 0: return false
    return (first[0] & second[0] & 0x100) != 0 and first[4] == second[4] and first[17] == second[17]

unsafe fn cc_same_file(a: i64, b: i64) -> bool:
    if cv_equal(cc_abspath(a), cc_abspath(b)): return true
    return cc_same_existing_file(a, b)

unsafe fn cc_lines(buf: ptr<ByteBuffer>, code: ptr<AsmObject>, lines: i64, listing: bool):
    for i in 0..cv_len(lines):
        let line: i64 = cv_at(lines, i)
        if code != (0 as ptr<AsmObject>): x_encode(code, line)
        if listing:
            cc_bytes_append(buf, cv_cptr(line), cv_len(line))
            cc_bytes_word(buf, 10, 1)

unsafe fn cc_lower(state: i64, code: ptr<AsmObject>, listing: ptr<ByteBuffer>, keep_listing: bool):
    let emitter: i64 = cce_new(state)
    if keep_listing:
        let header: string = ".intel_syntax noprefix\n.text\n.align 16\n"
        cc_bytes_append(listing, header as ptr<char>, str_len(header))
    let progs: i64 = cv_getkey(state, "progs")
    for i in 0..cv_len(progs):
        let functions: i64 = cv_getkey(cv_at(progs, i), "fns")
        for j in 0..cv_len(functions):
            let target: i64 = cv_at(functions, j)
            if cv_getkey(target, "body") != 0 and not cv_truth(cv_getkey(target, "type_params")):
                cc_function(emitter, code, listing, keep_listing, target, 0)
    let specialized: i64 = cv_getkey(state, "specializations")
    for i in 0..cv_len(specialized):
        let target: i64 = cv_at(specialized, i)
        let name: i64 = cc_function_label(cv_getkey(target, "mangled_name"), cv_getkey(target, "file"))
        cc_function(emitter, code, listing, keep_listing, target, name)
    cce_emit_globals(emitter)
    let startup: i64 = cv_text("VOLT_f_main")
    cc_function(emitter, code, listing, keep_listing, cv_getkey(state, "main_fn"), startup)
    if code != (0 as ptr<AsmObject>) and code.debug_functions != 0:
        cc_startup_source(code, progs, startup)
    let names: i64 = x_words("rodata data bss")
    for i in 0..3:
        let name: i64 = cv_at(names, i)
        let data: i64 = cv_get(emitter, name, 0)
        if cv_len(data) == 0: continue
        let directive: i64 = cv_cat(cv_text("."), name)
        if i == 0: directive = cv_text(".section .rodata")
        cc_lines(listing, code, cv_single(directive), keep_listing)
        cc_lines(listing, code, data, keep_listing)
    if keep_listing:
        let stack: string = ".section .note.GNU-stack,\"\",@progbits\n"
        cc_bytes_append(listing, stack as ptr<char>, str_len(stack))
    cc_error_file = 0

unsafe fn cc_startup_source(code: ptr<AsmObject>, progs: i64, label: i64):
    # Anchor startup to the first entry-file statement, not to a synthetic line 1.
    # The wrapper starts before any implicit module initialization calls.
    for i in 0..cv_len(progs):
        let prog: i64 = cv_at(progs, i)
        if not cv_truth(cv_getkey(prog, "is_entry")): continue
        let statements: i64 = cv_getkey(prog, "main")
        for j in 0..cv_len(statements):
            let stmt: i64 = cv_at(statements, j)
            if cv_classes(stmt, "ConstStmt"): continue
            asm_source_function(code, label, cv_getkey(prog, "file"), cv_index(cv_getkey(stmt, "line")))
            break
        return

unsafe fn cc_function(emitter: i64, code: ptr<AsmObject>, listing: ptr<ByteBuffer>, keep_listing: bool, target: i64, name: i64):
    if code != (0 as ptr<AsmObject>): code.section = ASM_TEXT
    cv_field(emitter, "text", cv_list())
    let file: i64 = cv_getkey(target, "file")
    let line: i64 = cv_index(cv_getkey(target, "line"))
    cc_error_file = file
    cc_error_line = line
    cce_emit_fn(emitter, target, name)
    cc_lines(listing, code, cv_getkey(emitter, "text"), keep_listing)
    # VOLT_f_main is a generated startup wrapper, not an explicit source function.
    if code != (0 as ptr<AsmObject>) and code.debug_functions != 0 and not cv_name(name, "VOLT_f_main"):
        let label: i64 = name
        if label == 0: label = cc_function_label(cv_getkey(target, "name"), file)
        asm_source_function(code, label, file, line)
    cc_error_file = 0

unsafe fn cc_dump(node: i64, depth: i64):
    let kind: i64 = cv_kind(node)
    if depth > 128:
        put_str("...")
        return
    if kind == CV_NODE:
        put_str(cv_cptr(cv_typename(node)) as string)
        put_char('(')
        let fields: i64 = cv_items(node)
        for i in 0..cv_len(fields):
            let field: i64 = cv_at(fields, i)
            let key: i64 = cv_at(field, 0)
            if cv_name(key, "file") or cv_name(key, "line"): continue
            nl()
            for j in 0..(2 * depth + 2): put_char(' ')
            put_str(cv_cptr(key) as string)
            put_str(" = ")
            cc_dump(cv_at(field, 1), depth + 1)
        nl()
        for i in 0..2*depth: put_char(' ')
        put_char(')')
    elif kind == CV_LIST or kind == CV_TUPLE:
        put_char('[')
        for i in 0..cv_len(node):
            if i != 0: put_str(", ")
            cc_dump(cv_at(node, i), depth)
        put_char(']')
    else:
        put_str(cv_cptr(cv_repr(node)) as string)

unsafe fn cc_build(opts: ptr<CCOptions>) -> i64:
    let entry: i64 = cc_abspath(opts.source)
    if opts.parse:
        cc_dump(ccp_parse_program(ccp_new(cc_read_text(entry), entry)), 0)
        nl()
        return 0
    let links: i64 = cv_list()
    let state: i64 = ccs_new(cc_load_modules(entry, links), entry)
    ccs_run(state)
    cc_error_file = 0
    let manifest: i64 = 0
    if opts.manifest != 0:
        # Let the kernel resolve symlinks before interpreting `..`.
        manifest = cc_path_join(cc_cwd, opts.manifest)
        if (opts.output != 0 and cc_same_existing_file(opts.output, manifest)) or (opts.listing != 0 and cc_same_existing_file(opts.listing, manifest)):
            cc_error(cv_text("нельзя перезаписывать манифест выходным файлом"), manifest, cv_i(1))
    if opts.asm_only and opts.listing == 0: opts.listing = cc_output_name(opts.source)
    if opts.output != 0 and cc_same_file(opts.output, entry): cc_error(cv_text("ELF должен быть отдельным файлом"), 0, 0)
    if opts.listing != 0:
        if cc_same_file(opts.listing, entry) or (opts.output != 0 and cc_same_file(opts.listing, opts.output)):
            cc_error(cv_text("листинг должен быть отдельным файлом"), 0, 0)
    let listing: ByteBuffer
    if opts.asm_only:
        cc_lower(state, 0 as ptr<AsmObject>, &listing, true)
        cc_write_file(opts.listing, listing.data as ptr<char>, listing.len, 420)
        if not opts.quiet:
            put_str("asm → ")
            put_str(cv_cptr(opts.listing) as string)
            nl()
        return 0
    let libraries: i64 = elf_libraries(links, manifest)
    let obj: AsmObject
    asm_setup(&obj)
    if opts.debug: obj.debug_functions = cv_list()
    cc_lower(state, &obj, &listing, opts.listing != 0)
    cc_runtime(&obj)
    let output: ByteBuffer
    elf_executable(&obj, libraries, entry, &output)
    if opts.listing != 0: cc_write_file(opts.listing, listing.data as ptr<char>, listing.len, 420)
    if opts.output != 0:
        cc_write_file(opts.output, output.data as ptr<char>, output.len, 493)
        if opts.run: return cc_run(cc_abspath(opts.output), opts.args)
        if not opts.quiet:
            put_str("ok: ")
            put_str(cv_cptr(opts.output) as string)
            nl()
        return 0
    let directory: i64 = cc_environment(cv_text("TMPDIR"))
    if directory == 0 or cv_len(directory) == 0: directory = cv_text("/tmp")
    let file: CCOutput = cc_open_output(cc_abspath(directory), "volt-")
    cc_store(file, output.data as ptr<char>, output.len, 448)
    if opts.run:
        let status: i64 = cc_run(file.path, opts.args)
        cc_unlink(cv_cptr(file.path))
        return status
    if not opts.quiet:
        put_str("ok: ")
        put_str(cv_cptr(file.path) as string)
        nl()
    return 0

unsafe fn cc_launch(args: i64) -> i64:
    let pos: i64 = 0
    let n: i64 = cv_len(args)
    if n > 0 and cv_name(cv_at(args, 0), "--"): pos += 1
    if pos == n:
        put_errnl("volt-launch: usage: volt-launch [--] <source.volt|browser> [program args...]")
        return 2
    let entry: i64 = cv_at(args, pos)
    let browser: i64 = cc_path_join(cc_root, cv_text("browser/browser.volt"))
    if not cc_regular(browser): browser = cc_path_join(cc_root, cv_text("apps/browser.volt"))
    if cv_name(entry, "browser"): entry = browser
    if cv_starts(entry, cv_text("-")) or not cv_ends(entry, cv_text(".volt")) or not cc_regular(entry):
        put_err("volt-launch: source not found or not a .volt file: ")
        put_errnl(cv_cptr(entry) as string)
        return 2
    let term: [128]char
    if not cc_same_file(entry, browser) and cc_isatty(0, &term[0]) == 0 and cc_isatty(2, &term[0]) == 0:
        put_err("VOLT source is executable code. Run? [y/N] ")
        let line: [16]char
        let amount: i64 = read(0, &line[0], len(line) - 1)
        if amount <= 0 or not cv_name(cv_lower(cv_strip(cv_text(cv_cstring(&line[0], max(0, amount))))), "y"):
            put_errnl("Cancelled.")
            return 0
    let opts: CCOptions
    opts.source = entry
    opts.run = true
    opts.quiet = true
    opts.args = cv_slice(args, cv_i(pos + 1), 0)
    if cv_name(cc_basename(entry), "browser.volt") and cv_len(opts.args) == 1 and cv_name(cv_at(opts.args, 0), "--check"):
        let demo: i64 = cc_path_join(cc_root, cv_text("examples/page.html"))
        if not cc_regular(demo): demo = cv_text("about:home")
        cv_push(opts.args, demo)
    return cc_build(&opts)

unsafe fn cc_cli() -> i64:
    let args: i64 = cc_args(1)
    let n: i64 = cv_len(args)
    if n == 0:
        print("VOLT для Linux x86-64: volt FILE.volt [-o FILE] [-g] [--manifest FILE] [--run] [--emit-asm] [--parse]")
        return 0
    if cv_name(cv_at(args, 0), "--launch"):
        cc_find_root()
        cc_constants()
        x_init()
        return cc_launch(cv_slice(args, cv_i(1), 0))
    let opts: CCOptions
    let target: i64 = cv_text("linux-x86_64")
    let i: i64 = 0
    while i < n:
        let arg: i64 = cv_at(args, i)
        i += 1
        if cv_name(arg, "--version") or cv_name(arg, "-v"):
            print("VOLT Language v0.3.0")
            return 0
        if cv_name(arg, "--help") or cv_name(arg, "-h"):
            print("VOLT для Linux x86-64: volt FILE.volt [-o FILE] [-g] [--manifest FILE] [--run] [--emit-asm] [--parse]")
            return 0
        if cv_name(arg, "--run"): opts.run = true
        elif cv_name(arg, "-g"): opts.debug = true
        elif cv_name(arg, "--quiet"): opts.quiet = true
        elif cv_name(arg, "--emit-asm"): opts.asm_only = true
        elif cv_name(arg, "--parse"): opts.parse = true
        elif cv_starts(arg, cv_text("--target=")):
            target = cv_subtext(arg, 9, cv_len(arg) - 9)
            if cv_len(target) == 0: cc_error(cv_text("--target требует значение"), 0, 0)
        elif cv_name(arg, "--target") or cv_name(arg, "-o") or cv_name(arg, "--out") or cv_name(arg, "-S") or cv_name(arg, "--asm-file") or cv_name(arg, "--manifest"):
            if i == n or cv_starts(cv_at(args, i), cv_text("-")): cc_error(cv_cat(arg, cv_text(" требует значение")), 0, 0)
            let item: i64 = cv_at(args, i)
            i += 1
            if cv_name(arg, "--target"):
                if cv_ends(item, cv_text(".volt")): cc_error(cv_text("--target требует значение"), 0, 0)
                target = item
            elif cv_name(arg, "-S") or cv_name(arg, "--asm-file"): opts.listing = item
            elif cv_name(arg, "--manifest"):
                if opts.manifest != 0: cc_error(cv_text("--manifest можно указать только один раз"), 0, 0)
                opts.manifest = item
            else: opts.output = item
        elif cv_starts(arg, cv_text("-")): cc_error(cv_cat(cv_text("неизвестный флаг "), arg), 0, 0)
        elif opts.source != 0: cc_error(cv_cat(cv_text("лишний аргумент "), arg), 0, 0)
        else: opts.source = arg
    if not cv_name(target, "linux-x86_64"): cc_error(cv_cat(cv_text("неподдерживаемая цель "), cv_repr(target)), 0, 0)
    if opts.source == 0: cc_error(cv_text("укажите файл .volt"), 0, 0)
    if opts.debug and (opts.parse or opts.asm_only): cc_error(cv_text("-g требует выходной ELF"), 0, 0)
    if opts.manifest != 0 and (opts.parse or opts.asm_only): cc_error(cv_text("--manifest требует выходной ELF"), 0, 0)
    cc_find_root()
    cc_constants()
    x_init()
    return cc_build(&opts)

fn main() -> i64:
    unsafe: return cc_cli()
