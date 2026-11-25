use volt_syntax

unsafe fn cc_find_module(file: i64, name: i64) -> i64:
    let filename: i64 = cv_cat(name, cv_text(".volt"))
    let local: i64 = cc_abspath(cc_path_join(cc_dirname(file), filename))
    if not cv_equal(local, file) and cc_regular(local): return local
    let standard: i64 = cc_path_join(cc_std, filename)
    if not cv_equal(standard, file) and cc_regular(standard): return standard
    # Optional components belong to this installation, not the working directory.
    let components: [3]string = ["browser/modules", "gpu/modules", "tools/modules"]
    for i in 0..len(components):
        let module: i64 = cc_path_join(cc_path_join(cc_root, cv_text(components[i])), filename)
        if not cv_equal(module, file) and cc_regular(module): return module
    cc_error(cv_cat(cv_cat(cv_text("модуль "), cv_repr(name)), cv_text(" не найден")), file, cv_i(1))
    return 0

unsafe fn cc_discover(path: i64, modules: i64, sources: i64, active: i64, depth: i64) -> i64:
    if depth > 128: cc_error(cv_text("слишком много вложенных импортов"), path, cv_i(1))
    if cv_has(active, path): cc_error(cv_cat(cv_text("цикл импорта модуля "), path), path, cv_i(1))
    let found: i64 = cv_get(modules, path, 0)
    if found != 0: return found
    let program: i64 = ccp_parse_program(ccp_new(cc_read_text(path), path))
    cv_set(modules, path, program)
    cv_push(sources, program)
    cv_add_set(active, path)
    let deps: i64 = cv_list()
    let namespaces: i64 = cv_dict()
    let uses: i64 = cv_getkey(program, "uses")
    for i in 0..cv_len(uses):
        let item: i64 = cv_at(uses, i)
        if not cv_starts(item, cv_text("__link__:")):
            let imported: i64 = cc_discover(cc_find_module(path, item), modules, sources, active, depth + 1)
            cv_push(deps, imported)
            let alias: i64 = cv_get(cv_getkey(program, "use_aliases"), cv_i(i), 0)
            if cv_getkey(imported, "module") != 0:
                if alias == 0: alias = item
                if cv_has(namespaces, alias) and cv_get(namespaces, alias, 0) != imported:
                    cc_error(cv_cat(cv_text("повторное имя пространства: "), alias), path, cv_i(1))
                cv_set(namespaces, alias, imported)
            elif alias != 0:
                cc_error(cv_text("use ... as требует модуль с заголовком module"), path, cv_i(1))
    cv_remove(active, path)
    cv_field(program, "dependencies", deps)
    if cv_len(namespaces) != 0: cv_field(program, "namespaces", namespaces)
    return program

unsafe fn cc_order_module(program: i64, ordered: i64):
    if cv_truth(cv_getkey(program, "ordered")): return
    cv_field(program, "ordered", CV_TRUE)
    let deps: i64 = cv_getkey(program, "dependencies")
    for i in 0..cv_len(deps): cc_order_module(cv_at(deps, i), ordered)
    cv_push(ordered, program)

unsafe fn cc_load_modules(entry: i64, links: i64) -> i64:
    let modules: i64 = cv_dict()
    let sources: i64 = cv_list()
    let active: i64 = cv_vector(CV_SET)
    let entry_program: i64 = cc_discover(entry, modules, sources, active, 0)
    let ordered: i64 = cv_list()
    let names: i64 = cv_split(cv_text("io str"), 0, 0)
    for i in 0..cv_len(names):
        # A stdlib module compiles standalone: the prelude does not self-import.
        let candidate: i64 = cv_cat(cv_at(names, i), cv_text(".volt"))
        if cv_equal(cc_abspath(cc_path_join(cc_dirname(entry), candidate)), entry): continue
        if cv_equal(cc_path_join(cc_std, candidate), entry): continue
        let path: i64 = cc_find_module(entry, cv_at(names, i))
        cc_order_module(cc_discover(path, modules, sources, active, 0), ordered)
    cc_order_module(entry_program, ordered)
    for i in 0..cv_len(sources):
        let uses: i64 = cv_getkey(cv_at(sources, i), "uses")
        for j in 0..cv_len(uses):
            let directive: i64 = cv_at(uses, j)
            if cv_starts(directive, cv_text("__link__:")):
                cv_push(links, cv_subtext(directive, 9, cv_len(directive) - 9))
    return ordered

unsafe fn ccs_auto_std(state: i64):
    # The module loader already put the prelude before user initialization.
    return
