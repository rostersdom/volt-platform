# VOLT compiler, native self-hosted implementation.
use volt_types
use module_loader
use volt_ownership

unsafe fn ccs_new(v_progs: i64, v_entry_name: i64) -> i64:
    let v_self: i64 = cv_node("Sem")
    cv_field(v_self, "progs", v_progs)
    cv_field(v_self, "module_files", cv_dict())
    cv_field(v_self, "entry_name", v_entry_name)
    cv_field(v_self, "fns", cv_dict())
    cv_field(v_self, "generic_fns", cv_dict())
    let items_1: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "specializations", items_1)
    cv_field(v_self, "specialization_cache", cv_dict())
    cv_field(v_self, "type_vars", cv_dict())
    cv_field(v_self, "enum_defs", cv_dict())
    cv_field(v_self, "enums", cv_dict())
    cv_field(v_self, "globals", cv_dict())
    cv_field(v_self, "const_globals", cv_dict())
    let items_2: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "global_order", items_2)
    cv_field(v_self, "defer_blocks", cv_dict())
    cv_field(v_self, "defer_serial", 3)
    let items_3: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "links", items_3)
    cv_field(v_self, "errors", 3)
    cv_field(v_self, "types_structs", cv_dict())
    cv_field(v_self, "struct_defs", cv_dict())
    cv_field(v_self, "generic_struct_count", 3)
    cv_field(v_self, "_ptr_char", cc_TPtr(cc_k_char_type))
    cv_field(v_self, "_string", cc_k_string_type)
    cv_field(v_self, "unsafe_depth", 3)
    cv_field(v_self, "borrowed_slots", cv_vector(CV_SET))
    cv_field(v_self, "frozen_mut_slots", cv_vector(CV_SET))
    cv_field(v_self, "temp_slice_releases", cv_vector(CV_LIST))
    cv_field(v_self, "defer_action_depth", 0)
    cv_field(v_self, "tf_depth", 3)
    cv_field(v_self, "buffer_borrow_file", cc_path_join(cc_std, cv_text("borrow_buffer.volt")))
    cv_field(v_self, "owned_buffer_file", cc_path_join(cc_std, cv_text("owned_buffer.volt")))
    cv_field(v_self, "fs_file", cc_path_join(cc_std, cv_text("fs.volt")))
    cv_field(v_self, "owned_kinds", cc_owner_kinds(v_self))
    cv_field(v_self, "lbl_prefix", cv_text("VOLT_L"))
    return v_self

# Semantic diagnostic anchored at an AST node: shows the byte column the
# parser recorded on the node, or falls back to the line-only format.
unsafe fn ccs_error(msg: i64, file: i64, node: i64):
    cc_error_at(msg, file, cv_getkey(node, "line"), cc_node_column(node))

unsafe fn ccs_register_namespaces(state: i64):
    let programs: i64 = cv_getkey(state, "progs")
    for i in 0..cv_len(programs):
        let prog: i64 = cv_at(programs, i)
        let file: i64 = cv_getkey(prog, "file")
        let scoped: bool = cv_getkey(prog, "module") != 0
        if scoped or cv_getkey(prog, "namespaces") != 0:
            cv_set(cv_getkey(state, "module_files"), file, prog)
            cv_field(state, "namespaced_code", CV_TRUE)
        if not scoped: continue
        let symbols: i64 = cv_dict()
        cv_field(prog, "symbols", symbols)
        cv_field(prog, "symbol_prefix", cv_mod(cv_text("$m%d$"), cv_i(i)))
        let tables: [4]string = ["structs", "enums", "fns", "main"]
        for j in 0..len(tables):
            let declarations: i64 = cv_getkey(prog, tables[j])
            for k in 0..cv_len(declarations):
                let def: i64 = cv_at(declarations, k)
                if j == 3 and not cv_classes(def, "ConstStmt") and (not cv_classes(def, "LetStmt") or cv_equal(file, cv_getkey(state, "entry_name"))): continue
                let name: i64 = cv_getkey(def, "name")
                if cv_has(symbols, name):
                    cc_error(cv_cat(cv_text("дубликат объявления в модуле: "), name), file, cv_getkey(def, "line"))
                cv_set(symbols, name, def)
                cv_field(def, "source_name", name)
                cv_field(def, "name", cv_cat(cv_getkey(prog, "symbol_prefix"), name))
                if j == 0: cv_field(def, "opaque", CV_TRUE)

unsafe fn ccs_namespace(state: i64, file: i64, alias: i64) -> i64:
    let prog: i64 = cv_get(cv_getkey(state, "module_files"), file, 0)
    return cv_get(cv_getkey(prog, "namespaces"), alias, 0)

unsafe fn ccs_export(target: i64, member: i64, file: i64, line: i64) -> i64:
    let def: i64 = cv_get(cv_getkey(target, "symbols"), member, 0)
    if def == 0:
        cc_error(cv_mod(cv_text("модуль %s: неизвестное имя %s"), cv_pair(cv_getkey(target, "module"), member)), file, line)
        return 0
    if not cv_truth(cv_getkey(def, "pub")):
        cc_error(cv_mod(cv_text("модуль %s: %s — приватное объявление (нет pub)"), cv_pair(cv_getkey(target, "module"), member)), file, line)
        return 0
    return cv_getkey(def, "name")

unsafe fn ccs_module_name(state: i64, name: i64, file: i64, line: i64) -> i64:
    let prog: i64 = cv_get(cv_getkey(state, "module_files"), file, 0)
    if prog == 0: return name
    let def: i64 = cv_get(cv_getkey(prog, "symbols"), name, 0)
    if def != 0: return cv_getkey(def, "name")
    if not cv_contains(name, cv_text(".")): return name
    let parts: i64 = cv_split(name, cv_text("."), cv_i(1))
    let target: i64 = ccs_namespace(state, file, cv_at(parts, 0))
    if target != 0: return ccs_export(target, cv_at(parts, 1), file, line)
    return name

unsafe fn ccs_opaque_access(typ: i64, file: i64, line: i64, message: string):
    let owner: i64 = cv_getkey(typ, "opaque_file")
    if owner != 0 and not cv_equal(owner, file):
        cc_error(cv_text(message), file, line)

unsafe fn ccs_default_access(typ: i64, file: i64, line: i64):
    if not cv_classes(typ, "TArray") and not cv_classes(typ, "TStruct"): return
    let pending: i64 = cv_list()
    let seen: i64 = cv_vector(CV_SET)
    cv_push(pending, typ)
    while cv_len(pending) > 0:
        let record: i64 = cv_pop(pending)
        while cv_classes(record, "TArray"): record = cv_getkey(record, "elem")
        if not cv_classes(record, "TStruct") or cv_contains(seen, cv_i(record)): continue
        cv_add_set(seen, cv_i(record))
        ccs_opaque_access(record, file, line, "приватный конструктор struct: требуется инициализатор")
        let fields: i64 = cv_getkey(record, "fields")
        for i in 0..cv_len(fields): cv_push(pending, cv_at(cv_at(fields, i), 1))

unsafe fn ccs_callback_type(v_self: i64, v_params: i64, v_result: i64, v_file: i64, v_line: i64) -> i64:
    # A VOLT enum uses its i64 representation, not the layout of a C enum.
    for i in 0..cv_len(v_params):
        let typ: i64 = cv_at(v_params, i)
        if cc_is_owned_ptr(typ) or (not cv_truth(cc_compatible(typ)) and not cv_classes(typ, "TEnum")):
            cc_error(cv_text("callback поддерживает только скалярный ABI C"), v_file, v_line)
            return 0
    if v_result != 0 and (cc_is_owned_ptr(v_result) or (not cv_truth(cc_compatible(v_result)) and not cv_classes(v_result, "TEnum"))):
        cc_error(cv_text("callback поддерживает только скалярный ABI C"), v_file, v_line)
        return 0
    return cc_TFnPtr(v_params, v_result)

unsafe fn cc_compatible(v_t: i64) -> i64:
    let choice_1: i64 = cv_bool((cv_name(cv_typename(v_t), "TInt")))
    if not cv_truth(choice_1):
        choice_1 = cv_bool(cv_classes(v_t, "TFloat") or cv_classes(v_t, "TBool") or cv_classes(v_t, "TPtr"))
    return choice_1

unsafe fn ccs_resolve_type(v_self: i64, v_t: i64, v_indirect: i64) -> i64:
    let v_file: i64 = 0
    let v_n: i64 = 0
    let v_typ: i64 = 0
    let v_name: i64 = 0
    let v_args: i64 = 0
    let v_types: i64 = 0
    let v_elem: i64 = 0
    let v_params: i64 = 0
    let v_result: i64 = 0
    let v_resolved_params: i64 = 0
    let v_resolved_result: i64 = 0
    v_file = cv_get(v_t, cv_text("file"), 0)
    if (cv_equal(cv_getkey(v_t, "kind"), cv_text("name"))):
        v_n = cv_subscript(cv_getkey(v_t, "a"), 3)
        # The module must not compile with a compiler that lacks its lifetime checks.
        if cv_name(v_n, "__VoltBorrowScopeV2") and cv_equal(v_file, cv_getkey(v_self, "buffer_borrow_file")):
            return cc_int(CV_TRUE, cv_i(8))
        if cc_owner_guard(v_self, v_n, v_file):
            return cc_int(CV_TRUE, cv_i(8))
        if (cv_contains(cv_getkey(v_self, "type_vars"), v_n)):
            v_typ = cv_subscript(cv_getkey(v_self, "type_vars"), v_n)
            if not (cv_truth(v_indirect)):
                ccs_ensure_layout(v_self, v_typ)
            return v_typ
        if ((cv_equal(v_n, cv_text("i8")) or cv_equal(v_n, cv_text("i16")) or cv_equal(v_n, cv_text("i32")) or cv_equal(v_n, cv_text("i64")))):
            return cc_int(CV_TRUE, cv_int(cv_slice(v_n, 11, 0), 83))
        if ((cv_equal(v_n, cv_text("u8")) or cv_equal(v_n, cv_text("u16")) or cv_equal(v_n, cv_text("u32")) or cv_equal(v_n, cv_text("u64")))):
            return cc_int(CV_FALSE, cv_int(cv_slice(v_n, 11, 0), 83))
        if ((cv_equal(v_n, cv_text("f32")) or cv_equal(v_n, cv_text("f64")))):
            return cc_TFloat(cv_int(cv_slice(v_n, 11, 0), 83))
        if (cv_equal(v_n, cv_text("int"))):
            return cc_int(CV_TRUE, 515)
        if (cv_equal(v_n, cv_text("uint"))):
            return cc_int(CV_FALSE, 515)
        if (cv_equal(v_n, cv_text("float"))):
            return cc_TFloat(515)
        if (cv_equal(v_n, cv_text("char"))):
            return cc_k_char_type
        if (cv_equal(v_n, cv_text("bool"))):
            return cc_TBool()
        if (cv_equal(v_n, cv_text("string"))):
            return cv_getkey(v_self, "_string")
        v_n = ccs_module_name(v_self, v_n, v_file, cv_getkey(v_t, "line"))
        if (cv_contains(cv_getkey(v_self, "enums"), v_n)):
            return cv_subscript(cv_getkey(v_self, "enums"), v_n)
        if ((cv_equal(v_n, cv_text("Option")) or cv_equal(v_n, cv_text("Result")))):
            ccs_error(cv_cat(cv_format(v_n, ""), cv_text(" должен быть параметризован типом payload")), v_file, v_t)
            return 0
        if (cv_contains(cv_getkey(v_self, "struct_defs"), v_n)):
            let items_1: i64 = cv_vector(CV_TUPLE)
            return ccs_struct_type(v_self, v_n, items_1, v_file, cv_getkey(v_t, "line"), v_indirect)
        let choice_2: i64 = 0
        if cv_has(v_t, cv_text("file")):
            choice_2 = cv_getkey(v_t, "file")
        else:
            choice_2 = 0
        ccs_error(cv_add(cv_text("неизвестный тип "), v_n), choice_2, v_t)
        return 0
    if (cv_equal(cv_getkey(v_t, "kind"), cv_text("struct_type"))):
        let unpack_3: i64 = cv_getkey(v_t, "a")
        v_name = ccs_module_name(v_self, cv_at(unpack_3, 0), v_file, cv_getkey(v_t, "line"))
        v_args = cv_slice(unpack_3, 11, 0)
        let collect_4: i64 = cv_vector(CV_LIST)
        let seq_6: i64 = v_args
        for index_5 in 0..cv_len(seq_6):
            let a_7: i64 = cv_at(seq_6, index_5)
            cv_push(collect_4, ccs_resolve_type(v_self, a_7, CV_TRUE))
        v_types = cv_astuple(collect_4)
        return ccs_struct_type(v_self, v_name, v_types, v_file, cv_getkey(v_t, "line"), v_indirect)
    if (cv_equal(cv_getkey(v_t, "kind"), cv_text("resolved"))):
        v_typ = cv_subscript(cv_getkey(v_t, "a"), 3)
        if not (cv_truth(v_indirect)):
            ccs_ensure_layout(v_self, v_typ)
        return v_typ
    let subject_8: i64 = cv_getkey(v_t, "kind")
    if ((cv_equal(subject_8, cv_text("option")) or cv_equal(subject_8, cv_text("result")))):
        let choice_9: i64 = 0
        if (cv_equal(cv_getkey(v_t, "kind"), cv_text("option"))):
            choice_9 = cv_text("Option")
        else:
            choice_9 = cv_text("Result")
        v_name = choice_9
        let collect_10: i64 = cv_vector(CV_LIST)
        let seq_12: i64 = cv_getkey(v_t, "a")
        for index_11 in 0..cv_len(seq_12):
            let a_13: i64 = cv_at(seq_12, index_11)
            cv_push(collect_10, ccs_resolve_type(v_self, a_13, CV_TRUE))
        v_args = cv_astuple(collect_10)
        return ccs_wrapper_type(v_self, v_name, v_args, v_file, cv_getkey(v_t, "line"), v_indirect)
    if (cv_equal(cv_getkey(v_t, "kind"), cv_text("ptr"))):
        v_elem = ccs_resolve_type(v_self, cv_subscript(cv_getkey(v_t, "a"), 3), CV_TRUE)
        if cc_is_owned(v_elem) and not cv_equal(v_file, cc_owned_home(v_elem)):
            ccs_error(cv_cat(cv_text("указатель на "), cv_cat(cc_owner_title(v_elem), cv_text(" нельзя объявить или привести к нему"))), v_file, v_t)
        if cc_is_mut_slice(v_elem):
            ccs_error(cv_text("ptr не может ссылаться на дескриптор изменяемого slice"), v_file, v_t)
            return 0
        if cv_truth(cc_contains_tagged_type(v_elem)):
            ccs_error(cv_text("ptr не может скрывать Option/Result или enum с payload"), v_file, v_t)
            return 0
        return cc_TPtr(v_elem)
    if (cv_equal(cv_getkey(v_t, "kind"), cv_text("fnptr"))):
        let unpack_18: i64 = cv_getkey(v_t, "a")
        v_params = cv_at(unpack_18, 0)
        v_result = cv_at(unpack_18, 1)
        let collect_19: i64 = cv_vector(CV_LIST)
        let seq_21: i64 = v_params
        for index_20 in 0..cv_len(seq_21):
            let p_22: i64 = cv_at(seq_21, index_20)
            cv_push(collect_19, ccs_resolve_type(v_self, p_22, CV_TRUE))
        v_resolved_params = cv_astuple(collect_19)
        let choice_23: i64 = 0
        if (not (v_result == 0)):
            choice_23 = ccs_resolve_type(v_self, v_result, CV_TRUE)
        else:
            choice_23 = 0
        v_resolved_result = choice_23
        return ccs_callback_type(v_self, v_resolved_params, v_resolved_result, v_file, cv_getkey(v_t, "line"))
    let subject_24: i64 = cv_getkey(v_t, "kind")
    if ((cv_equal(subject_24, cv_text("slice")) or cv_equal(subject_24, cv_text("slice_mut")))):
        v_elem = ccs_resolve_type(v_self, cv_subscript(cv_getkey(v_t, "a"), 3), v_indirect)
        if cc_is_owned(v_elem): ccs_error(cv_text("OwnedBuffer нельзя хранить в slice"), v_file, v_t)
        if cv_classes(v_elem, "TSlice") or cv_truth(cc_contains_tagged_type(v_elem)):
            ccs_error(cv_text("slice не может содержать slice или Option/Result или enum с payload"), v_file, v_t)
            return 0
        return cc_TSlice(v_elem, cv_bool((cv_equal(cv_getkey(v_t, "kind"), cv_text("slice_mut")))))
    if (cv_equal(cv_getkey(v_t, "kind"), cv_text("array"))):
        v_elem = ccs_resolve_type(v_self, cv_subscript(cv_getkey(v_t, "a"), 3), v_indirect)
        if cc_is_owned(v_elem): ccs_error(cv_text("OwnedBuffer нельзя хранить в массиве"), v_file, v_t)
        if cv_classes(v_elem, "TSlice"):
            ccs_error(cv_text("slice нельзя хранить в массиве"), v_file, v_t)
            return 0
        if cv_truth(cc_contains_tagged_type(v_elem)):
            ccs_error(cv_text("Option/Result нельзя помещать в массив (как и enum с payload)"), v_file, v_t)
            return 0
        return cc_TArray(v_elem, cv_subscript(cv_getkey(v_t, "a"), 11))
    ccs_error(cv_text("плохой тип"), v_file, v_t)
    return 0

unsafe fn cc_allowed_payload(typ: i64) -> bool:
    if cc_is_owned(typ) or cc_is_owned_ptr(typ): return false
    if cv_classes(typ, "TPtr"):
        return not cv_truth(cc_contains_tagged_type(cv_getkey(typ, "elem")))
    return cv_truth(cc_isscalar(typ)) or cv_classes(typ, "TStruct") or cc_is_tagged_value(typ)

unsafe fn ccs_wrapper_type(v_self: i64, name: i64, args: i64, file: i64, line: i64, indirect: i64) -> i64:
    let owned_ok: bool = (cv_name(name, "Result") or cv_name(name, "Option")) and cc_is_owned_struct(cv_at(args, 0))
    for i in 0..cv_len(args):
        let payload: i64 = cv_at(args, i)
        if owned_ok and i == 0: continue
        if not cc_allowed_payload(payload):
            cc_error(cv_mod(cv_text("%s: недопустимый тип payload %s"), cv_pair(name, cc_display(payload))), file, line)
            return 0
    let typ: i64 = cc_TWrapper(name, args)
    if owned_ok: cv_field(typ, "owned_ok", CV_TRUE)
    if cv_less(cv_i(64), cc_type_depth(typ)):
        cc_error(cv_text("Option/Result: превышена глубина вложенности типов"), file, line)
        return 0
    # In a struct field the type must be rejected before trying to lay it out.
    if not cv_truth(indirect): ccs_wrapper_layout(v_self, typ, file, line)
    return typ

unsafe fn ccs_wrapper_layout(v_self: i64, typ: i64, file: i64, line: i64):
    if cv_getkey(typ, "size") != 0: return
    let args: i64 = cv_getkey(typ, "args")
    for i in 0..cv_len(args):
        let payload: i64 = cv_at(args, i)
        if cv_classes(payload, "TWrapper"):
            ccs_wrapper_layout(v_self, payload, file, line)
        elif cv_classes(payload, "TStruct"):
            ccs_ensure_layout(v_self, payload)
            if not (cc_is_owned_result(typ) and i == 0) and not ccs_copyable_struct_payload(v_self, payload):
                cc_error(cv_text("payload Option/Result требует копируемую struct без slice, BorrowBuffer и OwnedBuffer"), file, line)
    cc_sum_layout(typ, args, file, line)

unsafe fn ccs_copyable_struct_payload(v_self: i64, typ: i64) -> bool:
    if ccs_buffer_module_def(v_self, "struct_defs", cv_text("BorrowBuffer")) and ccs_contains_buffer_owner(v_self, typ): return false
    let pending: i64 = cv_list()
    let seen: i64 = cv_vector(CV_SET)
    cv_push(pending, typ)
    while cv_len(pending) > 0:
        let record: i64 = cv_pop(pending)
        if cv_has(seen, record): continue
        cv_add_set(seen, record)
        let fields: i64 = cv_getkey(record, "fields")
        for i in 0..cv_len(fields):
            let field: i64 = cv_at(cv_at(fields, i), 1)
            while cv_classes(field, "TArray"): field = cv_getkey(field, "elem")
            if cv_classes(field, "TSlice") or cc_is_owned(field): return false
            if cv_classes(field, "TStruct"): cv_push(pending, field)
    return true

unsafe fn ccs_buffer_module_def(v_self: i64, v_table: string, v_name: i64) -> bool:
    let v_def: i64 = cv_get(cv_getkey(v_self, v_table), v_name, 0)
    return v_def != 0 and cv_equal(cv_getkey(v_def, "file"), cv_getkey(v_self, "buffer_borrow_file"))

unsafe fn ccs_buffer_module_body(v_self: i64) -> bool:
    return cv_equal(cv_getkey(cv_getkey(v_self, "fn"), "file"), cv_getkey(v_self, "buffer_borrow_file"))

unsafe fn ccs_buffer_type(v_self: i64, v_type: i64, v_name: string) -> bool:
    return cv_classes(v_type, "TStruct") and cv_name(cv_getkey(v_type, "name"), v_name) and ccs_buffer_module_def(v_self, "struct_defs", cv_text(v_name))

unsafe fn ccs_contains_buffer_owner(v_self: i64, v_type: i64) -> bool:
    let v_defs: i64 = cv_getkey(v_self, "struct_defs")
    let v_pending: i64 = cv_list()
    let v_seen: i64 = cv_vector(CV_SET)
    cv_push(v_pending, cv_pair(v_type, 0))
    while cv_len(v_pending) > 0:
        let v_entry: i64 = cv_pop(v_pending)
        let v_item: i64 = cv_at(v_entry, 0)
        let v_vars: i64 = cv_at(v_entry, 1)
        let v_record: i64 = 0
        let v_parts: i64 = 0
        if cv_classes(v_item, "TExpr"):
            v_parts = cv_getkey(v_item, "a")
            let v_kind: i64 = cv_getkey(v_item, "kind")
            if cv_name(v_kind, "struct_type") or (cv_name(v_kind, "name") and not cv_contains(v_vars, cv_at(v_parts, 0))):
                v_record = cv_at(v_parts, 0)
        elif cv_classes(v_item, "TStruct") or cv_classes(v_item, "TWrapper"):
            if cv_classes(v_item, "TStruct"): v_record = cv_getkey(v_item, "name")
            v_parts = cv_getkey(v_item, "args")
        elif cv_classes(v_item, "TArray") or cv_classes(v_item, "TSlice") or cv_classes(v_item, "TPtr"):
            cv_push(v_pending, cv_pair(cv_getkey(v_item, "elem"), v_vars))
        elif cv_classes(v_item, "TFnPtr"):
            v_parts = cv_getkey(v_item, "params")
            cv_push(v_pending, cv_pair(cv_getkey(v_item, "result"), v_vars))
        elif cv_classes(v_item, "tuple") or cv_classes(v_item, "list"):
            v_parts = v_item
        for i in 0..cv_len(v_parts): cv_push(v_pending, cv_pair(cv_at(v_parts, i), v_vars))
        if v_record == 0 or cv_has(v_seen, v_record): continue
        if cv_name(v_record, "BorrowBuffer"): return true
        cv_add_set(v_seen, v_record)
        # Pointer targets need not have a layout; inspect each declaration once instead.
        let v_def: i64 = cv_get(v_defs, v_record, 0)
        let v_fields: i64 = cv_getkey(v_def, "fields")
        for i in 0..cv_len(v_fields):
            cv_push(v_pending, cv_pair(cv_at(cv_at(v_fields, i), 1), cv_getkey(v_def, "type_params")))
    return false

unsafe fn ccs_check_buffer_cast(v_self: i64, v_a: i64, v_b: i64, v_e: i64):
    if not (cv_classes(v_a, "TPtr") or cv_classes(v_b, "TPtr")) or ccs_buffer_module_body(v_self): return
    if cv_equal(v_a, v_b) or not ccs_buffer_module_def(v_self, "struct_defs", cv_text("BorrowBuffer")): return
    # A literal null does not retype a live handle or its storage.
    if cv_classes(v_b, "TPtr") and cv_classes(v_e, "IntLit") and cv_equal(cv_getkey(v_e, "val"), cv_i(0)): return
    if ccs_contains_buffer_owner(v_self, v_a) or ccs_contains_buffer_owner(v_self, v_b):
        ccs_error(cv_text("представление BorrowBuffer нельзя приводить через raw-указатель"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)

unsafe fn ccs_buffer_view_type_error(v_file: i64, v_line: i64):
    cc_error(cv_text("BufferRead разрешён только как локальное заимствование через let без явной аннотации типа"), v_file, v_line)

unsafe fn ccs_struct_type(v_self: i64, v_name: i64, v_args: i64, v_file: i64, v_line: i64, v_indirect: i64) -> i64:
    let v_sd: i64 = 0
    let v_key: i64 = 0
    let v_typ: i64 = 0
    v_sd = cv_get(cv_getkey(v_self, "struct_defs"), v_name, 0)
    if (v_sd == 0):
        cc_error(cv_cat(cv_text("неизвестная структура "), cv_format(v_name, "")), v_file, v_line)
        return 0
    if cv_name(v_name, "BufferRead") and ccs_buffer_module_def(v_self, "struct_defs", v_name) and not cv_equal(v_file, cv_getkey(v_self, "buffer_borrow_file")):
        ccs_buffer_view_type_error(v_file, v_line)
        return 0
    if (not (cv_equal(cv_length(v_args), cv_length(cv_getkey(v_sd, "type_params"))))):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("struct "))
        cv_push(pieces_1, cv_format(v_name, ""))
        cv_push(pieces_1, cv_text(" требует "))
        cv_push(pieces_1, cv_format(cv_length(cv_getkey(v_sd, "type_params")), ""))
        cv_push(pieces_1, cv_text(" аргумент(ов) типа, получено "))
        cv_push(pieces_1, cv_format(cv_length(v_args), ""))
        cc_error(cv_join(cv_text(""), pieces_1), v_file, v_line)
        return 0
    let collect_2: i64 = cv_vector(CV_LIST)
    let seq_4: i64 = v_args
    for index_3 in 0..cv_len(seq_4):
        let t_5: i64 = cv_at(seq_4, index_3)
        let choice_6: i64 = cv_bool(cv_classes(t_5, "TSlice"))
        if not cv_truth(choice_6):
            choice_6 = cc_contains_tagged_type(t_5)
        cv_push(collect_2, choice_6)
    if cv_truth(cv_any(collect_2)):
        let pieces_7: i64 = cv_list()
        cv_push(pieces_7, cv_text("struct "))
        cv_push(pieces_7, cv_format(v_name, ""))
        cv_push(pieces_7, cv_text(": параметры типа не поддерживают slice или Option/Result или enum с payload"))
        cc_error(cv_join(cv_text(""), pieces_7), v_file, v_line)
        return 0
    v_key = cv_pair(v_name, v_args)
    v_typ = cv_get(cv_getkey(v_self, "types_structs"), v_key, 0)
    if (v_typ == 0):
        v_typ = cc_TStruct(v_name, v_args)
        let v_kind: i64 = cc_owner_kind_of_def(v_self, v_sd)
        if v_kind != 0:
            cv_field(v_typ, "owner_kind", v_kind)
            cv_field(v_typ, "opaque_file", cv_getkey(v_sd, "file"))
            cv_field(v_self, "has_owned", CV_TRUE)
        if cv_truth(cv_getkey(v_sd, "opaque")):
            cv_field(v_typ, "opaque_file", cv_getkey(v_sd, "file"))
            cv_field(v_typ, "source_name", cv_getkey(v_sd, "source_name"))
        if (cv_less(515, cv_getkey(v_typ, "type_depth"))):
            let pieces_8: i64 = cv_list()
            cv_push(pieces_8, cv_text("struct "))
            cv_push(pieces_8, cv_format(v_name, ""))
            cv_push(pieces_8, cv_text(": превышена глубина вложенности аргументов типа"))
            cc_error(cv_join(cv_text(""), pieces_8), v_file, v_line)
            return 0
        if cv_truth(v_args):
            if (cv_le(32771, cv_getkey(v_self, "generic_struct_count"))):
                cc_error(cv_text("слишком много специализаций generic-структур"), v_file, v_line)
                return 0
            cv_field(v_self, "generic_struct_count", cv_add(cv_getkey(v_self, "generic_struct_count"), 11))
        cv_set(cv_getkey(v_self, "types_structs"), v_key, v_typ)
    if not (cv_truth(v_indirect)):
        ccs_ensure_layout(v_self, v_typ)
    return v_typ

unsafe fn ccs_ensure_layout(v_self: i64, v_typ: i64) -> i64:
    let v_pending: i64 = 0
    let v_active: i64 = 0
    let v_record: i64 = 0
    let v_resolved: i64 = 0
    let v_sd: i64 = 0
    let v_variables: i64 = 0
    let v_field: i64 = 0
    let v_offset: i64 = 0
    let v_alignment: i64 = 0
    let v_fields: i64 = 0
    let v_name: i64 = 0
    let v_field_align: i64 = 0
    let v_size: i64 = 0
    let items_1: i64 = cv_vector(CV_LIST)
    cv_push(items_1, cv_pair(v_typ, 0))
    v_pending = items_1
    v_active = cv_vector(CV_SET)
    while cv_truth(v_pending):
        let unpack_2: i64 = cv_pop(v_pending)
        v_record = cv_at(unpack_2, 0)
        v_resolved = cv_at(unpack_2, 1)
        while cv_truth(cc_is_array(v_record)):
            v_record = cv_getkey(v_record, "elem")
        if (not (cv_truth(cc_is_struct(v_record))) or (not (cv_getkey(v_record, "size") == 0))):
            continue
        v_sd = cv_subscript(cv_getkey(v_self, "struct_defs"), cv_getkey(v_record, "name"))
        if (v_resolved == 0):
            if (cv_contains(v_active, v_record)):
                let pieces_3: i64 = cv_list()
                cv_push(pieces_3, cv_text("struct "))
                cv_push(pieces_3, cv_format(cc_display(v_record), ""))
                cv_push(pieces_3, cv_text(": бесконечная рекурсия по значению"))
                ccs_error(cv_join(cv_text(""), pieces_3), cv_getkey(v_sd, "file"), v_sd)
                return 0
            cv_add_set(v_active, v_record)
            v_variables = cv_asdict(cv_zip(cv_getkey(v_sd, "type_params"), cv_getkey(v_record, "args")))
            let collect_4: i64 = cv_vector(CV_LIST)
            let seq_6: i64 = cv_getkey(v_sd, "fields")
            for index_5 in 0..cv_len(seq_6):
                let unpack_7: i64 = cv_at(seq_6, index_5)
                let name_8: i64 = cv_at(unpack_7, 0)
                let field_9: i64 = cv_at(unpack_7, 1)
                cv_push(collect_4, cv_pair(name_8, ccs_generic_type(v_self, field_9, v_variables, CV_TRUE)))
            v_resolved = collect_4
            let seq_11: i64 = v_resolved
            for index_10 in 0..cv_len(seq_11):
                let unpack_12: i64 = cv_at(seq_11, index_10)
                v_field = cv_at(unpack_12, 1)
                if cc_is_owned(v_field) or cc_is_owned_ptr(v_field):
                    ccs_error(cv_text("OwnedBuffer нельзя хранить в struct"), cv_getkey(v_sd, "file"), v_sd)
                if cv_classes(v_field, "TSlice"):
                    ccs_error(cv_text("slice нельзя хранить в struct"), cv_getkey(v_sd, "file"), v_sd)
                    return 0
                if cv_truth(cc_contains_tagged_type(v_field)):
                    ccs_error(cv_text("Option/Result нельзя помещать в поля struct или скрывать за ptr (как и enum с payload)"), cv_getkey(v_sd, "file"), v_sd)
                    return 0
            cv_push(v_pending, cv_pair(v_record, v_resolved))
            let collect_13: i64 = cv_vector(CV_LIST)
            let seq_15: i64 = cv_reverse(v_resolved)
            for index_14 in 0..cv_len(seq_15):
                let unpack_16: i64 = cv_at(seq_15, index_14)
                let field_17: i64 = cv_at(unpack_16, 1)
                cv_push(collect_13, cv_pair(field_17, 0))
            cv_extend(v_pending, collect_13)
            continue
        v_offset = 3
        v_alignment = 11
        let items_18: i64 = cv_vector(CV_LIST)
        v_fields = items_18
        let seq_20: i64 = v_resolved
        for index_19 in 0..cv_len(seq_20):
            let unpack_21: i64 = cv_at(seq_20, index_19)
            v_name = cv_at(unpack_21, 0)
            v_field = cv_at(unpack_21, 1)
            v_field_align = cc_type_align(v_field)
            v_offset = cc_base_align(v_offset, v_field_align)
            v_size = cc_type_size(v_field)
            let items_22: i64 = cv_vector(CV_TUPLE)
            cv_push(items_22, v_name)
            cv_push(items_22, v_field)
            cv_push(items_22, v_offset)
            cv_push(items_22, v_size)
            cv_push(v_fields, items_22)
            v_offset = cv_add(v_offset, v_size)
            v_alignment = cv_max(v_alignment, v_field_align)
        v_size = cc_base_align(cv_max(v_offset, 11), v_alignment)
        if cv_truth(cv_getkey(v_sd, "c_layout")):
            ccs_c_record_layout(v_record, v_sd, v_fields, v_size)
        if (cv_less(17179869179, v_size)):
            let pieces_23: i64 = cv_list()
            cv_push(pieces_23, cv_text("struct "))
            cv_push(pieces_23, cv_format(cv_getkey(v_sd, "name"), ""))
            cv_push(pieces_23, cv_text(": размер структуры превышает лимит x86-64"))
            ccs_error(cv_join(cv_text(""), pieces_23), cv_getkey(v_sd, "file"), v_sd)
            return 0
        let items_24: i64 = cv_vector(CV_TUPLE)
        cv_push(items_24, v_fields)
        cv_push(items_24, v_size)
        cv_push(items_24, v_alignment)
        let unpack_25: i64 = items_24
        cv_field(v_record, "fields", cv_at(unpack_25, 0))
        cv_field(v_record, "size", cv_at(unpack_25, 1))
        cv_field(v_record, "align", cv_at(unpack_25, 2))
        cv_remove(v_active, v_record)
    return 0

unsafe fn ccs_c_record_layout(record: i64, def: i64, fields: i64, size: i64):
    let file: i64 = cv_getkey(def, "file")
    let line: i64 = cv_getkey(def, "line")
    if cv_less(cv_i(16), size):
        cc_error(cv_text("extern struct поддерживает размер до 16 байт"), file, line)
    let integer: i64 = 0
    let sse: i64 = 0
    for i in 0..cv_len(fields):
        let field: i64 = cv_at(fields, i)
        let typ: i64 = cv_at(field, 1)
        let bit: i64 = 1 << (cv_index(cv_at(field, 2)) / 8)
        if cv_truth(cc_is_float(typ)):
            sse |= bit
        elif cv_truth(cc_compatible(typ)) and not cv_classes(typ, "TEnum"):
            integer |= bit
        else:
            cc_error(cv_text("extern struct требует скалярные поля C ABI"), file, line)
    # INTEGER overrides SSE when both share an eightbyte.
    cv_field(record, "c_abi", cv_i(sse & (3 ^ integer)))

unsafe fn ccs_layout_tagged_enums(v_self: i64, defs: i64):
    for i in 0..cv_len(defs):
        let def: i64 = cv_at(defs, i)
        let typ: i64 = cv_get(cv_getkey(v_self, "enums"), cv_getkey(def, "name"), 0)
        if not cv_classes(typ, "TTaggedEnum"): continue
        let payloads: i64 = cv_getkey(typ, "payloads")
        for j in 0..cv_len(payloads):
            let member: i64 = cv_at(payloads, j)
            let node: i64 = cv_get(payloads, member, 0)
            let payload: i64 = ccs_resolve_type(v_self, node, CV_TRUE)
            if not cv_truth(cc_isscalar(payload)) or cv_classes(payload, "TPtr"):
                cc_error(cv_text("enum с payload поддерживает только скалярное значение без raw-указателей"), cv_getkey(def, "file"), cv_getkey(node, "line"))
            cv_set(payloads, member, payload)
        cc_sum_layout(typ, cv_values(payloads), cv_getkey(def, "file"), cv_getkey(def, "line"))

unsafe fn ccs_collect(v_self: i64) -> i64:
    ccs_register_namespaces(v_self)
    let v_prog: i64 = 0
    let v_is_entry: i64 = 0
    let v_sd: i64 = 0
    let v_ed: i64 = 0
    let v_collisions: i64 = 0
    let v_name: i64 = 0
    let v_values: i64 = 0
    let v_seen_values: i64 = 0
    let v_variant: i64 = 0
    let v_value: i64 = 0
    let v_fn: i64 = 0
    let v_pn: i64 = 0
    let v_pt: i64 = 0
    let v_resolved: i64 = 0
    let v_u: i64 = 0
    let v_st: i64 = 0
    let v_dummy: i64 = 0
    let v_init_t: i64 = 0
    let v_want: i64 = 0
    let v_val: i64 = 0
    let v_lo: i64 = 0
    let v_hi: i64 = 0
    let v_init_calls: i64 = 0
    let seq_2: i64 = cv_getkey(v_self, "progs")
    for index_1 in 0..cv_len(seq_2):
        v_prog = cv_at(seq_2, index_1)
        v_is_entry = cv_bool((cv_equal(cv_getkey(v_prog, "file"), cv_getkey(v_self, "entry_name"))))
        cv_field(v_prog, "is_entry", v_is_entry)
        let seq_4: i64 = cv_getkey(v_prog, "structs")
        for index_3 in 0..cv_len(seq_4):
            v_sd = cv_at(seq_4, index_3)
            if cv_truth(cv_getkey(v_sd, "c_layout")) and cv_truth(cv_getkey(v_sd, "type_params")):
                ccs_error(cv_text("extern struct не поддерживает параметры типа"), cv_getkey(v_sd, "file"), v_sd)
            if (cv_contains(cv_getkey(v_self, "struct_defs"), cv_getkey(v_sd, "name"))):
                let pieces_5: i64 = cv_list()
                cv_push(pieces_5, cv_text("struct "))
                cv_push(pieces_5, cv_format(cv_getkey(v_sd, "name"), ""))
                cv_push(pieces_5, cv_text(" определён дважды"))
                ccs_error(cv_join(cv_text(""), pieces_5), cv_getkey(v_sd, "file"), v_sd)
                return 0
            let original: i64 = cv_get(v_sd, cv_text("source_name"), cv_getkey(v_sd, "name"))
            let logic_7: bool = (cv_contains(cc_k_scalar_type_names, original))
            if not logic_7:
                let subject_6: i64 = original
                logic_7 = ((cv_equal(subject_6, cv_text("Option")) or cv_equal(subject_6, cv_text("Result")) or cv_equal(subject_6, cv_text("ptr"))))
            if (logic_7):
                let pieces_8: i64 = cv_list()
                cv_push(pieces_8, cv_text("имя "))
                cv_push(pieces_8, cv_format(cv_getkey(v_sd, "name"), ""))
                cv_push(pieces_8, cv_text(" зарезервировано для встроенного типа"))
                ccs_error(cv_join(cv_text(""), pieces_8), cv_getkey(v_sd, "file"), v_sd)
                return 0
            cv_set(cv_getkey(v_self, "struct_defs"), cv_getkey(v_sd, "name"), v_sd)
        let seq_10: i64 = cv_getkey(v_prog, "enums")
        for index_9 in 0..cv_len(seq_10):
            v_ed = cv_at(seq_10, index_9)
            if (cv_contains(cv_getkey(v_self, "enum_defs"), cv_getkey(v_ed, "name"))):
                let pieces_11: i64 = cv_list()
                cv_push(pieces_11, cv_text("enum "))
                cv_push(pieces_11, cv_format(cv_getkey(v_ed, "name"), ""))
                cv_push(pieces_11, cv_text(" определён дважды"))
                ccs_error(cv_join(cv_text(""), pieces_11), cv_getkey(v_ed, "file"), v_ed)
                return 0
            cv_set(cv_getkey(v_self, "enum_defs"), cv_getkey(v_ed, "name"), v_ed)
    v_collisions = cv_and(cv_asset(cv_getkey(v_self, "struct_defs")), cv_asset(cv_getkey(v_self, "enum_defs")))
    if cv_truth(v_collisions):
        v_name = cv_subscript(cv_sorted(v_collisions), 3)
        v_ed = cv_subscript(cv_getkey(v_self, "enum_defs"), v_name)
        let pieces_12: i64 = cv_list()
        cv_push(pieces_12, cv_text("имя "))
        cv_push(pieces_12, cv_format(v_name, ""))
        cv_push(pieces_12, cv_text(" используется и для struct, и для enum"))
        ccs_error(cv_join(cv_text(""), pieces_12), cv_getkey(v_ed, "file"), v_ed)
        return 0
    let seq_14: i64 = cv_items(cv_getkey(v_self, "enum_defs"))
    for index_13 in 0..cv_len(seq_14):
        let unpack_15: i64 = cv_at(seq_14, index_13)
        v_name = cv_at(unpack_15, 0)
        v_ed = cv_at(unpack_15, 1)
        v_values = cv_dict()
        let payloads: i64 = cv_dict()
        v_seen_values = cv_vector(CV_SET)
        let seq_17: i64 = cv_getkey(v_ed, "variants")
        for index_16 in 0..cv_len(seq_17):
            let unpack_18: i64 = cv_at(seq_17, index_16)
            v_variant = cv_at(unpack_18, 0)
            v_value = cv_at(unpack_18, 1)
            if (cv_contains(v_seen_values, v_value)):
                let pieces_19: i64 = cv_list()
                cv_push(pieces_19, cv_text("enum "))
                cv_push(pieces_19, cv_format(v_name, ""))
                cv_push(pieces_19, cv_text(": повторный discriminant "))
                cv_push(pieces_19, cv_format(v_value, ""))
                ccs_error(cv_join(cv_text(""), pieces_19), cv_getkey(v_ed, "file"), v_ed)
                return 0
            cv_add_set(v_seen_values, v_value)
            if (cv_contains(v_values, v_variant)):
                let pieces_20: i64 = cv_list()
                cv_push(pieces_20, cv_text("enum "))
                cv_push(pieces_20, cv_format(v_name, ""))
                cv_push(pieces_20, cv_text(": вариант "))
                cv_push(pieces_20, cv_format(v_variant, ""))
                cv_push(pieces_20, cv_text(" определён дважды"))
                ccs_error(cv_join(cv_text(""), pieces_20), cv_getkey(v_ed, "file"), v_ed)
                return 0
            cv_set(v_values, v_variant, v_value)
            let payload: i64 = cv_at(unpack_18, 2)
            if payload != 0: cv_set(payloads, v_variant, payload)
        if cv_len(payloads) == 0:
            cv_set(cv_getkey(v_self, "enums"), v_name, cc_TEnum(v_name, v_values))
        else:
            cv_set(cv_getkey(v_self, "enums"), v_name, cc_TTaggedEnum(v_name, v_values, payloads))
    ccs_layout_tagged_enums(v_self, cv_values(cv_getkey(v_self, "enum_defs")))
    let seq_22: i64 = cv_values(cv_getkey(v_self, "struct_defs"))
    for index_21 in 0..cv_len(seq_22):
        v_sd = cv_at(seq_22, index_21)
        if not (cv_truth(cv_getkey(v_sd, "type_params"))):
            let items_23: i64 = cv_vector(CV_TUPLE)
            ccs_struct_type(v_self, cv_getkey(v_sd, "name"), items_23, cv_getkey(v_sd, "file"), cv_getkey(v_sd, "line"), CV_FALSE)
    let seq_25: i64 = cv_getkey(v_self, "progs")
    for index_24 in 0..cv_len(seq_25):
        v_prog = cv_at(seq_25, index_24)
        let seq_27: i64 = cv_getkey(v_prog, "fns")
        for index_26 in 0..cv_len(seq_27):
            v_fn = cv_at(seq_27, index_26)
            if cv_truth(cv_getkey(v_fn, "type_params")):
                continue
            if (cv_contains(cv_getkey(v_self, "fns"), cv_getkey(v_fn, "name"))):
                ccs_error(cv_cat(cv_text("дубликат функции "), cv_format(cv_getkey(v_fn, "name"), "")), cv_getkey(v_fn, "file"), v_fn)
                return 0
            cv_set(cv_getkey(v_self, "fns"), cv_getkey(v_fn, "name"), v_fn)
            if ((cv_equal(cv_getkey(v_fn, "name"), cv_text("Option"))) or (cv_equal(cv_getkey(v_fn, "name"), cv_text("Result")))):
                let pieces_28: i64 = cv_list()
                cv_push(pieces_28, cv_text("имя "))
                cv_push(pieces_28, cv_format(cv_getkey(v_fn, "name"), ""))
                cv_push(pieces_28, cv_text(" зарезервировано встроенным wrapper-типом"))
                ccs_error(cv_join(cv_text(""), pieces_28), cv_getkey(v_fn, "file"), v_fn)
                return 0
            let items_29: i64 = cv_vector(CV_LIST)
            cv_field(v_fn, "sig_params", items_29)
            let seq_31: i64 = cv_getkey(v_fn, "params")
            for index_30 in 0..cv_len(seq_31):
                let unpack_32: i64 = cv_at(seq_31, index_30)
                v_pn = cv_at(unpack_32, 0)
                v_pt = cv_at(unpack_32, 1)
                v_resolved = ccs_resolve_type(v_self, v_pt, CV_FALSE)
                if (cv_classes(v_resolved, "TSlice") and ((not (cv_getkey(v_fn, "native") == 0)) or (cv_getkey(v_fn, "body") == 0))):
                    ccs_error(cv_text("slice не поддерживается в native/extern ABI"), cv_getkey(v_fn, "file"), v_fn)
                    return 0
                if (cv_classes(v_resolved, "TWrapper") and ((not (cv_getkey(v_fn, "native") == 0)) or (cv_getkey(v_fn, "body") == 0))):
                    ccs_error(cv_text("Option/Result параметры запрещены в extern/native"), cv_getkey(v_fn, "file"), v_fn)
                    return 0
                if cv_classes(v_resolved, "TTaggedEnum") and (cv_getkey(v_fn, "native") != 0 or cv_getkey(v_fn, "body") == 0):
                    ccs_error(cv_text("enum с payload запрещён в extern/native ABI"), cv_getkey(v_fn, "file"), v_fn)
                    return 0
                cv_push(cv_getkey(v_fn, "sig_params"), cv_pair(v_pn, v_resolved))
            let choice_33: i64 = 0
            if (not (cv_getkey(v_fn, "ret") == 0)):
                choice_33 = ccs_resolve_type(v_self, cv_getkey(v_fn, "ret"), CV_FALSE)
            else:
                choice_33 = 0
            cv_field(v_fn, "sig_ret", choice_33)
            if (cv_classes(cv_getkey(v_fn, "sig_ret"), "TSlice") and ((not (cv_getkey(v_fn, "native") == 0)) or (cv_getkey(v_fn, "body") == 0))):
                ccs_error(cv_text("slice не поддерживается в native/extern ABI"), cv_getkey(v_fn, "file"), v_fn)
                return 0
            if (cv_classes(cv_getkey(v_fn, "sig_ret"), "TWrapper") and ((not (cv_getkey(v_fn, "native") == 0)) or (cv_getkey(v_fn, "body") == 0))):
                ccs_error(cv_text("Option/Result результаты запрещены в extern/native"), cv_getkey(v_fn, "file"), v_fn)
                return 0
            if cv_classes(cv_getkey(v_fn, "sig_ret"), "TTaggedEnum") and (cv_getkey(v_fn, "native") != 0 or cv_getkey(v_fn, "body") == 0):
                ccs_error(cv_text("enum с payload запрещён в extern/native ABI"), cv_getkey(v_fn, "file"), v_fn)
                return 0
            ccs_check_fn_abi(v_self, v_fn)
        let seq_35: i64 = cv_getkey(v_prog, "uses")
        for index_34 in 0..cv_len(seq_35):
            v_u = cv_at(seq_35, index_34)
            if cv_truth(cv_bool(cv_starts(v_u, cv_text("__link__:")))):
                cv_push(cv_getkey(v_self, "links"), cv_subscript(cv_split(v_u, cv_text(":"), 11), 11))
    let seq_37: i64 = cv_getkey(v_self, "progs")
    for index_36 in 0..cv_len(seq_37):
        v_prog = cv_at(seq_37, index_36)
        let seq_39: i64 = cv_getkey(v_prog, "fns")
        for index_38 in 0..cv_len(seq_39):
            v_fn = cv_at(seq_39, index_38)
            if cv_truth(cv_getkey(v_fn, "type_params")):
                if ((cv_contains(cv_getkey(v_self, "generic_fns"), cv_getkey(v_fn, "name"))) or (cv_contains(cv_getkey(v_self, "fns"), cv_getkey(v_fn, "name")))):
                    ccs_error(cv_cat(cv_text("дубликат функции "), cv_format(cv_getkey(v_fn, "name"), "")), cv_getkey(v_fn, "file"), v_fn)
                    return 0
                if ((not (cv_getkey(v_fn, "native") == 0)) or (cv_getkey(v_fn, "body") == 0)):
                    ccs_error(cv_text("generic-функции пока не поддерживают native/extern ABI"), cv_getkey(v_fn, "file"), v_fn)
                    return 0
                cv_set(cv_getkey(v_self, "generic_fns"), cv_getkey(v_fn, "name"), v_fn)
    let seq_41: i64 = cv_getkey(v_self, "progs")
    for index_40 in 0..cv_len(seq_41):
        v_prog = cv_at(seq_41, index_40)
        let seq_43: i64 = cv_getkey(v_prog, "main")
        for index_42 in 0..cv_len(seq_43):
            v_st = cv_at(seq_43, index_42)
            if cv_classes(v_st, "ConstStmt"):
                if ((cv_contains(cv_getkey(v_self, "const_globals"), cv_getkey(v_st, "name"))) or (cv_contains(cv_getkey(v_self, "globals"), cv_getkey(v_st, "name")))):
                    let pieces_44: i64 = cv_list()
                    cv_push(pieces_44, cv_text("имя "))
                    cv_push(pieces_44, cv_format(cv_getkey(v_st, "name"), ""))
                    cv_push(pieces_44, cv_text(" объявлено дважды"))
                    ccs_error(cv_join(cv_text(""), pieces_44), cv_getkey(v_prog, "file"), v_st)
                    return 0
                let kindof_45: i64 = cv_getkey(v_st, "init")
                if not (cv_classes(kindof_45, "IntLit") or cv_classes(kindof_45, "FloatLit") or cv_classes(kindof_45, "StrLit") or cv_classes(kindof_45, "CharLit") or cv_classes(kindof_45, "BoolLit") or cv_classes(kindof_45, "Unary") or cv_classes(kindof_45, "Binary") or cv_classes(kindof_45, "Cast") or cv_classes(kindof_45, "Member") or cv_classes(kindof_45, "SizeAlignExpr") or cv_classes(kindof_45, "VarRef")):
                    ccs_error(cv_text("const требует константное выражение"), cv_getkey(v_prog, "file"), v_st)
                    return 0
                let items_46: i64 = cv_vector(CV_LIST)
                let items_47: i64 = cv_vector(CV_LIST)
                let extra_48: i64 = cv_tuple()
                cv_push(extra_48, 0)
                cv_push(extra_48, cv_getkey(v_st, "line"))
                cv_push(extra_48, CV_FALSE)
                cv_push(extra_48, 0)
                v_dummy = cc_FnDef(cv_getkey(v_prog, "file"), cv_text("<const>"), items_46, 0, items_47, extra_48)
                ccs_setup_fn(v_self, v_dummy)
                v_init_t = ccs_tf(v_self, cv_getkey(v_st, "init"), 0)
                let choice_49: i64 = 0
                if (not (cv_getkey(v_st, "typ") == 0)):
                    choice_49 = ccs_resolve_type(v_self, cv_getkey(v_st, "typ"), CV_FALSE)
                else:
                    choice_49 = v_init_t
                v_want = choice_49
                if ((not (cv_equal(v_want, v_init_t))) and not (cv_truth(cc_can_assign(v_init_t, v_want)))):
                    let pieces_50: i64 = cv_list()
                    cv_push(pieces_50, cv_text("const "))
                    cv_push(pieces_50, cv_format(cv_getkey(v_st, "name"), ""))
                    cv_push(pieces_50, cv_text(": "))
                    cv_push(pieces_50, cv_format(cc_display(v_init_t), ""))
                    cv_push(pieces_50, cv_text(" нельзя присвоить "))
                    cv_push(pieces_50, cv_format(cc_display(v_want), ""))
                    ccs_error(cv_join(cv_text(""), pieces_50), cv_getkey(v_prog, "file"), v_st)
                    return 0
                if (cv_truth(cc_is_array(v_want)) or cv_truth(cc_is_struct(v_want)) or cv_truth(cc_is_ptr(v_want)) or cv_truth(cc_is_string(v_want)) or cv_classes(v_want, "TFnPtr") or cv_classes(v_want, "TTaggedEnum")):
                    ccs_error(cv_text("const поддерживает только скалярные типы"), cv_getkey(v_prog, "file"), v_st)
                    return 0
                if (cv_classes(cv_getkey(v_st, "init"), "VarRef") and not cv_has(cv_getkey(v_st, "init"), cv_text("const_binding"))):
                    ccs_error(cv_cat(cv_text("неизвестное имя "), cv_format(cv_getkey(cv_getkey(v_st, "init"), "name"), "r")), cv_getkey(v_prog, "file"), v_st)
                    return 0
                v_val = ccs_fold_const(v_self, cv_getkey(v_st, "init"))
                if cv_truth(cc_is_int(v_want)):
                    v_val = cv_int(v_val, 83)
                    let unpack_51: i64 = cc_int_bounds(v_want)
                    v_lo = cv_at(unpack_51, 0)
                    v_hi = cv_at(unpack_51, 1)
                    if ((cv_less(v_val, v_lo)) or (cv_less(v_hi, v_val))):
                        ccs_error(cv_text("целочисленное переполнение в const"), cv_getkey(v_prog, "file"), v_st)
                        return 0
                else:
                    if cv_truth(cc_is_float(v_want)):
                        let choice_52: i64 = 0
                        if (cv_equal(cv_getkey(v_want, "bits"), 259)):
                            choice_52 = cv_round32(v_val)
                        else:
                            choice_52 = cv_f(v_val)
                        v_val = choice_52
                cv_set(cv_getkey(v_self, "const_globals"), cv_getkey(v_st, "name"), cv_pair(v_want, v_val))
                let unpack_53: i64 = cv_subscript(cv_getkey(v_self, "const_globals"), cv_getkey(v_st, "name"))
                cv_field(v_st, "const_type", cv_at(unpack_53, 0))
                cv_field(v_st, "const_value", cv_at(unpack_53, 1))
    let seq_55: i64 = cv_getkey(v_self, "progs")
    for index_54 in 0..cv_len(seq_55):
        v_prog = cv_at(seq_55, index_54)
        if (not (cv_equal(cv_getkey(v_prog, "file"), cv_getkey(v_self, "entry_name")))):
            let items_56: i64 = cv_vector(CV_LIST)
            v_init_calls = items_56
            let seq_58: i64 = cv_getkey(v_prog, "main")
            for index_57 in 0..cv_len(seq_58):
                v_st = cv_at(seq_58, index_57)
                if cv_classes(v_st, "LetStmt"):
                    let logic_60: bool = (cv_getkey(v_st, "init") == 0)
                    if not logic_60:
                        let kindof_59: i64 = cv_getkey(v_st, "init")
                        logic_60 = not (cv_classes(kindof_59, "IntLit") or cv_classes(kindof_59, "FloatLit") or cv_classes(kindof_59, "StrLit") or cv_classes(kindof_59, "CharLit") or cv_classes(kindof_59, "BoolLit") or cv_classes(kindof_59, "Unary") or cv_classes(kindof_59, "Binary") or cv_classes(kindof_59, "Cast") or cv_classes(kindof_59, "Member"))
                    if (logic_60):
                        ccs_error(cv_text("глобальная let в модуле требует константу"), cv_getkey(v_prog, "file"), v_st)
                        return 0
                    let items_61: i64 = cv_vector(CV_LIST)
                    let items_62: i64 = cv_vector(CV_LIST)
                    let extra_63: i64 = cv_tuple()
                    cv_push(extra_63, 0)
                    cv_push(extra_63, cv_getkey(v_st, "line"))
                    cv_push(extra_63, CV_FALSE)
                    cv_push(extra_63, 0)
                    v_dummy = cc_FnDef(cv_getkey(v_prog, "file"), cv_text("<global>"), items_61, 0, items_62, extra_63)
                    ccs_setup_fn(v_self, v_dummy)
                    v_init_t = ccs_tf(v_self, cv_getkey(v_st, "init"), 0)
                    if cv_classes(v_init_t, "TWrapper"):
                        ccs_error(cv_text("Option/Result нельзя использовать в global/const"), cv_getkey(v_prog, "file"), v_st)
                        return 0
                    if (cv_truth(cc_is_array(v_init_t)) or cv_truth(cc_is_struct(v_init_t)) or cv_classes(v_init_t, "TTaggedEnum")):
                        ccs_error(cv_text("глобальная let должна иметь скалярный тип"), cv_getkey(v_prog, "file"), v_st)
                        return 0
                    let choice_64: i64 = 0
                    if (not (cv_getkey(v_st, "typ") == 0)):
                        choice_64 = ccs_resolve_type(v_self, cv_getkey(v_st, "typ"), CV_FALSE)
                    else:
                        choice_64 = 0
                    v_want = choice_64
                    if ((not (v_want == 0)) and not (cv_truth(cc_can_assign(v_init_t, v_want)))):
                        let pieces_65: i64 = cv_list()
                        cv_push(pieces_65, cv_text("глобальная "))
                        cv_push(pieces_65, cv_format(cv_getkey(v_st, "name"), ""))
                        cv_push(pieces_65, cv_text(": "))
                        cv_push(pieces_65, cv_format(cc_display(v_init_t), ""))
                        cv_push(pieces_65, cv_text(" нельзя присвоить "))
                        cv_push(pieces_65, cv_format(cc_display(v_want), ""))
                        ccs_error(cv_join(cv_text(""), pieces_65), cv_getkey(v_prog, "file"), v_st)
                        return 0
                    let choice_66: i64 = 0
                    if (not (v_want == 0)):
                        choice_66 = v_want
                    else:
                        choice_66 = v_init_t
                    cv_field(v_st, "glob_type", choice_66)
                    cv_field(v_st, "const_val", ccs_fold_const(v_self, cv_getkey(v_st, "init")))
                    if cv_truth(cc_is_float(cv_getkey(v_st, "glob_type"))):
                        let choice_67: i64 = 0
                        if (cv_equal(cv_getkey(cv_getkey(v_st, "glob_type"), "bits"), 259)):
                            choice_67 = cv_round32(cv_getkey(v_st, "const_val"))
                        else:
                            choice_67 = cv_f(cv_getkey(v_st, "const_val"))
                        cv_field(v_st, "const_val", choice_67)
                    else:
                        if cv_truth(cc_is_int(cv_getkey(v_st, "glob_type"))):
                            cv_field(v_st, "const_val", cv_int(cv_getkey(v_st, "const_val"), 83))
                            let unpack_68: i64 = cc_int_bounds(cv_getkey(v_st, "glob_type"))
                            v_lo = cv_at(unpack_68, 0)
                            v_hi = cv_at(unpack_68, 1)
                            if ((cv_less(cv_getkey(v_st, "const_val"), v_lo)) or (cv_less(v_hi, cv_getkey(v_st, "const_val")))):
                                ccs_error(cv_text("целочисленное переполнение в глобальной константе"), cv_getkey(v_prog, "file"), v_st)
                                return 0
                    cv_field(v_st, "file", cv_getkey(v_prog, "file"))
                    cv_field(v_st, "name_hdr", cv_getkey(v_st, "name"))
                    cv_set(cv_getkey(v_self, "globals"), cv_getkey(v_st, "name"), v_st)
                    cv_push(cv_getkey(v_self, "global_order"), v_st)
                    continue
                else:
                    if cv_classes(v_st, "ConstStmt"):
                        continue
                    else:
                        if (cv_classes(v_st, "ExprStmt") and cv_classes(cv_getkey(v_st, "expr"), "Call")):
                            cv_push(v_init_calls, v_st)
                            continue
                        else:
                            let pieces_69: i64 = cv_list()
                            cv_push(pieces_69, cv_text("в модуле разрешены const-let и вызовы инициализации (строка "))
                            cv_push(pieces_69, cv_format(cv_getkey(v_st, "line"), ""))
                            cv_push(pieces_69, cv_text(")"))
                            ccs_error(cv_join(cv_text(""), pieces_69), cv_getkey(v_prog, "file"), v_st)
                            return 0
            let items_70: i64 = cv_vector(CV_LIST)
            cv_field(v_prog, "main", items_70)
            if cv_getkey(v_self, "namespaced_code") != 0 and cv_len(v_init_calls) != 0:
                let init_name: i64 = cv_mod(cv_text("$init$%d"), cv_i(index_54))
                let args: i64 = cv_list()
                let extra: i64 = cv_tuple()
                cv_push(extra, 0)
                cv_push(extra, cv_getkey(cv_at(v_init_calls, 0), "line"))
                cv_push(extra, CV_FALSE)
                cv_push(extra, 0)
                let init: i64 = cc_FnDef(cv_getkey(v_prog, "file"), init_name, args, 0, v_init_calls, extra)
                cv_field(init, "sig_params", args)
                cv_set(cv_getkey(v_self, "fns"), init_name, init)
                cv_push(cv_getkey(v_prog, "fns"), init)
                v_init_calls = cv_list()
                cv_push(v_init_calls, cc_ExprStmt(cc_Call(init_name, args, cv_getkey(init, "line")), cv_getkey(init, "line")))
            cv_field(v_prog, "init_calls", v_init_calls)
    return 0

unsafe fn ccs_check_fn_abi(v_self: i64, v_fn: i64) -> i64:
    ccs_check_slice_return_signature(v_fn)
    let v_params: i64 = 0
    let v_foreign: i64 = 0
    let collect_1: i64 = cv_vector(CV_LIST)
    let seq_3: i64 = cv_getkey(v_fn, "sig_params")
    for index_2 in 0..cv_len(seq_3):
        let unpack_4: i64 = cv_at(seq_3, index_2)
        let pt_5: i64 = cv_at(unpack_4, 1)
        cv_push(collect_1, pt_5)
    v_params = collect_1
    let choice_6: i64 = cv_bool((not (cv_getkey(v_fn, "native") == 0)))
    if not cv_truth(choice_6):
        choice_6 = cv_bool((cv_getkey(v_fn, "body") == 0))
    v_foreign = choice_6
    let collect_7: i64 = cv_vector(CV_LIST)
    let seq_9: i64 = v_params
    for index_8 in 0..cv_len(seq_9):
        let t_10: i64 = cv_at(seq_9, index_8)
        cv_push(collect_7, cc_is_array(t_10))
    if cv_truth(cv_any(collect_7)):
        ccs_error(cv_text("массив нельзя передавать по значению: используйте slice или ptr"), cv_getkey(v_fn, "file"), v_fn)
        return 0
    if cv_truth(cc_is_array(cv_getkey(v_fn, "sig_ret"))):
        ccs_error(cv_text("функции не могут возвращать массивы: возвращайте ptr"), cv_getkey(v_fn, "file"), v_fn)
        return 0
    if cv_truth(v_foreign):
        let raw: bool = cv_getkey(v_fn, "native") != 0
        for i in 0..cv_len(v_params):
            let typ: i64 = cv_at(v_params, i)
            if cv_classes(typ, "TStruct") and (raw or cv_getkey(typ, "c_abi") == 0):
                ccs_error(cv_text("структуры по значению требуют extern struct и extern fn"), cv_getkey(v_fn, "file"), v_fn)
        let result: i64 = cv_getkey(v_fn, "sig_ret")
        if cv_classes(result, "TStruct") and (raw or cv_getkey(result, "c_abi") == 0):
            ccs_error(cv_text("возврат struct запрещён в extern/native ABI без extern struct и extern fn"), cv_getkey(v_fn, "file"), v_fn)
    let logic_34: bool = not (cv_truth(cv_getkey(v_fn, "is_unsafe")))
    if logic_34:
        let collect_28: i64 = cv_vector(CV_LIST)
        let items_29: i64 = cv_vector(CV_TUPLE)
        cv_extend(items_29, v_params)
        cv_push(items_29, cv_getkey(v_fn, "sig_ret"))
        let seq_31: i64 = items_29
        for index_30 in 0..cv_len(seq_31):
            let t_32: i64 = cv_at(seq_31, index_30)
            let choice_33: i64 = cv_bool(cv_truth(cc_is_ptr(t_32)) and not cc_is_owned_ptr(t_32))
            if not cv_truth(choice_33):
                choice_33 = cv_bool(cv_classes(t_32, "TFnPtr"))
            cv_push(collect_28, choice_33)
        logic_34 = cv_truth(cv_any(collect_28))
    if (logic_34):
        ccs_error(cv_text("функция с raw-указателями в сигнатуре должна быть объявлена unsafe"), cv_getkey(v_fn, "file"), v_fn)
        return 0
    return 0

unsafe fn ccs_check_slice_return_signature(v_fn: i64):
    let v_source: i64 = cv_getkey(v_fn, "ret_source")
    let v_ret: i64 = cv_getkey(v_fn, "sig_ret")
    let v_file: i64 = cv_getkey(v_fn, "file")
    let v_line: i64 = cv_getkey(v_fn, "line")
    if not cv_classes(v_ret, "TSlice"):
        if v_source != 0:
            cc_error(cv_text("from допустим только для возвращаемого неизменяемого slice"), v_file, v_line)
        return
    if cc_is_mut_slice(v_ret):
        cc_error(cv_text("возврат slice пока запрещён для []mut"), v_file, v_line)
        return
    if v_source == 0:
        cc_error(cv_text("возврат slice пока запрещён без явно указанного источника from <параметр>"), v_file, v_line)
        return
    let v_params: i64 = cv_getkey(v_fn, "sig_params")
    for i in 0..cv_len(v_params):
        let v_param: i64 = cv_at(v_params, i)
        if cv_equal(cv_at(v_param, 0), v_source):
            if cc_is_owned_ptr(cv_at(v_param, 1)):
                # Срез байтов владельца: источник — адрес владельца, а не другой срез.
                cv_field(v_fn, "ret_source_index", cv_i(i))
                return
            if not cv_equal(cv_at(v_param, 1), v_ret):
                cc_error(cv_text("from должен называть параметр неизменяемого slice того же типа, что и результат"), v_file, v_line)
                return
            cv_field(v_fn, "ret_source_index", cv_i(i))
            return
    cc_error(cv_cat(cv_text("from называет неизвестный параметр: "), v_source), v_file, v_line)

unsafe fn ccs_generic_type(v_self: i64, v_texpr: i64, v_variables: i64, v_pattern: i64) -> i64:
    let v_old: i64 = 0
    v_old = cv_getkey(v_self, "type_vars")
    cv_field(v_self, "type_vars", v_variables)
    let resolved_1: i64 = ccs_resolve_type(v_self, v_texpr, v_pattern)
    cv_field(v_self, "type_vars", v_old)
    return resolved_1
    return 0

unsafe fn ccs_unify_generic(v_self: i64, v_pattern: i64, v_actual: i64, v_variables: i64, v_file: i64, v_packed: i64) -> i64:
    let v_prior: i64 = 0
    let v_formal: i64 = 0
    let v_supplied: i64 = 0
    let v_pt: i64 = 0
    let v_at: i64 = 0
    let v_line: i64 = cv_at(v_packed, 0)
    let v_allow_conversion: i64 = cv_at(v_packed, 1)
    if (v_actual == 0):
        cc_error(cv_text("для аргумента требуется значение"), v_file, v_line)
        return 0
    if cv_classes(v_pattern, "TTypeVar"):
        v_prior = cv_get(v_variables, cv_getkey(v_pattern, "name"), 0)
        if ((not (v_prior == 0)) and (not (cv_equal(v_prior, v_actual)))):
            let pieces_1: i64 = cv_list()
            cv_push(pieces_1, cv_text("параметр типа "))
            cv_push(pieces_1, cv_format(cv_getkey(v_pattern, "name"), ""))
            cv_push(pieces_1, cv_text(": конфликт "))
            cv_push(pieces_1, cv_format(cc_display(v_prior), ""))
            cv_push(pieces_1, cv_text(" и "))
            cv_push(pieces_1, cv_format(cc_display(v_actual), ""))
            cc_error(cv_join(cv_text(""), pieces_1), v_file, v_line)
            return 0
        cv_set(v_variables, cv_getkey(v_pattern, "name"), v_actual)
        return 0
    if (cv_classes(v_pattern, "TPtr") and cv_classes(v_actual, "TPtr")):
        let options_2: i64 = cv_tuple()
        cv_push(options_2, v_line)
        cv_push(options_2, CV_FALSE)
        return ccs_unify_generic(v_self, cv_getkey(v_pattern, "elem"), cv_getkey(v_actual, "elem"), v_variables, v_file, options_2)
    if (cv_classes(v_pattern, "TFnPtr") and cv_classes(v_actual, "TFnPtr")):
        if ((cv_equal(cv_length(cv_getkey(v_pattern, "params")), cv_length(cv_getkey(v_actual, "params")))) and (cv_equal(cv_bool((cv_getkey(v_pattern, "result") == 0)), cv_bool((cv_getkey(v_actual, "result") == 0))))):
            let seq_4: i64 = cv_zip(cv_getkey(v_pattern, "params"), cv_getkey(v_actual, "params"))
            for index_3 in 0..cv_len(seq_4):
                let unpack_5: i64 = cv_at(seq_4, index_3)
                v_formal = cv_at(unpack_5, 0)
                v_supplied = cv_at(unpack_5, 1)
                let options_6: i64 = cv_tuple()
                cv_push(options_6, v_line)
                cv_push(options_6, CV_FALSE)
                ccs_unify_generic(v_self, v_formal, v_supplied, v_variables, v_file, options_6)
            if (not (cv_getkey(v_pattern, "result") == 0)):
                let options_7: i64 = cv_tuple()
                cv_push(options_7, v_line)
                cv_push(options_7, CV_FALSE)
                ccs_unify_generic(v_self, cv_getkey(v_pattern, "result"), cv_getkey(v_actual, "result"), v_variables, v_file, options_7)
            return 0
    if (cv_classes(v_pattern, "TArray") and cv_classes(v_actual, "TArray") and (cv_equal(cv_getkey(v_pattern, "n"), cv_getkey(v_actual, "n")))):
        let options_8: i64 = cv_tuple()
        cv_push(options_8, v_line)
        cv_push(options_8, CV_FALSE)
        return ccs_unify_generic(v_self, cv_getkey(v_pattern, "elem"), cv_getkey(v_actual, "elem"), v_variables, v_file, options_8)
    if (cv_classes(v_pattern, "TSlice") and cv_classes(v_actual, "TSlice") and (cv_equal(cv_getkey(v_pattern, "mutable"), cv_getkey(v_actual, "mutable")))):
        let options_9: i64 = cv_tuple()
        cv_push(options_9, v_line)
        cv_push(options_9, CV_FALSE)
        return ccs_unify_generic(v_self, cv_getkey(v_pattern, "elem"), cv_getkey(v_actual, "elem"), v_variables, v_file, options_9)
    if (cv_truth(cc_is_struct(v_pattern)) and cv_truth(cc_is_struct(v_actual)) and (cv_equal(cv_getkey(v_pattern, "name"), cv_getkey(v_actual, "name")))):
        let seq_11: i64 = cv_zip(cv_getkey(v_pattern, "args"), cv_getkey(v_actual, "args"))
        for index_10 in 0..cv_len(seq_11):
            let unpack_12: i64 = cv_at(seq_11, index_10)
            v_pt = cv_at(unpack_12, 0)
            v_at = cv_at(unpack_12, 1)
            let options_13: i64 = cv_tuple()
            cv_push(options_13, v_line)
            cv_push(options_13, CV_FALSE)
            ccs_unify_generic(v_self, v_pt, v_at, v_variables, v_file, options_13)
        return 0
    if ((not (cv_equal(v_pattern, v_actual))) and not ((cv_truth(v_allow_conversion) and cv_truth(cc_can_assign(v_actual, v_pattern))))):
        let pieces_14: i64 = cv_list()
        cv_push(pieces_14, cv_text("тип аргумента "))
        cv_push(pieces_14, cv_format(cc_display(v_actual), ""))
        cv_push(pieces_14, cv_text(" несовместим с "))
        cv_push(pieces_14, cv_format(cc_display(v_pattern), ""))
        cc_error(cv_join(cv_text(""), pieces_14), v_file, v_line)
        return 0
    return 0

unsafe fn ccs_infer_type_args(v_self: i64, v_parameters: i64, v_fields: i64, v_args: i64, v_file: i64, v_packed: i64) -> i64:
    let v_variables: i64 = 0
    let v_mapping: i64 = 0
    let v_constructors: i64 = 0
    let v_arg: i64 = 0
    let v_field: i64 = 0
    let v_pattern: i64 = 0
    let v_record: i64 = 0
    let v_actual: i64 = 0
    let v_required: i64 = 0
    let v_expected: i64 = 0
    let v_missing: i64 = 0
    let v_line: i64 = cv_at(v_packed, 0)
    let v_allow_conversion: i64 = cv_at(v_packed, 1)
    let collect_1: i64 = cv_vector(CV_DICT)
    let seq_3: i64 = v_parameters
    for index_2 in 0..cv_len(seq_3):
        let name_4: i64 = cv_at(seq_3, index_2)
        cv_set(collect_1, name_4, cc_TTypeVar(name_4))
    v_variables = collect_1
    v_mapping = cv_dict()
    let items_5: i64 = cv_vector(CV_LIST)
    v_constructors = items_5
    let seq_7: i64 = cv_zip(v_args, v_fields)
    for index_6 in 0..cv_len(seq_7):
        let unpack_8: i64 = cv_at(seq_7, index_6)
        v_arg = cv_at(unpack_8, 0)
        v_field = cv_at(unpack_8, 1)
        v_pattern = ccs_generic_type(v_self, v_field, v_variables, CV_TRUE)
        let choice_9: i64 = 0
        if cv_classes(v_arg, "Call"):
            choice_9 = cv_get(cv_getkey(v_self, "struct_defs"), cv_getkey(v_arg, "name"), 0)
        else:
            choice_9 = 0
        v_record = choice_9
        if ((not (v_record == 0)) and cv_truth(cv_getkey(v_record, "type_params"))):
            let items_10: i64 = cv_vector(CV_TUPLE)
            cv_push(items_10, v_arg)
            cv_push(items_10, v_field)
            cv_push(items_10, v_pattern)
            cv_push(items_10, cc_type_variables(v_pattern))
            cv_push(v_constructors, items_10)
        else:
            v_actual = ccs_tf(v_self, v_arg, 0)
            let options_11: i64 = cv_tuple()
            cv_push(options_11, cv_getkey(v_arg, "line"))
            cv_push(options_11, v_allow_conversion)
            ccs_unify_generic(v_self, v_pattern, v_actual, v_mapping, v_file, options_11)
    let seq_13: i64 = v_constructors
    for index_12 in 0..cv_len(seq_13):
        let unpack_14: i64 = cv_at(seq_13, index_12)
        v_arg = cv_at(unpack_14, 0)
        v_field = cv_at(unpack_14, 1)
        v_pattern = cv_at(unpack_14, 2)
        v_required = cv_at(unpack_14, 3)
        let choice_15: i64 = 0
        if (cv_le(v_required, cv_keys(v_mapping))):
            choice_15 = ccs_generic_type(v_self, v_field, v_mapping, CV_FALSE)
        else:
            choice_15 = 0
        v_expected = choice_15
        v_actual = ccs_tf(v_self, v_arg, v_expected)
        let options_16: i64 = cv_tuple()
        cv_push(options_16, cv_getkey(v_arg, "line"))
        cv_push(options_16, v_allow_conversion)
        ccs_unify_generic(v_self, v_pattern, v_actual, v_mapping, v_file, options_16)
    let collect_17: i64 = cv_vector(CV_LIST)
    let seq_19: i64 = v_parameters
    for index_18 in 0..cv_len(seq_19):
        let name_20: i64 = cv_at(seq_19, index_18)
        if not ((not (cv_contains(v_mapping, name_20)))): continue
        cv_push(collect_17, name_20)
    v_missing = collect_17
    if cv_truth(v_missing):
        cc_error(cv_add(cv_text("не удалось вывести параметры типа: "), cv_join(cv_text(", "), v_missing)), v_file, v_line)
        return 0
    let collect_21: i64 = cv_vector(CV_LIST)
    let seq_23: i64 = v_parameters
    for index_22 in 0..cv_len(seq_23):
        let name_24: i64 = cv_at(seq_23, index_22)
        cv_push(collect_21, cv_subscript(v_mapping, name_24))
    return cv_astuple(collect_21)

unsafe fn ccs_instantiate_generic(v_self: i64, v_source: i64, v_args: i64, v_caller_file: i64, v_call_line: i64) -> i64:
    let v_types: i64 = 0
    let v_key: i64 = 0
    let v_depth: i64 = 0
    let v_mapping: i64 = 0
    let v_params: i64 = 0
    let v_ret: i64 = 0
    let v_fn: i64 = 0
    if (not (cv_equal(cv_length(v_args), cv_length(cv_getkey(v_source, "params"))))):
        cc_error(cv_cat(cv_format(cv_getkey(v_source, "name"), ""), cv_text(": неверное число аргументов")), v_caller_file, v_call_line)
        return 0
    let collect_1: i64 = cv_vector(CV_LIST)
    let seq_3: i64 = cv_getkey(v_source, "params")
    for index_2 in 0..cv_len(seq_3):
        let unpack_4: i64 = cv_at(seq_3, index_2)
        let pt_5: i64 = cv_at(unpack_4, 1)
        cv_push(collect_1, pt_5)
    let options_6: i64 = cv_tuple()
    cv_push(options_6, v_call_line)
    cv_push(options_6, CV_FALSE)
    let v_names: i64 = cv_getkey(v_source, "type_params")
    v_types = ccs_infer_type_args(v_self, v_names, collect_1, v_args, v_caller_file, options_6)
    # Deferred specialization checks inherit the first concrete call site.
    let v_caller: i64 = cv_getkey(v_self, "fn")
    let v_origin: i64 = cv_getkey(v_caller, "specialization_origin")
    if v_origin == 0: v_origin = cv_pair(v_caller_file, v_call_line)
    let v_eq_params: i64 = cv_getkey(v_source, "eq_params")
    if cv_truth(v_eq_params):
        for i in 0..cv_len(v_names):
            let v_name: i64 = cv_at(v_names, i)
            if not cv_contains(v_eq_params, v_name): continue
            let v_type: i64 = cv_at(v_types, i)
            if cc_satisfies_eq(v_type): continue
            let v_message: i64 = cv_list()
            cv_push(v_message, cv_get(v_source, cv_text("source_name"), cv_getkey(v_source, "name")))
            cv_push(v_message, cv_text(": ограничение "))
            cv_push(v_message, v_name)
            cv_push(v_message, cv_text(": Eq не выполнено для "))
            cv_push(v_message, cc_display(v_type))
            cc_error(cv_join(cv_text(""), v_message), cv_at(v_origin, 0), cv_at(v_origin, 1))
            return 0
    v_key = cv_pair(cv_getkey(v_source, "name"), v_types)
    if (cv_contains(cv_getkey(v_self, "specialization_cache"), v_key)):
        return cv_subscript(cv_getkey(v_self, "specialization_cache"), v_key)
    v_depth = cv_add(cv_get(v_caller, cv_text("specialization_depth"), 3), 11)
    if (cv_less(515, v_depth)):
        cc_error(cv_text("превышена глубина специализации generic-функций"), v_caller_file, v_call_line)
        return 0
    if (cv_le(32771, cv_length(cv_getkey(v_self, "specializations")))):
        cc_error(cv_text("слишком много специализаций generic-функций"), v_caller_file, v_call_line)
        return 0
    v_mapping = cv_asdict(cv_zip(v_names, v_types))
    let collect_7: i64 = cv_vector(CV_LIST)
    let seq_9: i64 = cv_getkey(v_source, "params")
    for index_8 in 0..cv_len(seq_9):
        let unpack_10: i64 = cv_at(seq_9, index_8)
        let n_11: i64 = cv_at(unpack_10, 0)
        let t_12: i64 = cv_at(unpack_10, 1)
        cv_push(collect_7, cv_pair(n_11, ccs_generic_type(v_self, t_12, v_mapping, CV_FALSE)))
    v_params = collect_7
    let choice_13: i64 = 0
    if cv_truth(cv_getkey(v_source, "ret")):
        choice_13 = ccs_generic_type(v_self, cv_getkey(v_source, "ret"), v_mapping, CV_FALSE)
    else:
        choice_13 = 0
    v_ret = choice_13
    v_fn = cv_clone(v_source)
    let items_14: i64 = cv_vector(CV_TUPLE)
    cv_field(v_fn, "type_params", items_14)
    cv_field(v_fn, "body", cc_subst(v_self, v_mapping, cv_getkey(v_fn, "body")))
    let collect_15: i64 = cv_vector(CV_LIST)
    let seq_17: i64 = v_params
    for index_16 in 0..cv_len(seq_17):
        let unpack_18: i64 = cv_at(seq_17, index_16)
        let n_19: i64 = cv_at(unpack_18, 0)
        let t_20: i64 = cv_at(unpack_18, 1)
        let items_21: i64 = cv_vector(CV_TUPLE)
        cv_push(items_21, t_20)
        cv_push(collect_15, cv_pair(n_19, cc_TExpr(cv_text("resolved"), items_21, cv_getkey(v_source, "line"), cv_getkey(v_source, "file"))))
    cv_field(v_fn, "params", collect_15)
    let choice_22: i64 = 0
    if cv_truth(v_ret):
        let items_23: i64 = cv_vector(CV_TUPLE)
        cv_push(items_23, v_ret)
        choice_22 = cc_TExpr(cv_text("resolved"), items_23, cv_getkey(v_source, "line"), cv_getkey(v_source, "file"))
    else:
        choice_22 = 0
    cv_field(v_fn, "ret", choice_22)
    let unpack_24: i64 = cv_pair(v_params, v_ret)
    cv_field(v_fn, "sig_params", cv_at(unpack_24, 0))
    cv_field(v_fn, "sig_ret", cv_at(unpack_24, 1))
    cv_field(v_fn, "specialization_depth", v_depth)
    cv_field(v_fn, "specialization_origin", v_origin)
    ccs_check_fn_abi(v_self, v_fn)
    let pieces_25: i64 = cv_list()
    cv_push(pieces_25, cv_format(cv_getkey(v_source, "name"), ""))
    cv_push(pieces_25, cv_text("$"))
    cv_push(pieces_25, cv_format(cv_length(cv_getkey(v_self, "specializations")), ""))
    cv_field(v_fn, "mangled_name", cv_join(cv_text(""), pieces_25))
    cv_set(cv_getkey(v_self, "specialization_cache"), v_key, v_fn)
    cv_push(cv_getkey(v_self, "specializations"), v_fn)
    return v_fn

unsafe fn cc_subst(v_self: i64, v_mapping: i64, v_node: i64) -> i64:
    let v_attr: i64 = 0
    let v_value: i64 = 0
    if cv_classes(v_node, "TExpr"):
        let items_1: i64 = cv_vector(CV_TUPLE)
        cv_push(items_1, ccs_generic_type(v_self, v_node, v_mapping, CV_FALSE))
        return cc_TExpr(cv_text("resolved"), items_1, cv_getkey(v_node, "line"), cv_getkey(v_node, "file"))
    if cv_classes(v_node, "list"):
        let collect_2: i64 = cv_vector(CV_LIST)
        let seq_4: i64 = v_node
        for index_3 in 0..cv_len(seq_4):
            let x_5: i64 = cv_at(seq_4, index_3)
            cv_push(collect_2, cc_subst(v_self, v_mapping, x_5))
        return collect_2
    if cv_classes(v_node, "tuple"):
        let collect_6: i64 = cv_vector(CV_LIST)
        let seq_8: i64 = v_node
        for index_7 in 0..cv_len(seq_8):
            let x_9: i64 = cv_at(seq_8, index_7)
            cv_push(collect_6, cc_subst(v_self, v_mapping, x_9))
        return cv_astuple(collect_6)
    if cv_kind(v_node) == CV_NODE:
        let seq_11: i64 = cv_aslist(cv_items(v_node))
        for index_10 in 0..cv_len(seq_11):
            let unpack_12: i64 = cv_at(seq_11, index_10)
            v_attr = cv_at(unpack_12, 0)
            v_value = cv_at(unpack_12, 1)
            cv_set(v_node, v_attr, cc_subst(v_self, v_mapping, v_value))
    return v_node

unsafe fn ccs_const_truthy(v_self: i64, v_e: i64, v_value: i64) -> i64:
    let v_typ: i64 = 0
    v_typ = cv_get(v_e, cv_text("type"), 0)
    if cv_truth(cc_is_float(v_typ)):
        let choice_1: i64 = cv_bool((cv_equal(v_value, v_value)))
        if cv_truth(choice_1):
            choice_1 = cv_bool((not (cv_equal(v_value, cv_real(0.0)))))
        return choice_1
    if cv_truth(cc_is_ptr(v_typ)):
        let choice_2: i64 = cv_bool((not (cv_equal(v_value, 3))))
        if not cv_truth(choice_2):
            choice_2 = cv_bool(cv_classes(v_value, "str"))
        return choice_2
    if cv_truth(cc_is_string(v_typ)):
        let choice_3: i64 = cv_bool((not (cv_equal(v_value, 3))))
        if not cv_truth(choice_3):
            choice_3 = cv_bool(cv_classes(v_value, "str"))
        return choice_3
    return cv_bool(cv_truth(v_value))

unsafe fn ccs_fold_const(v_self: i64, v_e: i64) -> i64:
    let v_value: i64 = 0
    let v_lo: i64 = 0
    let v_hi: i64 = 0
    let v_operand: i64 = 0
    let v_left: i64 = 0
    let v_left_truth: i64 = 0
    let v_right: i64 = 0
    let v_common: i64 = 0
    let v_mask: i64 = 0
    let v_sign: i64 = 0
    let v_q: i64 = 0
    let v_typ: i64 = 0
    if cv_classes(v_e, "IntLit"):
        v_value = cv_getkey(v_e, "val")
    else:
        if cv_classes(v_e, "FloatLit"):
            v_value = cv_getkey(v_e, "val")
        else:
            if cv_classes(v_e, "BoolLit"):
                v_value = cv_int(cv_getkey(v_e, "val"), 83)
            else:
                if cv_classes(v_e, "CharLit"):
                    v_value = cv_ordinal(cv_getkey(v_e, "val"))
                else:
                    if cv_classes(v_e, "StrLit"):
                        v_value = cv_getkey(v_e, "val")
                    else:
                        if (cv_classes(v_e, "Member") and cv_has(v_e, cv_text("enum_value"))):
                            v_value = cv_getkey(v_e, "enum_value")
                        else:
                            if cv_has(v_e, cv_text("const_binding")):
                                v_value = cv_subscript(cv_getkey(v_e, "const_binding"), 11)
                            else:
                                if cv_classes(v_e, "SizeAlignExpr"):
                                    v_value = cv_getkey(v_e, "const_value")
                                else:
                                    if cv_classes(v_e, "ArrayLit"):
                                        let collect_1: i64 = cv_vector(CV_LIST)
                                        let seq_3: i64 = cv_getkey(v_e, "items")
                                        for index_2 in 0..cv_len(seq_3):
                                            let item_4: i64 = cv_at(seq_3, index_2)
                                            cv_push(collect_1, ccs_fold_const(v_self, item_4))
                                        v_value = collect_1
                                    else:
                                        if cv_classes(v_e, "Cast"):
                                            v_value = ccs_fold_const(v_self, cv_getkey(v_e, "x"))
                                            if cv_truth(cc_is_int(cv_getkey(v_e, "type"))):
                                                v_value = cv_int(v_value, 83)
                                                if v_value == 0: ccs_error(cv_text("некорректное константное приведение к целому"), 0, v_e)
                                                let unpack_5: i64 = cc_int_bounds(cv_getkey(v_e, "type"))
                                                v_lo = cv_at(unpack_5, 0)
                                                v_hi = cv_at(unpack_5, 1)
                                                if ((cv_less(v_value, v_lo)) or (cv_less(v_hi, v_value))):
                                                    ccs_error(cv_text("целочисленное переполнение в const"), 0, v_e)
                                                    return 0
                                            else:
                                                if (cv_truth(cc_is_float(cv_getkey(v_e, "type"))) and (cv_equal(cv_getkey(cv_getkey(v_e, "type"), "bits"), 515))):
                                                    v_value = cv_f(v_value)
                                        else:
                                            if cv_classes(v_e, "Unary"):
                                                v_operand = ccs_fold_const(v_self, cv_getkey(v_e, "x"))
                                                if (cv_equal(cv_getkey(v_e, "op"), cv_text("-"))):
                                                    v_value = cv_neg(v_operand)
                                                else:
                                                    if (cv_equal(cv_getkey(v_e, "op"), cv_text("not"))):
                                                        v_value = cv_int(cv_bool(not (cv_truth(ccs_const_truthy(v_self, cv_getkey(v_e, "x"), v_operand)))), 83)
                                                    else:
                                                        ccs_error(cv_add(cv_text("const: унарная операция "), cv_getkey(v_e, "op")), 0, v_e)
                                                        return 0
                                            else:
                                                if cv_classes(v_e, "Binary"):
                                                    if cv_truth(cv_get(v_e, cv_text("sugar"), 0)):
                                                        ccs_error(cv_text("строковые операции нельзя использовать в глобальной константе"), 0, v_e)
                                                        return 0
                                                    v_left = ccs_fold_const(v_self, cv_getkey(v_e, "l"))
                                                    v_left_truth = ccs_const_truthy(v_self, cv_getkey(v_e, "l"), v_left)
                                                    if ((cv_equal(cv_getkey(v_e, "op"), cv_text("and"))) and not (cv_truth(v_left_truth))):
                                                        v_value = 3
                                                    else:
                                                        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("or"))) and cv_truth(v_left_truth)):
                                                            v_value = 11
                                                        else:
                                                            let subject_6: i64 = cv_getkey(v_e, "op")
                                                            if ((cv_equal(subject_6, cv_text("and")) or cv_equal(subject_6, cv_text("or")))):
                                                                v_right = ccs_fold_const(v_self, cv_getkey(v_e, "r"))
                                                                v_value = cv_int(ccs_const_truthy(v_self, cv_getkey(v_e, "r"), v_right), 83)
                                                            else:
                                                                v_right = ccs_fold_const(v_self, cv_getkey(v_e, "r"))
                                                                let choice_7: i64 = cv_get(v_e, cv_text("common"), 0)
                                                                if not cv_truth(choice_7):
                                                                    choice_7 = cv_get(v_e, cv_text("cmp_common"), 0)
                                                                v_common = choice_7
                                                                if cv_truth(cc_is_int(v_common)):
                                                                    v_mask = cv_sub(cv_shl(11, cv_getkey(v_common, "bits")), 11)
                                                                    v_left = cv_and(cv_int(v_left, 83), v_mask)
                                                                    v_right = cv_and(cv_int(v_right, 83), v_mask)
                                                                    if cv_truth(cv_getkey(v_common, "signed")):
                                                                        v_sign = cv_shl(11, cv_sub(cv_getkey(v_common, "bits"), 11))
                                                                        if cv_truth(cv_and(v_left, v_sign)):
                                                                            v_left = cv_sub(v_left, cv_shl(11, cv_getkey(v_common, "bits")))
                                                                        if cv_truth(cv_and(v_right, v_sign)):
                                                                            v_right = cv_sub(v_right, cv_shl(11, cv_getkey(v_common, "bits")))
                                                                if (cv_equal(cv_getkey(v_e, "op"), cv_text("+"))):
                                                                    v_value = cv_add(v_left, v_right)
                                                                else:
                                                                    if (cv_equal(cv_getkey(v_e, "op"), cv_text("-"))):
                                                                        v_value = cv_sub(v_left, v_right)
                                                                    else:
                                                                        if (cv_equal(cv_getkey(v_e, "op"), cv_text("*"))):
                                                                            v_value = cv_mul(v_left, v_right)
                                                                        else:
                                                                            if (cv_equal(cv_getkey(v_e, "op"), cv_text("/"))):
                                                                                if cv_truth(cc_is_float(v_common)):
                                                                                    if (not (cv_equal(v_right, 3))):
                                                                                        v_value = cv_numdiv(v_left, v_right)
                                                                                    else:
                                                                                        if ((cv_equal(v_left, 3)) or cv_truth(cv_isnan(v_left))):
                                                                                            v_value = cv_f(cv_text("nan"))
                                                                                        else:
                                                                                            v_sign = cv_mul(cv_copysign(cv_real(1.0), v_left), cv_copysign(cv_real(1.0), v_right))
                                                                                            v_value = cv_copysign(cv_f(cv_text("inf")), v_sign)
                                                                                else:
                                                                                    if cv_truth(cc_is_int(v_common)):
                                                                                        if (cv_equal(v_right, 3)):
                                                                                            ccs_error(cv_text("деление на 0 в const"), 0, v_e)
                                                                                            return 0
                                                                                        if (cv_truth(cv_getkey(v_common, "signed")) and (cv_equal(v_left, cv_neg(cv_shl(11, 507)))) and (cv_equal(v_right, cv_neg(11)))):
                                                                                            ccs_error(cv_text("целочисленное переполнение в const"), 0, v_e)
                                                                                            return 0
                                                                                        v_q = cv_floor(cv_abs(v_left), cv_abs(v_right))
                                                                                        let choice_8: i64 = 0
                                                                                        if (cv_equal(cv_bool((cv_less(v_left, 3))), cv_bool((cv_less(v_right, 3))))):
                                                                                            choice_8 = v_q
                                                                                        else:
                                                                                            choice_8 = cv_neg(v_q)
                                                                                        v_value = choice_8
                                                                                    else:
                                                                                        ccs_error(cv_text("неконстантное деление"), 0, v_e)
                                                                                        return 0
                                                                            else:
                                                                                if (cv_equal(cv_getkey(v_e, "op"), cv_text("%"))):
                                                                                    if (cv_equal(v_right, 3)):
                                                                                        ccs_error(cv_text("деление на 0 в const"), 0, v_e)
                                                                                        return 0
                                                                                    if (cv_truth(cc_is_int(v_common)) and cv_truth(cv_getkey(v_common, "signed")) and (cv_equal(v_left, cv_neg(cv_shl(11, 507)))) and (cv_equal(v_right, cv_neg(11)))):
                                                                                        ccs_error(cv_text("целочисленное переполнение в const"), 0, v_e)
                                                                                        return 0
                                                                                    v_q = cv_floor(cv_abs(v_left), cv_abs(v_right))
                                                                                    let choice_9: i64 = 0
                                                                                    if (cv_equal(cv_bool((cv_less(v_left, 3))), cv_bool((cv_less(v_right, 3))))):
                                                                                        choice_9 = v_q
                                                                                    else:
                                                                                        choice_9 = cv_neg(v_q)
                                                                                    v_q = choice_9
                                                                                    v_value = cv_sub(v_left, cv_mul(v_q, v_right))
                                                                                else:
                                                                                    if (cv_equal(cv_getkey(v_e, "op"), cv_text("&"))):
                                                                                        v_value = cv_and(cv_and(v_left, v_right), cv_u(0xffffffffffffffff))
                                                                                    else:
                                                                                        if (cv_equal(cv_getkey(v_e, "op"), cv_text("|"))):
                                                                                            v_value = cv_and(cv_or(v_left, v_right), cv_u(0xffffffffffffffff))
                                                                                        else:
                                                                                            if (cv_equal(cv_getkey(v_e, "op"), cv_text("^"))):
                                                                                                v_value = cv_and(cv_xor(v_left, v_right), cv_u(0xffffffffffffffff))
                                                                                            else:
                                                                                                if (cv_equal(cv_getkey(v_e, "op"), cv_text("<<"))):
                                                                                                    if ((cv_less(v_right, 3)) or (cv_le(cv_getkey(v_common, "bits"), v_right))):
                                                                                                        ccs_error(cv_text("некорректное число битов сдвига"), 0, v_e)
                                                                                                        return 0
                                                                                                    v_value = cv_and(cv_shl(v_left, v_right), cv_sub(cv_shl(11, cv_getkey(v_common, "bits")), 11))
                                                                                                else:
                                                                                                    if (cv_equal(cv_getkey(v_e, "op"), cv_text(">>"))):
                                                                                                        if ((cv_less(v_right, 3)) or (cv_le(cv_getkey(v_common, "bits"), v_right))):
                                                                                                            ccs_error(cv_text("некорректное число битов сдвига"), 0, v_e)
                                                                                                            return 0
                                                                                                        v_value = cv_shr(v_left, v_right)
                                                                                                    else:
                                                                                                        let subject_10: i64 = cv_getkey(v_e, "op")
                                                                                                        if ((cv_equal(subject_10, cv_text("==")) or cv_equal(subject_10, cv_text("!=")) or cv_equal(subject_10, cv_text(">")) or cv_equal(subject_10, cv_text("<")) or cv_equal(subject_10, cv_text(">=")) or cv_equal(subject_10, cv_text("<=")))):
                                                                                                            let dict_11: i64 = cv_dict()
                                                                                                            cv_set(dict_11, cv_text("=="), cv_bool((cv_equal(v_left, v_right))))
                                                                                                            cv_set(dict_11, cv_text("!="), cv_bool((not (cv_equal(v_left, v_right)))))
                                                                                                            cv_set(dict_11, cv_text(">"), cv_bool((cv_less(v_right, v_left))))
                                                                                                            cv_set(dict_11, cv_text("<"), cv_bool((cv_less(v_left, v_right))))
                                                                                                            cv_set(dict_11, cv_text(">="), cv_bool((cv_le(v_right, v_left))))
                                                                                                            cv_set(dict_11, cv_text("<="), cv_bool((cv_le(v_left, v_right))))
                                                                                                            v_value = cv_int(cv_subscript(dict_11, cv_getkey(v_e, "op")), 83)
                                                                                                        else:
                                                                                                            ccs_error(cv_add(cv_text("const-fold: операция "), cv_getkey(v_e, "op")), 0, v_e)
                                                                                                            return 0
                                                                let logic_13: bool = cv_truth(cc_is_int(v_common))
                                                                if logic_13:
                                                                    let subject_12: i64 = cv_getkey(v_e, "op")
                                                                    logic_13 = ((cv_equal(subject_12, cv_text("+")) or cv_equal(subject_12, cv_text("-")) or cv_equal(subject_12, cv_text("*")) or cv_equal(subject_12, cv_text("/")) or cv_equal(subject_12, cv_text("%"))))
                                                                if (logic_13):
                                                                    let unpack_14: i64 = cc_int_bounds(v_common)
                                                                    v_lo = cv_at(unpack_14, 0)
                                                                    v_hi = cv_at(unpack_14, 1)
                                                                    if ((cv_less(v_value, v_lo)) or (cv_less(v_hi, v_value))):
                                                                        ccs_error(cv_text("целочисленное переполнение в const"), 0, v_e)
                                                                        return 0
                                                else:
                                                    ccs_error(cv_text("неконстантное выражение при глобальной инициализации"), 0, v_e)
                                                    return 0
    v_typ = cv_get(v_e, cv_text("type"), 0)
    if (cv_truth(cc_is_int(v_typ)) and cv_classes(v_value, "int")):
        if (cv_classes(v_e, "Unary") and (cv_equal(cv_getkey(v_e, "op"), cv_text("-")))):
            let unpack_15: i64 = cc_int_bounds(v_typ)
            v_lo = cv_at(unpack_15, 0)
            v_hi = cv_at(unpack_15, 1)
            if ((cv_less(v_value, v_lo)) or (cv_less(v_hi, v_value))):
                ccs_error(cv_text("целочисленное переполнение в const"), 0, v_e)
                return 0
        v_value = cv_and(v_value, cv_sub(cv_shl(11, cv_getkey(v_typ, "bits")), 11))
        if (cv_truth(cv_getkey(v_typ, "signed")) and (cv_le(cv_shl(11, cv_sub(cv_getkey(v_typ, "bits"), 11)), v_value))):
            v_value = cv_sub(v_value, cv_shl(11, cv_getkey(v_typ, "bits")))
    else:
        if (cv_truth(cc_is_float(v_typ)) and (cv_equal(cv_getkey(v_typ, "bits"), 259))):
            v_value = cv_round32(v_value)
    cv_field(v_e, "const_val", v_value)
    return v_value

unsafe fn ccs_setup_fn(v_self: i64, v_fn: i64) -> i64:
    cc_error_file = cv_getkey(v_fn, "file")
    cc_error_line = cv_index(cv_getkey(v_fn, "line"))
    if ((cv_contains(cc_k_vec_reserved, cv_getkey(v_fn, "name"))) and not (cv_truth(cv_bool(cv_starts(cv_getkey(v_fn, "file"), cc_std))))):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("имя "))
        cv_push(pieces_1, cv_format(cv_getkey(v_fn, "name"), ""))
        cv_push(pieces_1, cv_text(" зарезервировано (встроенная функция)"))
        ccs_error(cv_join(cv_text(""), pieces_1), cv_getkey(v_fn, "file"), v_fn)
        return 0
    let items_2: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "slots", items_2)
    let items_3: i64 = cv_vector(CV_LIST)
    cv_push(items_3, cv_dict())
    cv_field(v_self, "scope", items_3)
    let items_4: i64 = cv_vector(CV_LIST)
    cv_push(items_4, cv_dict())
    cv_field(v_self, "const_scope", items_4)
    let items_5: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "defer_stack", items_5)
    cv_field(v_self, "future_local_names", cv_vector(CV_SET))
    cv_field(v_self, "defer_name_counter", 3)
    let items_6: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "loop_scope_depth", items_6)
    cv_field(v_self, "tempc", 3)
    cv_field(v_self, "fn", v_fn)
    cv_field(v_self, "unsafe_depth", 3)
    cv_field(v_self, "borrowed_slots", cv_vector(CV_SET))
    cv_field(v_self, "exclusive_slots", cv_vector(CV_SET))
    cv_field(v_self, "frozen_mut_slots", cv_vector(CV_SET))
    cv_field(v_self, "temp_slice_releases", cv_vector(CV_LIST))
    cv_field(v_self, "defer_action_depth", 0)
    cv_field(v_self, "tf_depth", 3)
    let items_7: i64 = cv_vector(CV_LIST)
    cv_field(v_fn, "loop_stack", items_7)
    return 0

unsafe fn ccs_declare(v_self: i64, v_name: i64, v_typ: i64, v_zero: i64, v_line: i64, v_kind: i64) -> i64:
    let v_sc: i64 = 0
    let v_sid: i64 = 0
    let v_prev: i64 = 0
    let v_off: i64 = 0
    v_sc = cv_subscript(cv_getkey(v_self, "scope"), cv_neg(11))
    if (cv_contains(v_sc, v_name)):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("имя "))
        cv_push(pieces_1, cv_format(v_name, ""))
        cv_push(pieces_1, cv_text(" объявлено дважды в этой области видимости"))
        cc_error(cv_join(cv_text(""), pieces_1), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_line)
        return 0
    v_sid = cv_length(cv_getkey(v_self, "slots"))
    let choice_2: i64 = 0
    if cv_truth(cv_getkey(v_self, "slots")):
        choice_2 = cv_getkey(cv_subscript(cv_getkey(v_self, "slots"), cv_neg(11)), "off")
    else:
        choice_2 = 3
    v_prev = choice_2
    v_off = cc_base_align(cv_add(v_prev, cc_type_size(v_typ)), cc_type_align(v_typ))
    cv_set(v_sc, v_name, v_sid)
    let extra_3: i64 = cv_tuple()
    cv_push(extra_3, v_line)
    cv_push(extra_3, v_kind)
    cv_push(cv_getkey(v_self, "slots"), cc_SlotK(v_name, v_typ, v_off, cc_type_size(v_typ), v_zero, extra_3))
    return v_sid

unsafe fn ccs_declare_temp(v_self: i64, v_typ: i64, v_line: i64) -> i64:
    let v_sid: i64 = 0
    let v_prev: i64 = 0
    let v_off: i64 = 0
    v_sid = cv_length(cv_getkey(v_self, "slots"))
    let choice_1: i64 = 0
    if cv_truth(cv_getkey(v_self, "slots")):
        choice_1 = cv_getkey(cv_subscript(cv_getkey(v_self, "slots"), cv_neg(11)), "off")
    else:
        choice_1 = 3
    v_prev = choice_1
    v_off = cc_base_align(cv_add(v_prev, cc_type_size(v_typ)), cc_type_align(v_typ))
    let extra_2: i64 = cv_tuple()
    cv_push(extra_2, v_line)
    cv_push(extra_2, cv_text("temp"))
    cv_push(cv_getkey(v_self, "slots"), cc_SlotK(cv_cat(cv_text("$temp"), cv_format(v_sid, "")), v_typ, v_off, cc_type_size(v_typ), CV_FALSE, extra_2))
    return v_sid

unsafe fn ccs_find_slot(v_self: i64, v_name: i64) -> i64:
    let v_sc: i64 = 0
    let seq_2: i64 = cv_reverse(cv_getkey(v_self, "scope"))
    for index_1 in 0..cv_len(seq_2):
        v_sc = cv_at(seq_2, index_1)
        if (cv_contains(v_sc, v_name)):
            return cv_subscript(cv_getkey(v_self, "slots"), cv_subscript(v_sc, v_name))
    return 0

unsafe fn ccs_typecheck_fn(v_self: i64, v_fn: i64) -> i64:
    let v_i: i64 = 0
    let v_s: i64 = 0
    let v_pn: i64 = 0
    let v_pt: i64 = 0
    if (not (cv_getkey(v_fn, "native") == 0)):
        let collect_1: i64 = cv_vector(CV_LIST)
        let seq_3: i64 = cv_getkey(v_fn, "params")
        for index_2 in 0..cv_len(seq_3):
            let unpack_4: i64 = cv_at(seq_3, index_2)
            let pn_5: i64 = cv_at(unpack_4, 0)
            let pt_6: i64 = cv_at(unpack_4, 1)
            let extra_7: i64 = cv_tuple()
            cv_push(extra_7, cv_getkey(v_fn, "line"))
            cv_push(extra_7, cv_text("param"))
            cv_push(collect_1, cc_SlotK(pn_5, ccs_resolve_type(v_self, pt_6, CV_FALSE), 3, cc_type_size(ccs_resolve_type(v_self, pt_6, CV_FALSE)), CV_FALSE, extra_7))
        cv_field(v_fn, "slots", collect_1)
        let seq_9: i64 = cv_enumerate(cv_getkey(v_fn, "slots"))
        for index_8 in 0..cv_len(seq_9):
            let unpack_10: i64 = cv_at(seq_9, index_8)
            v_i = cv_at(unpack_10, 0)
            v_s = cv_at(unpack_10, 1)
            cv_field(v_s, "off", cv_mul(v_i, 67))
        let choice_11: i64 = 0
        if cv_truth(cv_getkey(v_fn, "ret")):
            choice_11 = ccs_resolve_type(v_self, cv_getkey(v_fn, "ret"), CV_FALSE)
        else:
            choice_11 = 0
        cv_field(v_fn, "ret_type", choice_11)
        return 0
    if (cv_getkey(v_fn, "body") == 0):
        let items_12: i64 = cv_vector(CV_LIST)
        cv_field(v_fn, "slots", items_12)
        cv_field(v_fn, "ret_type", cv_getkey(v_fn, "sig_ret"))
        return 0
    ccs_setup_fn(v_self, v_fn)
    let choice_13: i64 = 0
    if cv_truth(cv_getkey(v_fn, "is_unsafe")):
        choice_13 = 11
    else:
        choice_13 = 3
    cv_field(v_self, "unsafe_depth", choice_13)
    cv_field(v_self, "had_ret", CV_FALSE)
    cv_field(v_self, "had_ret_values", CV_FALSE)
    let collect_14: i64 = cv_vector(CV_SET)
    let seq_16: i64 = cv_getkey(v_fn, "params")
    for index_15 in 0..cv_len(seq_16):
        let unpack_17: i64 = cv_at(seq_16, index_15)
        let pn_18: i64 = cv_at(unpack_17, 0)
        cv_add_set(collect_14, pn_18)
    cv_field(v_self, "fn_param_names", collect_14)
    let seq_20: i64 = cv_getkey(v_fn, "params")
    for index_19 in 0..cv_len(seq_20):
        let unpack_21: i64 = cv_at(seq_20, index_19)
        v_pn = cv_at(unpack_21, 0)
        v_pt = cv_at(unpack_21, 1)
        v_pt = ccs_resolve_type(v_self, v_pt, CV_FALSE)
        if (cv_classes(v_pt, "TSlice") and (not (cv_getkey(v_fn, "native") == 0))):
            ccs_error(cv_text("slice не поддерживается в native/extern ABI"), cv_getkey(v_fn, "file"), v_fn)
            return 0
        ccs_declare(v_self, v_pn, v_pt, CV_FALSE, cv_getkey(v_fn, "line"), cv_text("param"))
    let kindof_22: i64 = cv_getkey(v_fn, "sig_ret")
    if cc_is_tagged_value(kindof_22) or cv_classes(kindof_22, "TStruct"):
        cv_field(v_fn, "sret_slot", ccs_declare(v_self, cv_text("$sret"), cc_TPtr(cc_int(CV_TRUE, 67)), CV_FALSE, cv_getkey(v_fn, "line"), cv_text("sret")))
        cv_field(v_fn, "ret_snapshot_slot", ccs_declare(v_self, cv_text("$ret_snapshot"), cv_getkey(v_fn, "sig_ret"), CV_FALSE, cv_getkey(v_fn, "line"), cv_text("ret_snapshot")))
    else:
        cv_field(v_fn, "sret_slot", 0)
        cv_field(v_fn, "ret_snapshot_slot", 0)
    let choice_23: i64 = 0
    if (not (cv_getkey(v_fn, "body") == 0)):
        choice_23 = cv_getkey(v_fn, "body")
    else:
        let items_24: i64 = cv_vector(CV_LIST)
        choice_23 = items_24
    ccs_typecheck_stmts(v_self, choice_23)
    ccs_check_ownership(v_self, v_fn)
    cv_field(v_fn, "slots", cv_getkey(v_self, "slots"))
    cv_field(v_fn, "ret_type", cv_getkey(v_fn, "sig_ret"))
    if cv_getkey(v_fn, "ret_type") != 0 and ccs_block_flow(cv_getkey(v_fn, "body")) & CC_FLOW_NEXT != 0:
        let pieces_25: i64 = cv_list()
        cv_push(pieces_25, cv_text("функция "))
        cv_push(pieces_25, cv_format(cv_getkey(v_fn, "name"), ""))
        cv_push(pieces_25, cv_text(" с -> "))
        cv_push(pieces_25, cv_format(cc_display(cv_getkey(v_fn, "ret_type")), ""))
        cv_push(pieces_25, cv_text(" не завершается return"))
        ccs_error(cv_join(cv_text(""), pieces_25), cv_getkey(v_fn, "file"), v_fn)
        return 0
    if ((cv_getkey(v_fn, "ret_type") == 0) and cv_truth(cv_getkey(v_self, "had_ret_values"))):
        let pieces_26: i64 = cv_list()
        cv_push(pieces_26, cv_text("функция "))
        cv_push(pieces_26, cv_format(cv_getkey(v_fn, "name"), ""))
        cv_push(pieces_26, cv_text(" объявлена без ->, но содержит return со значением"))
        ccs_error(cv_join(cv_text(""), pieces_26), cv_getkey(v_fn, "file"), v_fn)
        return 0
    cv_field(v_self, "unsafe_depth", 3)
    return 0

# Only fallthrough and breaks can reach a later statement. Returns, continues
# and non-returning calls cannot; the enclosing loop consumes its own breaks.
const CC_FLOW_NEXT: i64 = 1
const CC_FLOW_BREAK: i64 = 2

unsafe fn cc_literal_condition(expr: i64) -> i64:
    if cv_classes(expr, "BoolLit"): return cv_getkey(expr, "val")
    return 0

unsafe fn ccs_block_flow(stmts: i64) -> i64:
    let flow: i64 = CC_FLOW_NEXT
    for i in 0..cv_len(stmts):
        if flow & CC_FLOW_NEXT == 0: break
        flow = (flow & CC_FLOW_BREAK) | ccs_stmt_flow(cv_at(stmts, i))
    return flow

unsafe fn ccs_stmt_flow(stmt: i64) -> i64:
    if cv_classes(stmt, "ReturnStmt") or cv_classes(stmt, "ContinueStmt"): return 0
    if cv_classes(stmt, "BreakStmt"): return CC_FLOW_BREAK
    if cv_classes(stmt, "ExprStmt") and cv_truth(cv_getkey(cv_getkey(stmt, "expr"), "no_return")): return 0
    if cv_classes(stmt, "UnsafeStmt"): return ccs_block_flow(cv_getkey(stmt, "body"))
    if cv_classes(stmt, "IfStmt"):
        let flow: i64 = 0
        let arms: i64 = cv_getkey(stmt, "conds")
        for i in 0..cv_len(arms):
            let arm: i64 = cv_at(arms, i)
            let known: i64 = cc_literal_condition(cv_at(arm, 0))
            if known == CV_FALSE: continue
            flow = flow | ccs_block_flow(cv_at(arm, 1))
            if known == CV_TRUE: return flow
        return flow | ccs_block_flow(cv_getkey(stmt, "els"))
    if cv_classes(stmt, "MatchStmt"):
        let flow: i64 = 0
        let arms: i64 = cv_getkey(stmt, "arms")
        for i in 0..cv_len(arms): flow = flow | ccs_block_flow(cv_getkey(cv_at(arms, i), "body"))
        return flow
    if cv_classes(stmt, "WhileStmt") and cc_literal_condition(cv_getkey(stmt, "cond")) == CV_TRUE:
        if ccs_block_flow(cv_getkey(stmt, "body")) & CC_FLOW_BREAK == 0: return 0
    return CC_FLOW_NEXT

unsafe fn ccs_tf(v_self: i64, v_e: i64, v_expected: i64) -> i64:
    # Flat expression chains (1+1+1+...) build a deep AST without any parser
    # recursion; bound the type-checking recursion before it overflows the
    # stack. Matches the temp-slot limit of the code generator in spirit.
    if cv_less(cv_i(4096), cv_getkey(v_self, "tf_depth")):
        ccs_error(cv_text("слишком глубокое выражение в одной инструкции"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
    cv_field(v_self, "tf_depth", cv_add(cv_getkey(v_self, "tf_depth"), 11))
    defer cv_field(v_self, "tf_depth", cv_sub(cv_getkey(v_self, "tf_depth"), 11))
    if cv_classes(v_e, "Call"):
        # Constructors compare this hint against the resolved, not the source, name.
        if cv_classes(v_expected, "TWrapper") or cv_classes(v_expected, "TStruct"):
            cv_field(v_e, "context_type", v_expected)
    if cv_classes(v_e, "Call"): ccs_buffer_check_call(v_self, v_e)
    let v_loan_mark: i64 = 0
    let v_freeze_mark: i64 = 0
    if cv_classes(v_e, "Call"):
        v_loan_mark = cv_len(cv_getkey(v_self, "borrowed_slots"))
        v_freeze_mark = cv_len(cv_getkey(v_self, "frozen_mut_slots"))
    let v_t: i64 = ccs_typeof(v_self, v_e)
    if cv_classes(v_e, "Call"):
        ccs_check_mut_slice_args(v_self, v_e)
        ccs_note_temp_slice_args(v_self, v_e, v_loan_mark, v_freeze_mark)
    if cv_classes(v_e, "Cast"):
        let v_x: i64 = cv_getkey(v_e, "x")
        ccs_check_buffer_cast(v_self, cv_getkey(v_x, "type"), v_t, v_x)
    if ccs_buffer_type(v_self, v_t, "BufferRead") and not ccs_buffer_module_body(v_self):
        let v_scoped_arg: bool = cv_truth(cv_getkey(v_e, "buffer_read_argument")) and cv_truth(cv_getkey(cv_getkey(v_e, "slot"), "buffer_read_loan"))
        if not cv_truth(cv_getkey(v_e, "buffer_read_generated")) and not v_scoped_arg:
            ccs_error(cv_text("BufferRead нельзя копировать или передавать за пределы операций чтения"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
    cv_field(v_e, "type", v_t)
    # A literal that can never fit the annotated integer type must fail at
    # compile time, not trap at program start.
    if cv_classes(v_e, "IntLit") and cv_classes(v_expected, "TInt"):
        let v_bounds: i64 = cc_int_bounds(v_expected)
        if cv_less(cv_getkey(v_e, "val"), cv_at(v_bounds, 0)) or cv_less(cv_at(v_bounds, 1), cv_getkey(v_e, "val")):
            ccs_error(cv_cat(cv_text("целочисленный литерал вне диапазона "), cc_display(v_expected)), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
    if cv_classes(v_t, "TTaggedEnum") and (cv_classes(v_e, "Call") or cc_is_sum_ctor(v_e)):
        cv_field(v_e, "temp_slot", ccs_declare_temp(v_self, v_t, cv_getkey(v_e, "line")))
    elif cv_classes(v_e, "Call") and cv_classes(v_t, "TWrapper") and (cc_is_owned_result(v_t) or cv_less(cv_i(16), cc_type_size(v_t))):
        cv_field(v_e, "temp_slot", ccs_declare_temp(v_self, v_t, cv_getkey(v_e, "line")))
    return v_t

unsafe fn ccs_require_unsafe(v_self: i64, v_e: i64, v_operation: i64) -> i64:
    if (cv_le(cv_getkey(v_self, "unsafe_depth"), 3)):
        ccs_error(cv_cat(cv_format(v_operation, ""), cv_text(" требует unsafe-блок или unsafe-функцию")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    return 0

unsafe fn ccs_typeof(v_self: i64, v_e: i64) -> i64:
    let v_s: i64 = 0
    let v_binding: i64 = 0
    let v_typ: i64 = 0
    let v_value: i64 = 0
    let v_ret_hint: i64 = 0
    let v_t: i64 = 0
    let v_rt: i64 = 0
    let v_compatible: i64 = 0
    let v_l: i64 = 0
    let v_r: i64 = 0
    let v_common: i64 = 0
    let v_bt: i64 = 0
    let v_it: i64 = 0
    let v_st: i64 = 0
    let v_et: i64 = 0
    let v_enum: i64 = 0
    let v_fn: i64 = 0
    let v_ft: i64 = 0
    let v_off: i64 = 0
    let v_sz: i64 = 0
    let v_tt: i64 = 0
    let v_null_pointer: i64 = 0
    if cv_classes(v_e, "IntLit"):
        if (cv_less(cv_getkey(v_e, "val"), cv_neg(cv_u(0x8000000000000000)))):
            ccs_error(cv_text("целочисленный литерал выходит за диапазон i64"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        if (cv_less(cv_u(0xffffffffffffffff), cv_getkey(v_e, "val"))):
            ccs_error(cv_text("целочисленный литерал выходит за диапазон u64"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let choice_1: i64 = 0
        if (cv_less(cv_i(9223372036854775807), cv_getkey(v_e, "val"))):
            choice_1 = cc_int(CV_FALSE, 515)
        else:
            choice_1 = cc_int(CV_TRUE, 515)
        return choice_1
    if cv_classes(v_e, "FloatLit"):
        return cc_TFloat(515)
    if cv_classes(v_e, "CharLit"):
        return cc_k_char_type
    if cv_classes(v_e, "BoolLit"):
        return cc_TBool()
    if cv_classes(v_e, "StrLit"):
        return cv_getkey(v_self, "_string")
    if cv_classes(v_e, "VarRef"):
        v_s = ccs_find_slot(v_self, cv_getkey(v_e, "name"))
        if (not (v_s == 0)):
            cv_field(v_e, "slot", v_s)
            cv_field(v_e, "kind", cv_text("slot"))
            ccs_check_exclusive_owner(v_self, v_e)
            return cv_getkey(v_s, "typ")
        v_binding = ccs_const_lookup(v_self, cv_getkey(v_e, "name"))
        if (not (v_binding == 0)):
            cv_field(v_e, "const_binding", v_binding)
            return cv_subscript(v_binding, 3)
        let file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
        let name: i64 = cv_getkey(v_e, "name")
        let typ: i64 = ccs_global_ref(v_self, v_e, ccs_module_name(v_self, name, file, cv_getkey(v_e, "line")))
        if typ != 0: return typ
        ccs_error(cv_cat(cv_text("неизвестное имя "), cv_format(cv_getkey(v_e, "name"), "r")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_e, "SizeAlignExpr"):
        v_typ = ccs_resolve_type(v_self, cv_getkey(v_e, "texpr"), CV_FALSE)
        let choice_2: i64 = 0
        if (cv_equal(cv_getkey(v_e, "op"), cv_text("sizeof"))):
            choice_2 = cc_type_size(v_typ)
        else:
            choice_2 = cc_type_align(v_typ)
        v_value = choice_2
        cv_field(v_e, "const_value", v_value)
        return cc_int(CV_TRUE, 515)
    if cv_classes(v_e, "Unary"):
        let logic_4: bool = (cv_equal(cv_getkey(v_e, "op"), cv_text("?"))) and cv_classes(cv_getkey(v_e, "x"), "Call")
        if logic_4:
            let subject_3: i64 = cv_getkey(cv_getkey(v_e, "x"), "name")
            logic_4 = ((cv_equal(subject_3, cv_text("Some")) or cv_equal(subject_3, cv_text("None")) or cv_equal(subject_3, cv_text("Ok")) or cv_equal(subject_3, cv_text("Err"))))
        if (logic_4):
            v_ret_hint = cv_getkey(cv_getkey(v_self, "fn"), "sig_ret")
            if cv_classes(v_ret_hint, "TWrapper"):
                cv_field(cv_getkey(v_e, "x"), "propagation_context", v_ret_hint)
                let subject_5: i64 = cv_getkey(cv_getkey(v_e, "x"), "name")
                if (((cv_equal(subject_5, cv_text("Ok")) or cv_equal(subject_5, cv_text("Err")))) and (cv_equal(cv_getkey(v_ret_hint, "name"), cv_text("Result")))):
                    cv_field(cv_getkey(v_e, "x"), "context_type", v_ret_hint)
                else:
                    if ((cv_equal(cv_getkey(cv_getkey(v_e, "x"), "name"), cv_text("None"))) and (cv_equal(cv_getkey(v_ret_hint, "name"), cv_text("Option")))):
                        cv_field(cv_getkey(v_e, "x"), "context_type", v_ret_hint)
        v_t = ccs_tf(v_self, cv_getkey(v_e, "x"), 0)
        if (cv_equal(cv_getkey(v_e, "op"), cv_text("?"))):
            v_rt = cv_getkey(cv_getkey(v_self, "fn"), "sig_ret")
            if not (cv_classes(v_t, "TWrapper")):
                ccs_error(cv_text("постфиксный ? требует Option или Result"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            let choice_6: i64 = cv_bool(cv_classes(v_rt, "TWrapper"))
            if cv_truth(choice_6):
                choice_6 = cv_bool((cv_equal(cv_getkey(v_rt, "name"), cv_getkey(v_t, "name"))))
            v_compatible = choice_6
            if (cv_truth(v_compatible) and (cv_equal(cv_getkey(v_t, "name"), cv_text("Option")))):
                v_compatible = cv_bool((cv_equal(cv_subscript(cv_getkey(v_rt, "args"), 3), cv_subscript(cv_getkey(v_t, "args"), 3))))
            if (cv_truth(v_compatible) and (cv_equal(cv_getkey(v_t, "name"), cv_text("Result")))):
                v_compatible = cv_bool((cv_equal(cv_subscript(cv_getkey(v_rt, "args"), 11), cv_subscript(cv_getkey(v_t, "args"), 11))))
            if not (cv_truth(v_compatible)):
                ccs_error(cv_text("? несовместим с типом результата функции"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            cv_field(v_e, "wrapper_type", v_t)
            let payload: i64 = cv_at(cv_getkey(v_t, "args"), 0)
            if cv_classes(payload, "TStruct") or cc_is_tagged_value(payload):
                cv_field(v_e, "temp_slot", ccs_declare_temp(v_self, payload, cv_getkey(v_e, "line")))
            return payload
        if (cv_equal(cv_getkey(v_e, "op"), cv_text("-"))):
            if cv_classes(v_t, "TEnum"):
                ccs_error(cv_text("унарный '-' не поддерживает enum"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if (cv_classes(cv_getkey(v_e, "x"), "IntLit") and (cv_equal(cv_getkey(cv_getkey(v_e, "x"), "val"), cv_shl(11, 507)))):
                return cc_int(CV_TRUE, 515)
            if (cv_classes(cv_getkey(v_e, "x"), "IntLit") and (cv_less(cv_shl(11, 507), cv_getkey(cv_getkey(v_e, "x"), "val")))):
                ccs_error(cv_text("целочисленный литерал выходит за диапазон i64"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if cv_truth(cc_is_int(v_t)):
                return v_t
            if cv_truth(cc_is_float(v_t)):
                return v_t
            ccs_error(cv_text("unary '-' требует число"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        if (cv_equal(cv_getkey(v_e, "op"), cv_text("not"))):
            ccs_truthy_check(v_self, v_t, v_e)
            return cc_TBool()
    if cv_classes(v_e, "Binary"):
        v_l = ccs_tf(v_self, cv_getkey(v_e, "l"), 0)
        v_r = ccs_tf(v_self, cv_getkey(v_e, "r"), 0)
        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("+"))) and cv_truth(cc_is_string(v_l)) and cv_truth(cc_is_string(v_r))):
            cv_field(v_e, "sugar", cv_pair(cv_text("str_concat"), 3))
            return cv_getkey(v_self, "_string")
        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("*"))) and cv_truth(cc_is_string(v_l)) and cv_truth(cc_is_int(v_r))):
            cv_field(v_e, "sugar", cv_pair(cv_text("str_repeat"), 3))
            return cv_getkey(v_self, "_string")
        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("*"))) and cv_truth(cc_is_int(v_l)) and cv_truth(cc_is_string(v_r))):
            cv_field(v_e, "sugar", cv_pair(cv_text("str_repeat"), 11))
            return cv_getkey(v_self, "_string")
        let v_op: i64 = cv_getkey(v_e, "op")
        let v_equality: bool = cv_name(v_op, "==") or cv_name(v_op, "!=")
        let v_comparison: bool = v_equality or cv_name(v_op, "<") or cv_name(v_op, "<=") or cv_name(v_op, ">") or cv_name(v_op, ">=")
        let v_cmp: i64 = 0
        if v_comparison: v_cmp = cc_comparison_kind(v_l, v_r, v_equality)
        if v_cmp == CC_CMP_STRING:
            cv_field(v_e, "sugar", cv_pair(cv_text("str_eq"), 3))
            cv_field(v_e, "negate_sugar", cv_bool(cv_name(v_op, "!=")))
            return cc_TBool()
        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("+"))) and cv_truth(cc_is_ptr(v_l)) and cv_truth(cc_is_ptr(v_r)) and cv_classes(cv_getkey(v_l, "elem"), "TInt") and (cv_equal(cv_getkey(cv_getkey(v_l, "elem"), "bits"), 67)) and cv_classes(cv_getkey(v_r, "elem"), "TInt") and (cv_equal(cv_getkey(cv_getkey(v_r, "elem"), "bits"), 67))):
            ccs_require_unsafe(v_self, v_e, cv_text("операция со строковым raw-указателем"))
            cv_field(v_e, "sugar", cv_pair(cv_text("str_concat"), 3))
            return cv_getkey(v_self, "_ptr_char")
        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("*"))) and cv_truth(cc_is_ptr(v_l)) and cv_truth(cc_is_int(v_r)) and cv_classes(cv_getkey(v_l, "elem"), "TInt") and (cv_equal(cv_getkey(cv_getkey(v_l, "elem"), "bits"), 67))):
            ccs_require_unsafe(v_self, v_e, cv_text("операция со строковым raw-указателем"))
            cv_field(v_e, "sugar", cv_pair(cv_text("str_repeat"), 3))
            return cv_getkey(v_self, "_ptr_char")
        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("*"))) and cv_truth(cc_is_int(v_l)) and cv_truth(cc_is_ptr(v_r)) and cv_classes(cv_getkey(v_r, "elem"), "TInt") and (cv_equal(cv_getkey(cv_getkey(v_r, "elem"), "bits"), 67))):
            ccs_require_unsafe(v_self, v_e, cv_text("операция со строковым raw-указателем"))
            cv_field(v_e, "sugar", cv_pair(cv_text("str_repeat"), 11))
            return cv_getkey(v_self, "_ptr_char")
        if (cv_classes(v_l, "TEnum") or cv_classes(v_r, "TEnum")):
            if v_cmp == CC_CMP_ENUM:
                cv_field(v_e, "cmp_common", cc_int(CV_TRUE, 515))
                return cc_TBool()
            let pieces_9: i64 = cv_list()
            cv_push(pieces_9, cv_text("enum можно сравнивать только через ==/!= с тем же типом ("))
            cv_push(pieces_9, cv_format(cc_display(v_l), ""))
            cv_push(pieces_9, cv_text(", "))
            cv_push(pieces_9, cv_format(cc_display(v_r), ""))
            cv_push(pieces_9, cv_text(")"))
            ccs_error(cv_join(cv_text(""), pieces_9), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let subject_10: i64 = cv_getkey(v_e, "op")
        if ((cv_equal(subject_10, cv_text("and")) or cv_equal(subject_10, cv_text("or")))):
            ccs_truthy_check(v_self, v_l, v_e)
            ccs_truthy_check(v_self, v_r, v_e)
            cv_field(v_e, "type", cc_TBool())
            return cc_TBool()
        if v_comparison:
            if v_cmp == CC_CMP_INT or v_cmp == CC_CMP_FLOAT:
                v_common = cc_num_widen(v_l, v_r)
                if not cv_truth(v_common): v_common = v_l
                cv_field(v_e, "cmp_common", v_common)
                cv_field(v_e, "common", v_common)
                return cc_TBool()
            if v_cmp == CC_CMP_PTR: return cc_TBool()
            if cv_truth(cc_is_num(v_l)) and cv_truth(cc_is_num(v_r)):
                ccs_error(cv_text("сравнение int/float: приведите через as"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if cv_truth(cc_is_ptr(v_l)) and cv_truth(cc_is_ptr(v_r)):
                ccs_error(cv_text("сравнение указателей разных типов"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if ((cv_truth(cc_is_int(v_l)) and cv_truth(cc_is_ptr(v_r))) or (cv_truth(cc_is_ptr(v_l)) and cv_truth(cc_is_int(v_r)))):
                ccs_error(cv_text("сравнение указателя с числом не разрешено"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            let pieces_13: i64 = cv_list()
            cv_push(pieces_13, cv_text("несравнимые типы "))
            cv_push(pieces_13, cv_format(cc_display(v_l), ""))
            cv_push(pieces_13, cv_text(" и "))
            cv_push(pieces_13, cv_format(cc_display(v_r), ""))
            ccs_error(cv_join(cv_text(""), pieces_13), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let subject_14: i64 = cv_getkey(v_e, "op")
        if ((cv_equal(subject_14, cv_text("+")) or cv_equal(subject_14, cv_text("-")) or cv_equal(subject_14, cv_text("*")) or cv_equal(subject_14, cv_text("/")) or cv_equal(subject_14, cv_text("%")) or cv_equal(subject_14, cv_text("&")) or cv_equal(subject_14, cv_text("|")) or cv_equal(subject_14, cv_text("^")) or cv_equal(subject_14, cv_text("<<")) or cv_equal(subject_14, cv_text(">>")))):
            if (cv_truth(cc_is_ptr(v_l)) and cv_truth(cc_is_ptr(v_r))):
                ccs_error(cv_text("указатель-указатель не разрешён"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if (cv_truth(cc_is_ptr(v_l)) and cv_truth(cc_is_int(v_r))):
                let subject_15: i64 = cv_getkey(v_e, "op")
                if (not ((cv_equal(subject_15, cv_text("+")) or cv_equal(subject_15, cv_text("-"))))):
                    let pieces_16: i64 = cv_list()
                    cv_push(pieces_16, cv_text("'"))
                    cv_push(pieces_16, cv_format(cv_getkey(v_e, "op"), ""))
                    cv_push(pieces_16, cv_text("' с указателем не разрешён"))
                    ccs_error(cv_join(cv_text(""), pieces_16), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                    return 0
                ccs_require_unsafe(v_self, v_e, cv_text("арифметика raw-указателей"))
                ccs_ensure_layout(v_self, cv_getkey(v_l, "elem"))
                cv_field(v_e, "common", v_l)
                return v_l
            if (cv_truth(cc_is_ptr(v_r)) and cv_truth(cc_is_int(v_l))):
                if (not (cv_equal(cv_getkey(v_e, "op"), cv_text("+")))):
                    let pieces_17: i64 = cv_list()
                    cv_push(pieces_17, cv_text("'"))
                    cv_push(pieces_17, cv_format(cv_getkey(v_e, "op"), ""))
                    cv_push(pieces_17, cv_text("' с указателем не разрешён"))
                    ccs_error(cv_join(cv_text(""), pieces_17), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                    return 0
                ccs_require_unsafe(v_self, v_e, cv_text("арифметика raw-указателей"))
                ccs_ensure_layout(v_self, cv_getkey(v_r, "elem"))
                cv_field(v_e, "common", v_r)
                return v_r
            let subject_18: i64 = cv_getkey(v_e, "op")
            let logic_20: bool = ((cv_equal(subject_18, cv_text("&")) or cv_equal(subject_18, cv_text("|")) or cv_equal(subject_18, cv_text("^"))))
            if not logic_20:
                let subject_19: i64 = cv_getkey(v_e, "op")
                logic_20 = ((cv_equal(subject_19, cv_text("<<")) or cv_equal(subject_19, cv_text(">>"))))
            if (logic_20):
                if not ((cv_truth(cc_is_int(v_l)) and cv_truth(cc_is_int(v_r)))):
                    let pieces_21: i64 = cv_list()
                    cv_push(pieces_21, cv_text("операция '"))
                    cv_push(pieces_21, cv_format(cv_getkey(v_e, "op"), ""))
                    cv_push(pieces_21, cv_text("' требует целые"))
                    ccs_error(cv_join(cv_text(""), pieces_21), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                    return 0
                if (cv_truth(cc_is_ptr(v_l)) or cv_truth(cc_is_ptr(v_r))):
                    ccs_error(cv_text("битовые операции над указателями запрещены"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                    return 0
                if (cv_truth(cc_is_bool(v_l)) or cv_truth(cc_is_bool(v_r))):
                    ccs_error(cv_text("битовые операции над bool не разрешены"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                    return 0
                let subject_22: i64 = cv_getkey(v_e, "op")
                if ((cv_equal(subject_22, cv_text("<<")) or cv_equal(subject_22, cv_text(">>")))):
                    cv_field(v_e, "common", v_l)
                    return v_l
                let choice_23: i64 = cc_num_widen(v_l, v_r)
                if not cv_truth(choice_23):
                    choice_23 = v_l
                cv_field(v_e, "common", choice_23)
                return cv_getkey(v_e, "common")
            if (not (cv_truth(cc_is_num(v_l))) or not (cv_truth(cc_is_num(v_r)))):
                let pieces_24: i64 = cv_list()
                cv_push(pieces_24, cv_text("арифметика над "))
                cv_push(pieces_24, cv_format(cc_display(v_l), ""))
                cv_push(pieces_24, cv_text(" и "))
                cv_push(pieces_24, cv_format(cc_display(v_r), ""))
                cv_push(pieces_24, cv_text(" недопустима"))
                ccs_error(cv_join(cv_text(""), pieces_24), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if ((cv_truth(cc_is_int(v_l)) and cv_truth(cc_is_float(v_r))) or (cv_truth(cc_is_float(v_l)) and cv_truth(cc_is_int(v_r)))):
                ccs_error(cv_text("int и float в арифметике: приведите через as"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            v_common = cc_num_widen(v_l, v_r)
            if (v_common == 0):
                let pieces_25: i64 = cv_list()
                cv_push(pieces_25, cv_text("арифметика над "))
                cv_push(pieces_25, cv_format(cc_display(v_l), ""))
                cv_push(pieces_25, cv_text(" и "))
                cv_push(pieces_25, cv_format(cc_display(v_r), ""))
                cv_push(pieces_25, cv_text(" недопустима"))
                ccs_error(cv_join(cv_text(""), pieces_25), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if ((cv_equal(cv_getkey(v_e, "op"), cv_text("%"))) and cv_truth(cc_is_float(v_common))):
                ccs_error(cv_text("% требует целые числа"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            cv_field(v_e, "common", v_common)
            return v_common
    if cv_classes(v_e, "CharLit"):
        return cc_k_char_type
    if cv_classes(v_e, "Call"):
        return ccs_t_call(v_self, v_e)
    if cv_classes(v_e, "Index"):
        v_bt = ccs_tf(v_self, cv_getkey(v_e, "base"), 0)
        v_it = ccs_tf(v_self, cv_getkey(v_e, "idx"), 0)
        if (not (cv_truth(cc_is_int(v_it))) or cv_classes(v_it, "TEnum")):
            ccs_error(cv_text("индекс должен быть целым"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        ccs_want_indexable(v_self, cv_getkey(v_e, "base"), v_bt)
        if cv_truth(cc_is_array(v_bt)):
            # The index can itself borrow the owner before the element is accessed.
            ccs_check_exclusive_owner(v_self, ccs_borrow_base(cv_getkey(v_e, "base")))
            cv_field(v_e, "tarr", v_bt)
            return cv_getkey(v_bt, "elem")
        if cv_truth(cc_is_string(v_bt)):
            cv_field(v_e, "tstr", CV_TRUE)
            return cc_k_char_type
        if cv_classes(v_bt, "TSlice"):
            return cv_getkey(v_bt, "elem")
        if cv_truth(cc_is_ptr(v_bt)):
            ccs_require_unsafe(v_self, v_e, cv_text("индексация raw-указателя"))
            ccs_ensure_layout(v_self, cv_getkey(v_bt, "elem"))
            cv_field(v_e, "tarr", v_bt)
            return cv_getkey(v_bt, "elem")
        let pieces_26: i64 = cv_list()
        cv_push(pieces_26, cv_text("базу "))
        cv_push(pieces_26, cv_format(cc_display(v_bt), ""))
        cv_push(pieces_26, cv_text(" нельзя индексировать"))
        ccs_error(cv_join(cv_text(""), pieces_26), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_e, "SliceExpr"):
        let v_base: i64 = cv_getkey(v_e, "base")
        v_bt = ccs_tf(v_self, v_base, 0)
        let v_mutable: i64 = cv_getkey(v_e, "mutable")
        let v_owner: i64 = 0
        let v_raw: bool = false
        if cv_classes(v_bt, "TArray") and cv_classes(v_base, "VarRef"):
            v_owner = cv_getkey(v_base, "slot")
        elif not cv_truth(v_mutable) and cv_classes(v_bt, "TSlice") and not cc_is_mut_slice(v_bt):
            v_owner = ccs_slice_origin(v_base)
        elif not cv_truth(v_mutable) and cv_classes(v_bt, "TSlice"):
            # Read-only re-slice of a []mut T: freeze the handle against writes
            # until the end of this block, like any other lexical loan.
            v_owner = ccs_slice_origin(v_base)
            if v_owner != 0 and cv_classes(v_base, "VarRef"):
                cv_add_set(cv_getkey(v_self, "frozen_mut_slots"), cv_getkey(v_base, "slot"))
        elif not cv_truth(v_mutable) and cv_truth(cc_is_ptr(v_bt)) and not cc_is_owned_ptr(v_bt):
            # Срез от raw-указателя не имеет лексического источника: unsafe сам
            # отвечает за границы и время жизни. Хранить такой срез в let нельзя —
            # только вернуть из функции с from по адресу владельца.
            ccs_require_unsafe(v_self, v_e, cv_text("срез от raw-указателя"))
            ccs_ensure_layout(v_self, cv_getkey(v_bt, "elem"))
            v_raw = true
        if v_owner == 0 and not v_raw:
            ccs_error(cv_text("slice source должен быть локальным массивом или неизменяемым slice с известным источником"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let unpack_27: i64 = cv_pair(ccs_tf(v_self, cv_getkey(v_e, "start"), 0), ccs_tf(v_self, cv_getkey(v_e, "end"), 0))
        v_st = cv_at(unpack_27, 0)
        v_et = cv_at(unpack_27, 1)
        if (not (cv_truth(cc_is_int(v_st))) or not (cv_truth(cc_is_int(v_et))) or not (cv_truth(cv_getkey(v_st, "signed"))) or not (cv_truth(cv_getkey(v_et, "signed")))):
            ccs_error(cv_text("границы slice должны быть знаковыми целыми"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        if cv_classes(v_bt, "TArray"):
            ccs_check_exclusive_owner(v_self, v_base)
            # The owner stays reserved until block exit; ccs_note_temp_slice_args
            # shortens the loan to the end of the statement when this slice is a
            # temporary argument of a call that does not return the borrow.
            let v_borrowed: i64 = cv_getkey(v_self, "borrowed_slots")
            if cv_truth(v_mutable):
                if cv_contains(v_borrowed, v_owner):
                    ccs_error(cv_text("нельзя создать изменяемый slice: массив уже заимствован"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                    return 0
                cv_add_set(cv_getkey(v_self, "exclusive_slots"), v_owner)
            cv_add_set(v_borrowed, v_owner)
        cv_field(v_e, "slice_origin", v_owner)
        return cc_TSlice(cv_getkey(v_bt, "elem"), v_mutable)
    if cv_classes(v_e, "Member"):
        let file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
        let line: i64 = cv_getkey(v_e, "line")
        let base: i64 = cv_getkey(v_e, "base")
        let name: i64 = cc_member_path(base)
        if cv_classes(base, "Member") and ccs_find_slot(v_self, cv_getkey(cv_getkey(base, "base"), "name")) != 0: name = 0
        if cv_classes(base, "VarRef") and ccs_find_slot(v_self, name) != 0: name = 0
        if name != 0 and cv_classes(base, "VarRef"):
            let target: i64 = ccs_namespace(v_self, file, name)
            if target != 0:
                let member: i64 = cv_getkey(v_e, "field")
                let constant: i64 = ccs_global_ref(v_self, v_e, ccs_export(target, member, file, line))
                if constant != 0: return constant
                cc_error(cv_cat(cv_text("модуль: имя не является значением: "), member), file, line)
        if name != 0: v_enum = cv_get(cv_getkey(v_self, "enums"), ccs_module_name(v_self, name, file, line), 0)
        if v_enum != 0:
            if (not (cv_contains(cv_getkey(v_enum, "values"), cv_getkey(v_e, "field")))):
                let pieces_28: i64 = cv_list()
                cv_push(pieces_28, cv_text("enum "))
                cv_push(pieces_28, cv_format(cv_getkey(v_enum, "name"), ""))
                cv_push(pieces_28, cv_text(": неизвестный вариант "))
                cv_push(pieces_28, cv_format(cv_getkey(v_e, "field"), "r"))
                ccs_error(cv_join(cv_text(""), pieces_28), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            if cv_classes(v_enum, "TTaggedEnum"):
                let variant: i64 = cv_getkey(v_e, "field")
                if cv_has(cv_getkey(v_enum, "payloads"), variant):
                    ccs_error(cv_text("вариант enum требует один аргумент payload"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                    return 0
                cv_field(v_e, "kindt", cv_text("tagged_ctor"))
                cv_field(v_e, "variant", cv_get(cv_getkey(v_enum, "values"), variant, 0))
                return v_enum
            cv_field(v_e, "enum_value", cv_subscript(cv_getkey(v_enum, "values"), cv_getkey(v_e, "field")))
            cv_field(v_e, "enum_type", v_enum)
            return v_enum
        v_bt = ccs_tf(v_self, cv_getkey(v_e, "base"), 0)
        if not (cv_truth(cc_is_struct(v_bt))):
            if (cv_truth(cc_is_ptr(v_bt)) and cv_classes(cv_getkey(v_bt, "elem"), "TStruct")):
                ccs_require_unsafe(v_self, v_e, cv_text("доступ к структуре через raw-указатель"))
                v_st = cv_getkey(v_bt, "elem")
                cv_field(v_e, "tptr", CV_TRUE)
            else:
                let pieces_29: i64 = cv_list()
                cv_push(pieces_29, cv_text("обращение к ."))
                cv_push(pieces_29, cv_format(cv_getkey(v_e, "field"), ""))
                cv_push(pieces_29, cv_text(" у "))
                cv_push(pieces_29, cv_format(cc_display(v_bt), ""))
                cv_push(pieces_29, cv_text(" не поддерживается"))
                ccs_error(cv_join(cv_text(""), pieces_29), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
        else:
            v_st = v_bt
            cv_field(v_e, "tptr", CV_FALSE)
        if ccs_buffer_type(v_self, v_st, "BorrowBuffer") and not ccs_buffer_module_body(v_self):
            ccs_error(cv_text("BorrowBuffer: поле дескриптора недоступно"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        ccs_opaque_access(v_st, file, line, "приватное поле struct")
        ccs_ensure_layout(v_self, v_st)
        let seq_31: i64 = cv_getkey(v_st, "fields")
        for index_30 in 0..cv_len(seq_31):
            let unpack_32: i64 = cv_at(seq_31, index_30)
            v_fn = cv_at(unpack_32, 0)
            v_ft = cv_at(unpack_32, 1)
            v_off = cv_at(unpack_32, 2)
            v_sz = cv_at(unpack_32, 3)
            if (cv_equal(v_fn, cv_getkey(v_e, "field"))):
                cv_field(v_e, "toff", v_off)
                cv_field(v_e, "styp", v_st)
                cv_field(v_e, "field_type", v_ft)
                return v_ft
        let pieces_33: i64 = cv_list()
        cv_push(pieces_33, cv_text("поле "))
        cv_push(pieces_33, cv_format(cv_getkey(v_e, "field"), "r"))
        cv_push(pieces_33, cv_text(" отсутствует в "))
        cv_push(pieces_33, cv_format(cc_display(v_st), ""))
        ccs_error(cv_join(cv_text(""), pieces_33), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_e, "Cast"):
        v_ft = ccs_tf(v_self, cv_getkey(v_e, "x"), 0)
        v_tt = ccs_resolve_type(v_self, cv_getkey(v_e, "texpr"), CV_FALSE)
        if cc_is_owned(v_ft) or cc_is_owned(v_tt) or cc_is_owned_ptr(v_ft) or cc_is_owned_ptr(v_tt):
            ccs_error(cv_text("приведение OwnedBuffer и его адреса запрещено"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        if cc_is_mut_slice(v_ft) or cc_is_mut_slice(v_tt):
            ccs_error(cv_text("приведение изменяемого slice запрещено"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let choice_34: i64 = cc_is_ptr(v_tt)
        if cv_truth(choice_34):
            choice_34 = cc_is_int(v_ft)
        if cv_truth(choice_34):
            choice_34 = cv_bool(cv_classes(cv_getkey(v_e, "x"), "IntLit"))
        if cv_truth(choice_34):
            choice_34 = cv_bool((cv_equal(cv_getkey(cv_getkey(v_e, "x"), "val"), 3)))
        v_null_pointer = choice_34
        if ((cv_truth(cc_is_ptr(v_ft)) or cv_truth(cc_is_ptr(v_tt))) and (not (cv_equal(v_ft, v_tt))) and not (cv_truth(v_null_pointer))):
            ccs_require_unsafe(v_self, v_e, cv_text("приведение raw-указателя"))
        ccs_chk_cast(v_self, v_ft, v_tt, v_e, CV_TRUE)
        cv_field(v_e, "type", v_tt)
        return v_tt
    if cv_classes(v_e, "Deref"):
        v_bt = ccs_tf(v_self, cv_getkey(v_e, "x"), 0)
        if not (cv_truth(cc_is_ptr(v_bt))):
            ccs_error(cv_cat(cv_text("* требует указатель, получен "), cv_format(cc_display(v_bt), "")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        ccs_require_unsafe(v_self, v_e, cv_text("разыменование raw-указателя"))
        ccs_ensure_layout(v_self, cv_getkey(v_bt, "elem"))
        return cv_getkey(v_bt, "elem")
    if cv_classes(v_e, "AddrOf"):
        v_t = ccs_tf(v_self, cv_getkey(v_e, "x"), 0)
        if cv_classes(v_t, "TWrapper"):
            ccs_error(cv_text("ptr не может скрывать Option/Result"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        if cv_classes(v_t, "TTaggedEnum"):
            ccs_error(cv_text("ptr не может скрывать enum с payload"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        ccs_want_lvalue_node(v_self, cv_getkey(v_e, "x"), v_t)
        if cc_is_mut_slice(v_t):
            ccs_error(cv_text("нельзя взять адрес дескриптора изменяемого slice"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let v_place: i64 = ccs_borrow_base(cv_getkey(v_e, "x"))
        if cv_classes(cv_getkey(v_place, "type"), "TSlice"):
            ccs_require_unsafe(v_self, v_e, cv_text("взятие raw-адреса slice"))
        return cc_TPtr(v_t)
    if cv_classes(v_e, "ArrayLit"):
        ccs_error(cv_text("список массивов нельзя вычислять как значение"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_e, "StructLit"):
        ccs_error(cv_text("переменная структуры не выражение"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    ccs_error(cv_add(cv_text("неизвестный узел "), cv_typename(v_e)), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
    return 0

unsafe fn ccs_truthy_check(v_self: i64, v_t: i64, v_e: i64) -> i64:
    if v_t == 0:
        ccs_error(cv_text("void нельзя использовать как условие"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_t, "TWrapper"):
        ccs_error(cv_text("Option/Result в условии всегда истинен (адрес); используйте match или postfix ?"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_t, "TTaggedEnum"):
        ccs_error(cv_text("enum с payload нельзя использовать в условии; используйте match"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if (cv_truth(cc_is_struct(v_t)) or cv_truth(cc_is_array(v_t))):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("условие из "))
        cv_push(pieces_1, cv_format(cc_display(v_t), ""))
        cv_push(pieces_1, cv_text(" не имеет смысла"))
        ccs_error(cv_join(cv_text(""), pieces_1), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    return 0

unsafe fn ccs_want_indexable(v_self: i64, v_base: i64, v_bt: i64) -> i64:
    if (cv_truth(cc_is_array(v_bt)) or cv_truth(cc_is_ptr(v_bt)) or cv_truth(cc_is_string(v_bt)) or cv_classes(v_bt, "TSlice")):
        return 0
    ccs_error(cv_cat(cv_format(cc_display(v_bt), ""), cv_text(" не индексируется")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_base)
    return 0

unsafe fn ccs_want_lvalue_node(v_self: i64, v_e: i64, v_t: i64) -> i64:
    if cv_classes(v_e, "VarRef"):
        return 0
    if cv_classes(v_e, "Member"):
        if cv_has(v_e, cv_text("enum_value")):
            ccs_error(cv_text("вариант enum нельзя изменить или взять по адресу"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        return 0
    if cv_classes(v_e, "Index"):
        return 0
    if cv_classes(v_e, "Deref"):
        return 0
    ccs_error(cv_text("нельзя взять адрес этого выражения"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
    return 0

unsafe fn ccs_chk_cast(v_self: i64, v_a: i64, v_b: i64, v_e: i64, v_explicit: i64) -> i64:
    if (cv_equal(v_a, v_b)):
        return CV_TRUE
    if (cv_truth(cc_is_string(v_a)) or cv_truth(cc_is_string(v_b))):
        if (cv_truth(v_explicit) and ((cv_truth(cc_is_string(v_a)) and cv_truth(cc_is_ptr(v_b)) and (cv_equal(cv_getkey(v_b, "elem"), cc_k_char_type))) or (cv_truth(cc_is_ptr(v_a)) and (cv_equal(cv_getkey(v_a, "elem"), cc_k_char_type)) and cv_truth(cc_is_string(v_b))))):
            return CV_TRUE
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("нельзя привести "))
        cv_push(pieces_1, cv_format(cc_display(v_a), ""))
        cv_push(pieces_1, cv_text(" к "))
        cv_push(pieces_1, cv_format(cc_display(v_b), ""))
        ccs_error(cv_join(cv_text(""), pieces_1), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if (cv_classes(v_a, "TEnum") or cv_classes(v_b, "TEnum")):
        if (cv_truth(v_explicit) and cv_classes(v_a, "TEnum") and not (cv_classes(v_b, "TEnum")) and cv_truth(cc_is_int(v_b))):
            return CV_TRUE
        let pieces_2: i64 = cv_list()
        cv_push(pieces_2, cv_text("нельзя привести "))
        cv_push(pieces_2, cv_format(cc_display(v_a), ""))
        cv_push(pieces_2, cv_text(" к "))
        cv_push(pieces_2, cv_format(cc_display(v_b), ""))
        ccs_error(cv_join(cv_text(""), pieces_2), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if (cv_truth(cc_is_num(v_a)) and cv_truth(cc_is_num(v_b))):
        return CV_TRUE
    # An explicit unsafe cast can attach a signature to a raw address, e.g. from dlsym.
    if cv_truth(cc_is_ptr(v_a)) and (cv_truth(cc_is_ptr(v_b)) or (cv_truth(v_explicit) and cv_classes(v_b, "TFnPtr"))):
        return CV_TRUE
    if (cv_truth(cc_is_ptr(v_a)) and cv_truth(cc_is_int(v_b)) and (cv_equal(cv_getkey(v_b, "bits"), 515))):
        return CV_TRUE
    if (cv_truth(cc_is_int(v_a)) and (cv_equal(cv_getkey(v_a, "bits"), 515)) and cv_truth(cc_is_ptr(v_b))):
        return CV_TRUE
    if (cv_truth(cc_is_bool(v_a)) and cv_truth(cc_is_int(v_b))):
        return CV_TRUE
    let pieces_3: i64 = cv_list()
    cv_push(pieces_3, cv_text("нельзя привести "))
    cv_push(pieces_3, cv_format(cc_display(v_a), ""))
    cv_push(pieces_3, cv_text(" к "))
    cv_push(pieces_3, cv_format(cc_display(v_b), ""))
    ccs_error(cv_join(cv_text(""), pieces_3), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
    return 0

unsafe fn ccs_is_callback_builtin(v_self: i64, v_name: i64) -> i64:
    let choice_1: i64 = cv_bool((cv_equal(v_name, cv_text("callback"))))
    if cv_truth(choice_1):
        choice_1 = cv_bool((not (cv_contains(cv_getkey(v_self, "fns"), v_name))))
    if cv_truth(choice_1):
        choice_1 = cv_bool((not (cv_contains(cv_getkey(v_self, "generic_fns"), v_name))))
    if cv_truth(choice_1):
        choice_1 = cv_bool((not (cv_contains(cv_getkey(v_self, "struct_defs"), v_name))))
    return choice_1

unsafe fn ccs_check_mut_slice_args(v_self: i64, v_e: i64):
    let v_args: i64 = cv_getkey(v_e, "args")
    for i in 0..cv_len(v_args):
        let v_arg: i64 = cv_at(v_args, i)
        let v_typ: i64 = cv_getkey(v_arg, "type")
        # Struct arguments are copied by the callee after all arguments are evaluated.
        if cv_truth(cc_is_struct(v_typ)):
            ccs_check_exclusive_owner(v_self, ccs_borrow_base(v_arg))
        if not cc_is_mut_slice(v_typ): continue
        if cv_classes(v_arg, "SliceExpr"): continue
        let v_slot: i64 = cv_getkey(v_arg, "slot")
        if not cv_classes(v_arg, "VarRef") or v_slot == 0:
            ccs_error(cv_text("аргумент []mut должен быть именем изменяемого slice или диапазоном локального массива"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arg)
        if cv_contains(cv_getkey(v_self, "frozen_mut_slots"), v_slot):
            ccs_error(cv_text("изменяемый slice нельзя передать как []mut, пока из него создан slice на чтение"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arg)
        for j in 0..i:
            if cv_getkey(cv_at(v_args, j), "slot") == v_slot:
                ccs_error(cv_text("изменяемый slice нельзя передать дважды в один вызов"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arg)

unsafe fn ccs_note_temp_slice_args(v_self: i64, v_e: i64, v_loan_mark: i64, v_freeze_mark: i64):
    # A slice expression written directly in argument position borrows its owner
    # only until the end of the enclosing statement; a named slice keeps the
    # loan until block exit, and a `from` result inherits the argument's loan.
    # Loans created while checking a defer action are excluded: defer holds
    # them until the block exits, as before.
    if cv_getkey(v_self, "defer_action_depth") != 0: return
    let v_result_origin: i64 = cv_get(v_e, cv_text("slice_origin"), 0)
    let v_borrowed: i64 = cv_getkey(v_self, "borrowed_slots")
    let v_frozen: i64 = cv_getkey(v_self, "frozen_mut_slots")
    let v_pending: i64 = cv_getkey(v_self, "temp_slice_releases")
    let v_args: i64 = cv_getkey(v_e, "args")
    for index_1 in 0..cv_len(v_args):
        let v_arg: i64 = cv_at(v_args, index_1)
        if not cv_classes(v_arg, "SliceExpr"): continue
        let v_owner: i64 = cv_get(v_arg, cv_text("slice_origin"), 0)
        if v_owner == 0: continue
        if v_result_origin != 0 and cv_equal(v_result_origin, v_owner): continue
        let v_base: i64 = cv_getkey(v_arg, "base")
        let v_bt: i64 = cv_get(v_base, cv_text("type"), 0)
        if cv_classes(v_bt, "TArray"):
            # Only a loan that this call introduced may end with the statement.
            if v_loan_mark <= cv_pos(v_borrowed, v_owner):
                cv_push(v_pending, cv_pair(v_borrowed, v_owner))
                if cv_truth(cv_getkey(v_arg, "mutable")):
                    cv_push(v_pending, cv_pair(cv_getkey(v_self, "exclusive_slots"), v_owner))
        elif cv_classes(v_bt, "TSlice") and cc_is_mut_slice(v_bt) and cv_classes(v_base, "VarRef"):
            let v_slot: i64 = cv_getkey(v_base, "slot")
            if v_freeze_mark <= cv_pos(v_frozen, v_slot):
                cv_push(v_pending, cv_pair(v_frozen, v_slot))
    return

unsafe fn ccs_apply_temp_slice_releases(v_self: i64):
    let v_pending: i64 = cv_getkey(v_self, "temp_slice_releases")
    for index_1 in 0..cv_len(v_pending):
        let v_entry: i64 = cv_at(v_pending, index_1)
        cv_remove(cv_at(v_entry, 0), cv_at(v_entry, 1))
    while cv_len(v_pending) > 0: cv_pop(v_pending)
    return

unsafe fn ccs_slice_origin(v_e: i64) -> i64:
    if cv_classes(v_e, "VarRef"):
        let v_slot: i64 = cv_getkey(v_e, "slot")
        if cv_name(cv_getkey(v_slot, "kind"), "param") and cv_classes(cv_getkey(v_slot, "typ"), "TSlice"):
            return v_slot
        return cv_getkey(v_slot, "slice_origin")
    return cv_getkey(v_e, "slice_origin")

unsafe fn ccs_bind_slice_call_result(v_self: i64, v_e: i64, v_fn: i64):
    let v_index: i64 = cv_getkey(v_fn, "ret_source_index")
    if v_index == 0: return
    let v_arg: i64 = cv_subscript(cv_getkey(v_e, "args"), v_index)
    let v_source_param: i64 = cv_subscript(cv_getkey(v_fn, "sig_params"), v_index)
    if cc_is_owned_ptr(cv_at(v_source_param, 1)):
        # Адрес владельца: срез заимствует его слот до конца блока вызова;
        # перенос запрещает проход владения (owner_slice_borrow).
        let v_owner_slot: i64 = 0
        if cv_classes(v_arg, "AddrOf") and cv_classes(cv_getkey(v_arg, "x"), "VarRef"):
            v_owner_slot = cv_getkey(cv_getkey(v_arg, "x"), "slot")
        if v_owner_slot == 0 or not cc_is_owned(cv_getkey(v_owner_slot, "typ")):
            ccs_error(cv_text("аргумент from должен быть адресом локального владельца"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arg)
            return
        cv_field(v_e, "slice_origin", v_owner_slot)
        cv_field(v_e, "owner_slice_borrow", v_owner_slot)
        return
    let v_origin: i64 = ccs_slice_origin(v_arg)
    # A view of an array must still be backed by the caller's lexical owner loan.
    if v_origin == 0 or (cv_classes(cv_getkey(v_origin, "typ"), "TArray") and not cv_contains(cv_getkey(v_self, "borrowed_slots"), v_origin)):
        ccs_error(cv_text("аргумент from должен быть неизменяемым slice с известным источником"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arg)
        return
    cv_field(v_e, "slice_origin", v_origin)

unsafe fn ccs_t_indirect_call(v_self: i64, v_e: i64, slot: i64) -> i64:
    let name: i64 = cv_getkey(v_e, "name")
    let file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
    let line: i64 = cv_getkey(v_e, "line")
    let signature: i64 = cv_getkey(slot, "typ")
    if not cv_classes(signature, "TFnPtr"):
        cc_error(cv_mod(cv_text("%s: вызов требует fnptr, получен %s"), cv_pair(name, cc_display(signature))), file, line)
        return 0
    ccs_require_unsafe(v_self, v_e, cv_text("косвенный вызов fnptr"))
    let args: i64 = cv_getkey(v_e, "args")
    let params: i64 = cv_getkey(signature, "params")
    if cv_len(args) != cv_len(params):
        let detail: i64 = cv_mod(cv_text(": %d аргумента(ов), ожидалось %d"), cv_pair(cv_length(args), cv_length(params)))
        cc_error(cv_cat(name, detail), file, line)
        return 0
    for i in 0..cv_len(args):
        let arg: i64 = cv_at(args, i)
        let expected: i64 = cv_at(params, i)
        let actual: i64 = ccs_tf(v_self, arg, expected)
        if not cv_truth(cc_can_assign(actual, expected)):
            let prefix: i64 = cv_mod(cv_text("%s: аргумент %d: "), cv_pair(name, cv_i(i + 1)))
            let detail: i64 = cv_mod(cv_text("%s вместо %s"), cv_pair(cc_display(actual), cc_display(expected)))
            cc_error(cv_cat(prefix, detail), file, cv_getkey(arg, "line"))
            return 0
    let callee: i64 = cc_VarRef(name, line)
    cv_field(callee, "slot", slot)
    cv_field(callee, "type", signature)
    cv_field(v_e, "indirect_callee", callee)
    return cv_getkey(signature, "result")

unsafe fn ccs_t_enum_ctor(v_self: i64, expr: i64) -> i64:
    let file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
    let line: i64 = cv_getkey(expr, "line")
    let qualifier: i64 = ccs_module_name(v_self, cv_getkey(expr, "call_qualifier"), file, line)
    let member: i64 = cv_getkey(expr, "call_member")
    let typ: i64 = cv_get(cv_getkey(v_self, "enums"), qualifier, 0)
    if typ == 0 or not cv_has(cv_getkey(typ, "values"), member):
        cc_error(cv_cat(cv_text("неизвестный вариант enum "), cv_getkey(expr, "name")), file, line)
        return 0
    let payload: i64 = cv_get(cv_getkey(typ, "payloads"), member, 0)
    if payload == 0:
        cc_error(cv_text("вариант enum без payload используется без скобок"), file, line)
        return 0
    let args: i64 = cv_getkey(expr, "args")
    if cv_len(args) != 1:
        cc_error(cv_text("вариант enum требует один аргумент payload"), file, line)
        return 0
    let actual: i64 = ccs_tf(v_self, cv_at(args, 0), payload)
    if not cv_equal(actual, payload):
        cc_error(cv_mod(cv_text("вариант enum: %s вместо %s"), cv_pair(cc_display(actual), cc_display(payload))), file, line)
        return 0
    cv_field(expr, "kindt", cv_text("tagged_ctor"))
    cv_field(expr, "variant", cv_get(cv_getkey(typ, "values"), member, 0))
    return typ

unsafe fn ccs_global_ref(state: i64, expr: i64, name: i64) -> i64:
    let binding: i64 = cv_get(cv_getkey(state, "const_globals"), name, 0)
    if binding != 0:
        cv_field(expr, "const_binding", binding)
        return cv_at(binding, 0)
    let global: i64 = cv_get(cv_getkey(state, "globals"), name, 0)
    if global != 0:
        cv_field(expr, "kind", cv_text("glob"))
        cv_field(expr, "name", name)
        return cv_getkey(global, "glob_type")
    return 0

unsafe fn ccs_prepare_array_length(v_self: i64, v_e: i64):
    # len does not copy the array, but reaching it can evaluate a temporary record.
    let base: i64 = v_e
    while base != 0:
        if cv_classes(base, "Member") or cv_classes(base, "Index"):
            base = cv_getkey(base, "base")
        elif cv_classes(base, "Cast"):
            cv_field(base, "array_len_address", CV_TRUE)
            base = cv_getkey(base, "x")
        else:
            if cv_classes(base, "Call") and cv_name(cv_getkey(base, "kindt"), "ctor"):
                cv_field(base, "array_len_address", CV_TRUE)
                cv_field(base, "temp_slot", ccs_declare_temp(v_self, cv_getkey(base, "type"), cv_getkey(base, "line")))
            return

unsafe fn ccs_t_call(v_self: i64, v_e: i64) -> i64:
    let v_name: i64 = 0
    let v_target: i64 = 0
    let v_signature: i64 = 0
    let v_payload: i64 = 0
    let v_hint: i64 = 0
    let v_result: i64 = 0
    let v_propagation_hint: i64 = 0
    let v_expected: i64 = 0
    let v_definition: i64 = 0
    let v_sd: i64 = 0
    let v_inferred: i64 = 0
    let v_types: i64 = 0
    let v_a: i64 = 0
    let v_fn_: i64 = 0
    let v_ft: i64 = 0
    let v_off: i64 = 0
    let v_sz: i64 = 0
    let v_at: i64 = 0
    let v_source: i64 = 0
    let v_fn: i64 = 0
    let v_arg: i64 = 0
    let v_param_name: i64 = 0
    let v_param_type: i64 = 0
    let v_pn: i64 = 0
    let v_pt: i64 = 0
    let v_kinds: i64 = 0
    let v_ret: i64 = 0
    let v_label: i64 = 0
    let v_i: i64 = 0
    let v_k: i64 = 0
    let v_ta: i64 = 0
    let v_tb: i64 = 0
    let v_common: i64 = 0
    let v_ok: i64 = 0
    let file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
    let line: i64 = cv_getkey(v_e, "line")
    let qualifier: i64 = cv_getkey(v_e, "call_qualifier")
    if qualifier != 0:
        let target: i64 = ccs_namespace(v_self, file, qualifier)
        if target == 0: return ccs_t_enum_ctor(v_self, v_e)
        v_name = ccs_export(target, cv_getkey(v_e, "call_member"), file, line)
    else:
        v_name = ccs_module_name(v_self, cv_getkey(v_e, "name"), file, line)
    cv_field(v_e, "name", v_name)
    if cv_truth(cv_getkey(v_self, "has_owned")):
        let v_drop_kind: i64 = cc_owner_kind_of_drop(v_self, v_name)
        if v_drop_kind != 0:
            cc_error(cv_cat(cv_text("drop "), cv_cat(cv_getkey(v_drop_kind, "title"), cv_text(" выполняется автоматически"))), file, line)
    if cv_truth(ccs_is_callback_builtin(v_self, v_name)):
        ccs_require_unsafe(v_self, v_e, cv_text("callback"))
        if ((not (cv_equal(cv_length(cv_getkey(v_e, "args")), 11))) or not (cv_classes(cv_subscript(cv_getkey(v_e, "args"), 3), "VarRef"))):
            ccs_error(cv_text("callback ожидает имя функции VOLT"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let callback_name: i64 = ccs_module_name(v_self, cv_getkey(cv_at(cv_getkey(v_e, "args"), 0), "name"), file, line)
        v_target = cv_get(cv_getkey(v_self, "fns"), callback_name, 0)
        if ((v_target == 0) or (cv_getkey(v_target, "body") == 0) or (not (cv_getkey(v_target, "native") == 0))):
            ccs_error(cv_text("callback ожидает обычную необобщённую функцию VOLT"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let collect_1: i64 = cv_vector(CV_LIST)
        let seq_3: i64 = cv_getkey(v_target, "sig_params")
        for index_2 in 0..cv_len(seq_3):
            let unpack_4: i64 = cv_at(seq_3, index_2)
            let t_5: i64 = cv_at(unpack_4, 1)
            cv_push(collect_1, t_5)
        v_signature = ccs_callback_type(v_self, cv_astuple(collect_1), cv_getkey(v_target, "sig_ret"), cv_getkey(cv_getkey(v_self, "fn"), "file"), cv_getkey(v_e, "line"))
        cv_field(v_e, "callback_target", v_target)
        return v_signature
    if ((cv_equal(v_name, cv_text("Some")) or cv_equal(v_name, cv_text("Ok")) or cv_equal(v_name, cv_text("Err")))):
        if (not (cv_equal(cv_length(cv_getkey(v_e, "args")), 11))):
            ccs_error(cv_cat(cv_format(v_name, ""), cv_text(": ожидается один payload")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        v_hint = cv_get(v_e, cv_text("context_type"), 0)
        if cv_classes(v_hint, "TWrapper"):
            let args: i64 = cv_getkey(v_hint, "args")
            if cv_name(v_name, "Some") and cv_name(cv_getkey(v_hint, "name"), "Option"):
                v_expected = cv_at(args, 0)
            elif cv_name(cv_getkey(v_hint, "name"), "Result"):
                if cv_name(v_name, "Ok"): v_expected = cv_at(args, 0)
                if cv_name(v_name, "Err"): v_expected = cv_at(args, 1)
        v_payload = ccs_tf(v_self, cv_at(cv_getkey(v_e, "args"), 0), v_expected)
        let owned_ok: bool = (cv_name(v_name, "Ok") and cc_is_owned_result(v_hint) and cv_equal(v_payload, v_expected)) or (cv_name(v_name, "Some") and cc_is_owned_struct(v_payload))
        if not owned_ok and not cc_allowed_payload(v_payload):
            let pieces_8: i64 = cv_list()
            cv_push(pieces_8, cv_format(v_name, ""))
            cv_push(pieces_8, cv_text(": недопустимый тип payload "))
            cv_push(pieces_8, cv_format(cc_display(v_payload), ""))
            ccs_error(cv_join(cv_text(""), pieces_8), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        if (cv_equal(v_name, cv_text("Some"))):
            let choice_9: i64 = 0
            if (cv_classes(v_hint, "TWrapper") and (cv_equal(cv_getkey(v_hint, "name"), cv_text("Option")))):
                choice_9 = v_hint
            else:
                let items_10: i64 = cv_vector(CV_TUPLE)
                cv_push(items_10, v_payload)
                choice_9 = ccs_wrapper_type(v_self, cv_text("Option"), items_10, cv_getkey(cv_getkey(v_self, "fn"), "file"), cv_getkey(v_e, "line"), CV_FALSE)
            v_result = choice_9
            if (not (cv_equal(cv_subscript(cv_getkey(v_result, "args"), 3), v_payload))):
                let pieces_11: i64 = cv_list()
                cv_push(pieces_11, cv_text("Some: "))
                cv_push(pieces_11, cv_format(cc_display(v_payload), ""))
                cv_push(pieces_11, cv_text(" вместо "))
                cv_push(pieces_11, cv_format(cc_display(cv_subscript(cv_getkey(v_result, "args"), 3)), ""))
                ccs_error(cv_join(cv_text(""), pieces_11), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            cv_field(v_e, "kindt", cv_text("wrapper_ctor"))
            cv_field(v_e, "variant", 11)
            return v_result
        if (not (cv_classes(v_hint, "TWrapper")) or (not (cv_equal(cv_getkey(v_hint, "name"), cv_text("Result"))))):
            v_propagation_hint = cv_get(v_e, cv_text("propagation_context"), 0)
            if (not (cv_classes(v_propagation_hint, "TWrapper")) or (not (cv_equal(cv_getkey(v_propagation_hint, "name"), cv_text("Result"))))):
                ccs_error(cv_cat(cv_format(v_name, ""), cv_text(" требует контекста Result<T, E>")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            let choice_12: i64 = 0
            if (cv_equal(v_name, cv_text("Ok"))):
                choice_12 = cv_subscript(cv_getkey(v_propagation_hint, "args"), 3)
            else:
                choice_12 = cv_subscript(cv_getkey(v_propagation_hint, "args"), 11)
            v_expected = choice_12
            if (not (cv_equal(v_payload, v_expected))):
                let pieces_13: i64 = cv_list()
                cv_push(pieces_13, cv_format(v_name, ""))
                cv_push(pieces_13, cv_text(": "))
                cv_push(pieces_13, cv_format(cc_display(v_payload), ""))
                cv_push(pieces_13, cv_text(" вместо "))
                cv_push(pieces_13, cv_format(cc_display(v_expected), ""))
                ccs_error(cv_join(cv_text(""), pieces_13), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
                return 0
            cv_field(v_e, "kindt", cv_text("wrapper_ctor"))
            let choice_14: i64 = 0
            if (cv_equal(v_name, cv_text("Ok"))):
                choice_14 = 3
            else:
                choice_14 = 11
            cv_field(v_e, "variant", choice_14)
            return v_propagation_hint
        let choice_15: i64 = 0
        if (cv_equal(v_name, cv_text("Ok"))):
            choice_15 = cv_subscript(cv_getkey(v_hint, "args"), 3)
        else:
            choice_15 = cv_subscript(cv_getkey(v_hint, "args"), 11)
        v_expected = choice_15
        if (not (cv_equal(v_payload, v_expected))):
            let pieces_16: i64 = cv_list()
            cv_push(pieces_16, cv_format(v_name, ""))
            cv_push(pieces_16, cv_text(": "))
            cv_push(pieces_16, cv_format(cc_display(v_payload), ""))
            cv_push(pieces_16, cv_text(" вместо "))
            cv_push(pieces_16, cv_format(cc_display(v_expected), ""))
            ccs_error(cv_join(cv_text(""), pieces_16), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        cv_field(v_e, "kindt", cv_text("wrapper_ctor"))
        let choice_17: i64 = 0
        if (cv_equal(v_name, cv_text("Ok"))):
            choice_17 = 3
        else:
            choice_17 = 11
        cv_field(v_e, "variant", choice_17)
        return v_hint
    if (cv_equal(v_name, cv_text("None"))):
        v_hint = cv_get(v_e, cv_text("context_type"), 0)
        if (not (cv_classes(v_hint, "TWrapper")) or (not (cv_equal(cv_getkey(v_hint, "name"), cv_text("Option"))))):
            ccs_error(cv_text("None требует контекста Option<T>"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        cv_field(v_e, "kindt", cv_text("wrapper_ctor"))
        cv_field(v_e, "variant", 3)
        return v_hint
    if (cv_contains(cv_getkey(v_self, "struct_defs"), v_name)):
        v_definition = cv_subscript(cv_getkey(v_self, "struct_defs"), v_name)
        if cv_name(v_name, "OwnedBuffer") and cv_truth(cv_getkey(v_self, "has_owned")) and not cv_equal(file, cv_getkey(v_self, "owned_buffer_file")):
            cc_error(cv_text("приватный конструктор OwnedBuffer"), file, line)
        if cv_truth(cv_getkey(v_definition, "opaque")) and not cv_equal(cv_getkey(v_definition, "file"), file):
            cc_error(cv_text("приватный конструктор struct"), file, line)
        if (not (cv_equal(cv_length(cv_getkey(v_e, "args")), cv_length(cv_getkey(v_definition, "fields"))))):
            let pieces_18: i64 = cv_list()
            cv_push(pieces_18, cv_format(v_name, ""))
            cv_push(pieces_18, cv_text(": "))
            cv_push(pieces_18, cv_format(cv_length(cv_getkey(v_e, "args")), ""))
            cv_push(pieces_18, cv_text(" значений вместо "))
            cv_push(pieces_18, cv_format(cv_length(cv_getkey(v_definition, "fields")), ""))
            cv_push(pieces_18, cv_text(" полей"))
            ccs_error(cv_join(cv_text(""), pieces_18), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        v_sd = cv_get(v_e, cv_text("context_type"), 0)
        v_inferred = CV_FALSE
        if (not (cv_truth(cc_is_struct(v_sd))) or (not (cv_equal(cv_getkey(v_sd, "name"), v_name)))):
            let items_19: i64 = cv_vector(CV_TUPLE)
            v_types = items_19
            if cv_truth(cv_getkey(v_definition, "type_params")):
                let collect_20: i64 = cv_vector(CV_LIST)
                let seq_22: i64 = cv_getkey(v_definition, "fields")
                for index_21 in 0..cv_len(seq_22):
                    let unpack_23: i64 = cv_at(seq_22, index_21)
                    let ft_24: i64 = cv_at(unpack_23, 1)
                    cv_push(collect_20, ft_24)
                let options_25: i64 = cv_tuple()
                cv_push(options_25, cv_getkey(v_e, "line"))
                cv_push(options_25, CV_TRUE)
                v_types = ccs_infer_type_args(v_self, cv_getkey(v_definition, "type_params"), collect_20, cv_getkey(v_e, "args"), cv_getkey(cv_getkey(v_self, "fn"), "file"), options_25)
                v_inferred = CV_TRUE
            v_sd = ccs_struct_type(v_self, v_name, v_types, cv_getkey(cv_getkey(v_self, "fn"), "file"), cv_getkey(v_e, "line"), CV_FALSE)
        let seq_27: i64 = cv_zip(cv_getkey(v_e, "args"), cv_getkey(v_sd, "fields"))
        for index_26 in 0..cv_len(seq_27):
            let unpack_28: i64 = cv_at(seq_27, index_26)
            v_a = cv_at(unpack_28, 0)
            let unpack_29: i64 = cv_at(unpack_28, 1)
            v_fn_ = cv_at(unpack_29, 0)
            v_ft = cv_at(unpack_29, 1)
            v_off = cv_at(unpack_29, 2)
            v_sz = cv_at(unpack_29, 3)
            let choice_30: i64 = 0
            if cv_truth(v_inferred):
                choice_30 = cv_getkey(v_a, "type")
            else:
                choice_30 = ccs_tf(v_self, v_a, v_ft)
            v_at = choice_30
            if (v_at == 0):
                let pieces_31: i64 = cv_list()
                cv_push(pieces_31, cv_format(v_name, ""))
                cv_push(pieces_31, cv_text("."))
                cv_push(pieces_31, cv_format(v_fn_, ""))
                cv_push(pieces_31, cv_text(": для аргумента требуется значение"))
                ccs_error(cv_join(cv_text(""), pieces_31), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                return 0
            if not (cv_truth(cc_can_assign(v_at, v_ft))):
                let pieces_32: i64 = cv_list()
                cv_push(pieces_32, cv_format(v_name, ""))
                cv_push(pieces_32, cv_text("."))
                cv_push(pieces_32, cv_format(v_fn_, ""))
                cv_push(pieces_32, cv_text(": "))
                cv_push(pieces_32, cv_format(cc_display(v_at), ""))
                cv_push(pieces_32, cv_text(" вместо "))
                cv_push(pieces_32, cv_format(cc_display(v_ft), ""))
                ccs_error(cv_join(cv_text(""), pieces_32), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                return 0
        cv_field(v_e, "kindt", cv_text("ctor"))
        return v_sd
    if (cv_contains(cv_getkey(v_self, "generic_fns"), v_name)):
        v_source = cv_subscript(cv_getkey(v_self, "generic_fns"), v_name)
        if cv_truth(cv_getkey(v_source, "is_unsafe")):
            ccs_require_unsafe(v_self, v_e, cv_cat(cv_text("вызов unsafe-функции "), cv_format(v_name, "")))
        let v_caller_file: i64 = cv_getkey(v_e, "file")
        if v_caller_file == 0: v_caller_file = cv_getkey(cv_getkey(v_self, "fn"), "file")
        v_fn = ccs_instantiate_generic(v_self, v_source, cv_getkey(v_e, "args"), v_caller_file, cv_getkey(v_e, "line"))
        cv_field(v_e, "generic_fn", v_fn)
        let seq_34: i64 = cv_zip(cv_getkey(v_e, "args"), cv_getkey(v_fn, "sig_params"))
        for index_33 in 0..cv_len(seq_34):
            let unpack_35: i64 = cv_at(seq_34, index_33)
            v_arg = cv_at(unpack_35, 0)
            let unpack_36: i64 = cv_at(unpack_35, 1)
            v_param_name = cv_at(unpack_36, 0)
            v_param_type = cv_at(unpack_36, 1)
            if (not (cv_equal(cv_getkey(v_arg, "type"), v_param_type))):
                let pieces_37: i64 = cv_list()
                cv_push(pieces_37, cv_format(v_name, ""))
                cv_push(pieces_37, cv_text(": аргумент '"))
                cv_push(pieces_37, cv_format(v_param_name, ""))
                cv_push(pieces_37, cv_text("': "))
                cv_push(pieces_37, cv_format(cc_display(cv_getkey(v_arg, "type")), ""))
                cv_push(pieces_37, cv_text(" вместо "))
                cv_push(pieces_37, cv_format(cc_display(v_param_type), ""))
                ccs_error(cv_join(cv_text(""), pieces_37), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arg)
                return 0
            if (cv_truth(cc_is_struct(cv_getkey(v_arg, "type"))) and (cv_equal(cv_get(v_arg, cv_text("kindt"), 0), cv_text("ctor")))):
                cv_field(v_arg, "temp_slot", ccs_declare_temp(v_self, cv_getkey(v_arg, "type"), cv_getkey(v_arg, "line")))
        if cv_truth(cc_is_struct(cv_getkey(v_fn, "sig_ret"))):
            cv_field(v_e, "temp_slot", ccs_declare_temp(v_self, cv_getkey(v_fn, "sig_ret"), cv_getkey(v_e, "line")))
        ccs_bind_slice_call_result(v_self, v_e, v_fn)
        return cv_getkey(v_fn, "sig_ret")
    if (cv_contains(cv_getkey(v_self, "fns"), v_name)):
        v_fn = cv_subscript(cv_getkey(v_self, "fns"), v_name)
        if cv_truth(cv_getkey(v_fn, "is_unsafe")):
            ccs_require_unsafe(v_self, v_e, cv_cat(cv_text("вызов unsafe-функции "), cv_format(v_name, "")))
        if (not (cv_equal(cv_length(cv_getkey(v_e, "args")), cv_length(cv_getkey(v_fn, "sig_params"))))):
            let pieces_38: i64 = cv_list()
            cv_push(pieces_38, cv_format(v_name, ""))
            cv_push(pieces_38, cv_text(": "))
            cv_push(pieces_38, cv_format(cv_length(cv_getkey(v_e, "args")), ""))
            cv_push(pieces_38, cv_text(" аргумента вместо "))
            cv_push(pieces_38, cv_format(cv_length(cv_getkey(v_fn, "params")), ""))
            ccs_error(cv_join(cv_text(""), pieces_38), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let seq_40: i64 = cv_zip(cv_getkey(v_e, "args"), cv_getkey(v_fn, "sig_params"))
        for index_39 in 0..cv_len(seq_40):
            let unpack_41: i64 = cv_at(seq_40, index_39)
            v_a = cv_at(unpack_41, 0)
            let unpack_42: i64 = cv_at(unpack_41, 1)
            v_pn = cv_at(unpack_42, 0)
            v_pt = cv_at(unpack_42, 1)
            let logic_44: bool = cv_classes(v_pt, "TWrapper") and cv_classes(v_a, "Call")
            if logic_44:
                let subject_43: i64 = cv_getkey(v_a, "name")
                logic_44 = ((cv_equal(subject_43, cv_text("Some")) or cv_equal(subject_43, cv_text("None")) or cv_equal(subject_43, cv_text("Ok")) or cv_equal(subject_43, cv_text("Err"))))
            if (logic_44):
                cv_field(v_a, "context_type", v_pt)
            v_at = ccs_tf(v_self, v_a, v_pt)
            if cv_classes(v_pt, "TWrapper"):
                if ((not (cv_getkey(v_fn, "native") == 0)) or (cv_getkey(v_fn, "body") == 0)):
                    ccs_error(cv_text("Option/Result параметры запрещены в extern/native"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                    return 0
                if (not (cv_equal(v_at, v_pt))):
                    let pieces_45: i64 = cv_list()
                    cv_push(pieces_45, cv_format(v_name, ""))
                    cv_push(pieces_45, cv_text(": аргумент '"))
                    cv_push(pieces_45, cv_format(v_pn, ""))
                    cv_push(pieces_45, cv_text("': "))
                    cv_push(pieces_45, cv_format(cc_display(v_at), ""))
                    cv_push(pieces_45, cv_text(" вместо "))
                    cv_push(pieces_45, cv_format(cc_display(v_pt), ""))
                    ccs_error(cv_join(cv_text(""), pieces_45), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                    return 0
                if cv_name(cv_getkey(v_a, "kindt"), "wrapper_ctor") and cv_getkey(v_a, "temp_slot") == 0:
                    cv_field(v_a, "temp_slot", ccs_declare_temp(v_self, v_at, cv_getkey(v_a, "line")))
                continue
            if (cv_truth(cc_is_struct(v_at)) and cv_classes(v_a, "Call") and (cv_equal(cv_get(v_a, cv_text("kindt"), 0), cv_text("ctor")))):
                cv_field(v_a, "temp_slot", ccs_declare_temp(v_self, v_at, cv_getkey(v_a, "line")))
            if (cv_equal(v_at, v_pt)):
                0
            else:
                if (cv_classes(v_at, "TEnum") or cv_classes(v_pt, "TEnum")):
                    let pieces_46: i64 = cv_list()
                    cv_push(pieces_46, cv_format(v_name, ""))
                    cv_push(pieces_46, cv_text(": аргумент '"))
                    cv_push(pieces_46, cv_format(v_pn, ""))
                    cv_push(pieces_46, cv_text("': "))
                    cv_push(pieces_46, cv_format(cc_display(v_at), ""))
                    cv_push(pieces_46, cv_text(" вместо "))
                    cv_push(pieces_46, cv_format(cc_display(v_pt), ""))
                    ccs_error(cv_join(cv_text(""), pieces_46), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                    return 0
                else:
                    if (cv_truth(cc_is_num(v_at)) and cv_truth(cc_is_num(v_pt))):
                        continue
                    else:
                        let pieces_47: i64 = cv_list()
                        cv_push(pieces_47, cv_format(v_name, ""))
                        cv_push(pieces_47, cv_text(": аргумент '"))
                        cv_push(pieces_47, cv_format(v_pn, ""))
                        cv_push(pieces_47, cv_text("': "))
                        cv_push(pieces_47, cv_format(cc_display(v_at), ""))
                        cv_push(pieces_47, cv_text(" вместо "))
                        cv_push(pieces_47, cv_format(cc_display(v_pt), ""))
                        ccs_error(cv_join(cv_text(""), pieces_47), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                        return 0
        if (cv_classes(cv_getkey(v_fn, "sig_ret"), "TWrapper") and ((not (cv_getkey(v_fn, "native") == 0)) or (cv_getkey(v_fn, "body") == 0))):
            ccs_error(cv_text("Option/Result результаты запрещены в extern/native"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        if cv_truth(cc_is_struct(cv_getkey(v_fn, "sig_ret"))):
            cv_field(v_e, "temp_slot", ccs_declare_temp(v_self, cv_getkey(v_fn, "sig_ret"), cv_getkey(v_e, "line")))
        if cv_getkey(v_fn, "body") == 0 and cv_getkey(v_fn, "native") == 0:
            cv_field(v_e, "c_extern", CV_TRUE)
        ccs_bind_slice_call_result(v_self, v_e, v_fn)
        return cv_getkey(v_fn, "sig_ret")
    if (cv_contains(cc_k_irtis, v_name)):
        let unpack_48: i64 = cv_subscript(cc_k_irtis, v_name)
        v_kinds = cv_at(unpack_48, 0)
        v_ret = cv_at(unpack_48, 1)
        v_label = cv_at(unpack_48, 2)
        if ((cv_equal(v_name, cv_text("write")) or cv_equal(v_name, cv_text("write_all")) or cv_equal(v_name, cv_text("read")) or cv_equal(v_name, cv_text("mmap")) or cv_equal(v_name, cv_text("munmap")) or cv_equal(v_name, cv_text("brk")))):
            ccs_require_unsafe(v_self, v_e, cv_cat(cv_text("системный вызов "), cv_format(v_name, "")))
        if (not (cv_equal(cv_length(cv_getkey(v_e, "args")), cv_length(v_kinds)))):
            let pieces_49: i64 = cv_list()
            cv_push(pieces_49, cv_format(v_name, ""))
            cv_push(pieces_49, cv_text(": "))
            cv_push(pieces_49, cv_format(cv_length(cv_getkey(v_e, "args")), ""))
            cv_push(pieces_49, cv_text(" аргумента(ов), ожидалось "))
            cv_push(pieces_49, cv_format(cv_length(v_kinds), ""))
            ccs_error(cv_join(cv_text(""), pieces_49), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        let seq_51: i64 = cv_enumerate(cv_zip(cv_getkey(v_e, "args"), v_kinds))
        for index_50 in 0..cv_len(seq_51):
            let unpack_52: i64 = cv_at(seq_51, index_50)
            v_i = cv_at(unpack_52, 0)
            let unpack_53: i64 = cv_at(unpack_52, 1)
            v_a = cv_at(unpack_53, 0)
            v_k = cv_at(unpack_53, 1)
            v_at = ccs_tf(v_self, v_a, 0)
            if (cv_equal(v_k, cv_text("i"))):
                if (not (cv_truth(cc_is_int(v_at))) or cv_classes(v_at, "TEnum")):
                    let pieces_54: i64 = cv_list()
                    cv_push(pieces_54, cv_format(v_name, ""))
                    cv_push(pieces_54, cv_text(": аргумент "))
                    cv_push(pieces_54, cv_format(cv_add(v_i, 11), ""))
                    cv_push(pieces_54, cv_text(" должен быть целым"))
                    ccs_error(cv_join(cv_text(""), pieces_54), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                    return 0
            else:
                if (cv_equal(v_k, cv_text("f"))):
                    if not (cv_truth(cc_is_float(v_at))):
                        let pieces_55: i64 = cv_list()
                        cv_push(pieces_55, cv_format(v_name, ""))
                        cv_push(pieces_55, cv_text(": аргумент "))
                        cv_push(pieces_55, cv_format(cv_add(v_i, 11), ""))
                        cv_push(pieces_55, cv_text(" должен быть float"))
                        ccs_error(cv_join(cv_text(""), pieces_55), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                        return 0
                else:
                    if (cv_equal(v_k, cv_text("p"))):
                        if cv_truth(cc_is_string(v_at)):
                            continue
                        if not ((cv_truth(cc_is_ptr(v_at)) and cv_classes(cv_getkey(v_at, "elem"), "TInt") and (cv_equal(cv_getkey(cv_getkey(v_at, "elem"), "bits"), 67)))):
                            let pieces_56: i64 = cv_list()
                            cv_push(pieces_56, cv_format(v_name, ""))
                            cv_push(pieces_56, cv_text(": аргумент "))
                            cv_push(pieces_56, cv_format(cv_add(v_i, 11), ""))
                            cv_push(pieces_56, cv_text(" должен быть ptr<char>"))
                            ccs_error(cv_join(cv_text(""), pieces_56), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                            return 0
                        ccs_require_unsafe(v_self, v_a, cv_cat(cv_text("передача raw-указателя в "), cv_format(v_name, "")))
                    else:
                        if (cv_equal(v_k, cv_text("n"))):
                            if (not (cv_truth(cc_is_num(v_at))) or cv_classes(v_at, "TEnum")):
                                let pieces_57: i64 = cv_list()
                                cv_push(pieces_57, cv_format(v_name, ""))
                                cv_push(pieces_57, cv_text(": аргумент "))
                                cv_push(pieces_57, cv_format(cv_add(v_i, 11), ""))
                                cv_push(pieces_57, cv_text(" должен быть числом"))
                                ccs_error(cv_join(cv_text(""), pieces_57), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                                return 0
                        else:
                            if (cv_equal(v_k, cv_text("a"))):
                                if (not (cv_truth(cc_is_array(v_at))) and not (((cv_equal(v_name, cv_text("len"))) and cv_classes(v_at, "TSlice")))):
                                    let pieces_58: i64 = cv_list()
                                    cv_push(pieces_58, cv_format(v_name, ""))
                                    cv_push(pieces_58, cv_text(": аргумент "))
                                    cv_push(pieces_58, cv_format(cv_add(v_i, 11), ""))
                                    cv_push(pieces_58, cv_text(" должен быть массивом или slice"))
                                    ccs_error(cv_join(cv_text(""), pieces_58), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                                    return 0
                                if cv_name(v_name, "len") and cv_classes(v_at, "TArray"): ccs_prepare_array_length(v_self, v_a)
        if ((cv_equal(v_name, cv_text("abs")) or cv_equal(v_name, cv_text("min")) or cv_equal(v_name, cv_text("max")))):
            v_ta = cv_getkey(cv_subscript(cv_getkey(v_e, "args"), 3), "type")
            let choice_59: i64 = 0
            if (cv_less(11, cv_length(cv_getkey(v_e, "args")))):
                choice_59 = cv_getkey(cv_subscript(cv_getkey(v_e, "args"), 11), "type")
            else:
                choice_59 = 0
            v_tb = choice_59
            if ((not (v_tb == 0)) and (not (cv_equal(v_tb, v_ta)))):
                if (cv_truth(cc_is_num(v_ta)) and cv_truth(cc_is_num(v_tb))):
                    v_common = cc_num_widen(v_ta, v_tb)
                    if (v_common == 0):
                        let pieces_60: i64 = cv_list()
                        cv_push(pieces_60, cv_format(v_name, ""))
                        cv_push(pieces_60, cv_text(": типы "))
                        cv_push(pieces_60, cv_format(cc_display(v_ta), ""))
                        cv_push(pieces_60, cv_text(" и "))
                        cv_push(pieces_60, cv_format(cc_display(v_tb), ""))
                        cv_push(pieces_60, cv_text(" несовместимы"))
                        ccs_error(cv_join(cv_text(""), pieces_60), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                        return 0
                    cv_field(v_e, "common_w", v_common)
                else:
                    let pieces_61: i64 = cv_list()
                    cv_push(pieces_61, cv_format(v_name, ""))
                    cv_push(pieces_61, cv_text(": типы "))
                    cv_push(pieces_61, cv_format(cc_display(v_ta), ""))
                    cv_push(pieces_61, cv_text(" и "))
                    cv_push(pieces_61, cv_format(cc_display(v_tb), ""))
                    cv_push(pieces_61, cv_text(" несовместимы"))
                    ccs_error(cv_join(cv_text(""), pieces_61), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                    return 0
            else:
                cv_field(v_e, "common_w", 0)
        if ((cv_equal(v_name, cv_text("len"))) and (cv_equal(cv_length(cv_getkey(v_e, "args")), 11)) and cv_classes(cv_getkey(cv_subscript(cv_getkey(v_e, "args"), 3), "type"), "TSlice")):
            cv_field(v_e, "len_slice", CV_TRUE)
        if (cv_equal(v_ret, cv_text("i"))):
            return cc_int(CV_TRUE, 515)
        if (cv_equal(v_ret, cv_text("f"))):
            return cc_TFloat(515)
        if (cv_equal(v_ret, cv_text("p"))):
            return cv_getkey(v_self, "_ptr_char")
        if (cv_equal(v_ret, cv_text("n"))):
            return cv_getkey(cv_subscript(cv_getkey(v_e, "args"), 3), "type")
        if (v_ret == 0):
            if cv_name(v_label, "VOLT_rt_panic") or cv_name(v_label, "VOLT_rt_exit"):
                cv_field(v_e, "no_return", CV_TRUE)
            return 0
        ccs_error(cv_text("внутр: неизвестный ret-код"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if (cv_equal(v_name, cv_text("print"))):
        let seq_63: i64 = cv_getkey(v_e, "args")
        for index_62 in 0..cv_len(seq_63):
            v_a = cv_at(seq_63, index_62)
            v_at = ccs_tf(v_self, v_a, 0)
            let choice_64: i64 = cc_is_int(v_at)
            if not cv_truth(choice_64):
                choice_64 = cc_is_float(v_at)
            if not cv_truth(choice_64):
                choice_64 = cc_is_bool(v_at)
            if not cv_truth(choice_64):
                choice_64 = cc_is_string(v_at)
            if not cv_truth(choice_64):
                let choice_65: i64 = cc_is_ptr(v_at)
                if cv_truth(choice_65):
                    choice_65 = cv_bool(cv_classes(cv_getkey(v_at, "elem"), "TInt"))
                if cv_truth(choice_65):
                    choice_65 = cv_bool((cv_equal(cv_getkey(cv_getkey(v_at, "elem"), "bits"), 67)))
                choice_64 = choice_65
            v_ok = choice_64
            if not (cv_truth(v_ok)):
                ccs_error(cv_cat(cv_text("print не поддерживает тип "), cv_format(cc_display(v_at), "")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_a)
                return 0
            if cv_truth(cc_is_ptr(v_at)):
                ccs_require_unsafe(v_self, v_a, cv_text("печать raw-указателя"))
        return 0
    # Keep existing functions, constructors and builtins ahead of local call targets.
    let slot: i64 = ccs_find_slot(v_self, v_name)
    if slot != 0: return ccs_t_indirect_call(v_self, v_e, slot)
    ccs_error(cv_cat(cv_text("неизвестная функция "), cv_format(v_name, "r")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
    return 0

unsafe fn ccs_buffer_function(v_self: i64, v_name: i64) -> bool:
    # Constructors take precedence over functions in the ordinary call resolver.
    return not cv_has(cv_getkey(v_self, "struct_defs"), v_name) and ccs_buffer_module_def(v_self, "generic_fns", v_name)

unsafe fn ccs_buffer_check_call(v_self: i64, v_e: i64):
    let v_name: i64 = cv_getkey(v_e, "name")
    if cv_name(v_name, "BorrowBuffer") or cv_name(v_name, "BufferRead"):
        if ccs_buffer_module_def(v_self, "struct_defs", v_name) and not ccs_buffer_module_body(v_self):
            let v_file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
            let v_line: i64 = cv_getkey(v_e, "line")
            if cv_name(v_name, "BufferRead"):
                ccs_buffer_view_type_error(v_file, v_line)
            else:
                cc_error(cv_text("BorrowBuffer: создавайте дескриптор через borrow_buffer_new"), v_file, v_line)
        return
    let v_acquire: bool = cv_name(v_name, "borrow_buffer_read")
    let v_release: bool = cv_name(v_name, "__volt_buffer_read_end")
    if not (v_acquire or v_release or cv_name(v_name, "buffer_read_len") or cv_name(v_name, "buffer_read_get")): return
    if not ccs_buffer_function(v_self, v_name): return
    if (v_acquire or v_release) and not cv_truth(cv_getkey(v_e, "buffer_read_generated")):
        let v_file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
        let v_line: i64 = cv_getkey(v_e, "line")
        if v_acquire: cc_error(cv_text("borrow_buffer_read требует отдельного let"), v_file, v_line)
        if v_release: cc_error(cv_text("завершение заимствования автоматическое"), v_file, v_line)
    let v_args: i64 = cv_getkey(v_e, "args")
    if v_acquire or cv_len(v_args) == 0: return
    let v_arg: i64 = cv_at(v_args, 0)
    if cv_classes(v_arg, "VarRef"): cv_field(v_arg, "buffer_read_argument", CV_TRUE)

unsafe fn ccs_buffer_read_defers(v_self: i64, v_stmts: i64):
    if not ccs_buffer_function(v_self, cv_text("borrow_buffer_read")): return
    let v_expanded: i64 = 0
    for i in 0..cv_len(v_stmts):
        let v_st: i64 = cv_at(v_stmts, i)
        let v_init: i64 = cv_getkey(v_st, "init")
        if cv_classes(v_st, "LetStmt") and cv_classes(v_init, "Call") and cv_name(cv_getkey(v_init, "name"), "borrow_buffer_read"):
            let v_file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
            let v_line: i64 = cv_getkey(v_st, "line")
            let v_args: i64 = cv_getkey(v_init, "args")
            if cv_len(v_args) != 1 or not cv_classes(cv_at(v_args, 0), "VarRef"):
                cc_error(cv_text("borrow_buffer_read ожидает имя владельца"), v_file, v_line)
                return
            let v_end: i64 = cv_text("__volt_buffer_read_end")
            if not ccs_buffer_function(v_self, v_end):
                cc_error(cv_text("недоступно завершение заимствования BorrowBuffer"), v_file, v_line)
                return
            if v_expanded == 0: v_expanded = cv_slice(v_stmts, cv_i(0), cv_i(i))
            # Register in this block immediately after acquisition, before later user defers.
            cv_field(v_init, "buffer_read_generated", CV_TRUE)
            let v_cleanup_args: i64 = cv_list()
            cv_push(v_cleanup_args, cc_VarRef(cv_getkey(v_st, "name"), v_line))
            let v_cleanup: i64 = cc_Call(v_end, v_cleanup_args, v_line)
            cv_field(v_cleanup, "buffer_read_generated", CV_TRUE)
            cv_push(v_expanded, v_st)
            cv_push(v_expanded, cc_DeferStmt(cc_ExprStmt(v_cleanup, v_line), v_line))
        elif v_expanded != 0:
            cv_push(v_expanded, v_st)
    if v_expanded != 0:
        while cv_len(v_stmts) > 0: cv_pop(v_stmts)
        cv_extend(v_stmts, v_expanded)

unsafe fn ccs_typecheck_stmts(v_self: i64, v_stmts: i64) -> i64:
    ccs_buffer_read_defers(v_self, v_stmts)
    let v_frame: i64 = 0
    let v_old_future: i64 = 0
    let v_st: i64 = 0
    let v_flag_name: i64 = 0
    let v_borrows: i64 = cv_getkey(v_self, "borrowed_slots")
    let v_borrow_count: i64 = cv_len(v_borrows)
    let v_exclusive: i64 = cv_getkey(v_self, "exclusive_slots")
    let v_exclusive_count: i64 = cv_len(v_exclusive)
    let v_frozen: i64 = cv_getkey(v_self, "frozen_mut_slots")
    let v_frozen_count: i64 = cv_len(v_frozen)
    cv_push(cv_getkey(v_self, "scope"), cv_dict())
    cv_push(cv_getkey(v_self, "const_scope"), cv_dict())
    let items_1: i64 = cv_vector(CV_LIST)
    v_frame = items_1
    cv_push(cv_getkey(v_self, "defer_stack"), v_frame)
    v_old_future = cv_getkey(v_self, "future_local_names")
    let collect_2: i64 = cv_vector(CV_SET)
    let seq_4: i64 = v_stmts
    for index_3 in 0..cv_len(seq_4):
        let st_5: i64 = cv_at(seq_4, index_3)
        if not (cv_classes(st_5, "LetStmt") or cv_classes(st_5, "ConstStmt")): continue
        cv_add_set(collect_2, cv_getkey(st_5, "name"))
    cv_field(v_self, "future_local_names", cv_or(v_old_future, collect_2))
    let seq_7: i64 = v_stmts
    for index_6 in 0..cv_len(seq_7):
        v_st = cv_at(seq_7, index_6)
        if cv_classes(v_st, "LetStmt") or cv_classes(v_st, "ConstStmt"):
            cv_remove(cv_getkey(v_self, "future_local_names"), cv_getkey(v_st, "name"))
        ccs_typecheck_st(v_self, v_st)
        # Temporary slice arguments of this statement's calls end their loans here.
        ccs_apply_temp_slice_releases(v_self)
    # Deferred owner accesses also see loans introduced after their registration.
    for i in 0..cv_len(v_frame):
        let v_defer: i64 = cv_at(v_frame, i)
        let v_owner_uses: i64 = cv_getkey(v_defer, "owner_uses")
        let v_own_loans: i64 = cv_getkey(v_defer, "exclusive_loans")
        for j in 0..cv_len(v_owner_uses):
            let v_use: i64 = cv_at(v_owner_uses, j)
            if not cv_contains(v_own_loans, cv_getkey(v_use, "slot")):
                ccs_check_exclusive_owner(v_self, v_use)
        let v_action: i64 = cv_getkey(v_defer, "action")
        if cv_classes(v_action, "AssignStmt"):
            ccs_check_lvalue(v_self, cv_getkey(v_action, "target"))
    # The set only appends newly borrowed slots; ancestor loans stay active.
    while cv_len(v_borrows) > v_borrow_count:
        cv_pop(v_borrows)
    while cv_len(v_exclusive) > v_exclusive_count:
        cv_pop(v_exclusive)
    while cv_len(v_frozen) > v_frozen_count:
        cv_pop(v_frozen)
    cv_pop(cv_getkey(v_self, "defer_stack"))
    cv_field(v_self, "future_local_names", v_old_future)
    let seq_9: i64 = v_stmts
    for index_8 in 0..cv_len(seq_9):
        v_st = cv_at(seq_9, index_8)
        if cv_classes(v_st, "DeferStmt"):
            v_flag_name = cv_add(cv_text("$defer"), cv_str(cv_getkey(v_self, "defer_name_counter")))
            cv_field(v_self, "defer_name_counter", cv_add(cv_getkey(v_self, "defer_name_counter"), 11))
            cv_field(v_st, "flag_slot", ccs_declare(v_self, v_flag_name, cc_int(CV_FALSE, 515), CV_TRUE, cv_getkey(v_st, "line"), cv_text("defer")))
            cv_field(v_self, "defer_serial", cv_add(cv_getkey(v_self, "defer_serial"), 11))
    # Drop only this block's names, including its hidden defer flags.
    cv_pop(cv_getkey(v_self, "const_scope"))
    cv_pop(cv_getkey(v_self, "scope"))
    let seq_16: i64 = v_stmts
    for index_15 in 0..cv_len(seq_16):
        v_st = cv_at(seq_16, index_15)
        cv_field(v_st, "block_defers", v_frame)
    return 0

unsafe fn ccs_const_lookup(v_self: i64, v_name: i64) -> i64:
    let v_scope: i64 = 0
    let seq_2: i64 = cv_reverse(cv_getkey(v_self, "const_scope"))
    for index_1 in 0..cv_len(seq_2):
        v_scope = cv_at(seq_2, index_1)
        if (cv_contains(v_scope, v_name)):
            return cv_subscript(v_scope, v_name)
    return 0

unsafe fn ccs_typecheck_defer_action(v_self: i64, v_st: i64) -> i64:
    if not (cv_classes(v_st, "AssignStmt") or cv_classes(v_st, "ExprStmt")):
        ccs_error(cv_text("defer допускает только простой оператор без flow-control или вложенного defer"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
        return 0
    # Loans created by the deferred action stay until block exit, so temporary
    # slice arguments inside it must not be scheduled for statement-end release.
    cv_field(v_self, "defer_action_depth", cv_getkey(v_self, "defer_action_depth") + 1)
    ccs_typecheck_st(v_self, v_st)
    cv_field(v_self, "defer_action_depth", cv_getkey(v_self, "defer_action_depth") - 1)
    return 0

unsafe fn ccs_validate_defer_reads(v_self: i64, v_defer: i64) -> i64:
    let v_action: i64 = 0
    v_action = cv_getkey(v_defer, "action")
    cv_field(v_defer, "owner_uses", cv_list())
    if cv_classes(v_action, "AssignStmt"):
        cc_check_expr(v_self, v_defer, cv_getkey(v_action, "target"))
        cc_check_expr(v_self, v_defer, cv_getkey(v_action, "value"))
    else:
        if cv_classes(v_action, "ExprStmt"):
            cc_check_expr(v_self, v_defer, cv_getkey(v_action, "expr"))
    return 0

unsafe fn cc_check_expr(v_self: i64, v_defer: i64, v_expr: i64) -> i64:
    if cv_has(v_expr, cv_text("const_binding")) or cv_has(v_expr, cv_text("enum_value")): return 0
    let v_slot_id: i64 = 0
    let v_slot: i64 = 0
    let v_arg: i64 = 0
    let v_item: i64 = 0
    if (v_expr == 0):
        return 0
    if cv_classes(v_expr, "SliceExpr"):
        cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "base"))
        cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "start"))
        cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "end"))
        return 0
    if cv_classes(v_expr, "VarRef"):
        v_slot_id = cv_get(v_expr, cv_text("slot"), 0)
        # A resolved local is already bound to its visible slot, even if a
        # later declaration has the same name.
        if v_slot_id == 0 and not cv_has(v_expr, cv_text("const_binding")) and cv_contains(cv_getkey(v_self, "future_local_names"), cv_getkey(v_expr, "name")):
            let pieces_1: i64 = cv_list()
            cv_push(pieces_1, cv_text("defer использует локальную переменную "))
            cv_push(pieces_1, cv_format(cv_getkey(v_expr, "name"), ""))
            cv_push(pieces_1, cv_text(", объявленную после defer"))
            ccs_error(cv_join(cv_text(""), pieces_1), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_expr)
            return 0
        let choice_2: i64 = 0
        if cv_classes(v_slot_id, "SlotK"):
            choice_2 = v_slot_id
        else:
            let choice_3: i64 = 0
            if (not (v_slot_id == 0)):
                choice_3 = cv_subscript(cv_getkey(v_self, "slots"), v_slot_id)
            else:
                choice_3 = 0
            choice_2 = choice_3
        v_slot = choice_2
        if cv_classes(cv_getkey(v_slot, "typ"), "TArray"):
            cv_push(cv_getkey(v_defer, "owner_uses"), v_expr)
        if ((not (v_slot == 0)) and (not (cv_contains(cv_getkey(v_defer, "defer_visible_slots"), v_slot)))):
            let pieces_4: i64 = cv_list()
            cv_push(pieces_4, cv_text("defer использует локальную переменную "))
            cv_push(pieces_4, cv_format(cv_getkey(v_expr, "name"), ""))
            cv_push(pieces_4, cv_text(", объявленную после defer"))
            ccs_error(cv_join(cv_text(""), pieces_4), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_expr)
            return 0
        if ((v_slot == 0) and (not (cv_contains(cv_getkey(v_defer, "defer_visible_names"), cv_getkey(v_expr, "name")))) and (not (cv_contains(cv_getkey(v_self, "fn_param_names"), cv_getkey(v_expr, "name")))) and (not (cv_contains(cv_getkey(v_self, "const_globals"), cv_getkey(v_expr, "name")))) and (not (cv_contains(cv_getkey(v_self, "globals"), cv_getkey(v_expr, "name"))))):
            let pieces_5: i64 = cv_list()
            cv_push(pieces_5, cv_text("defer использует имя "))
            cv_push(pieces_5, cv_format(cv_getkey(v_expr, "name"), ""))
            cv_push(pieces_5, cv_text(", не видимое в точке defer"))
            ccs_error(cv_join(cv_text(""), pieces_5), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_expr)
            return 0
    else:
        if cv_classes(v_expr, "Unary"):
            cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "x"))
        else:
            if cv_classes(v_expr, "Binary"):
                cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "l"))
                cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "r"))
            else:
                if cv_classes(v_expr, "Call"):
                    if cv_has(v_expr, cv_text("callback_target")):
                        return 0
                    cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "indirect_callee"))
                    let seq_7: i64 = cv_getkey(v_expr, "args")
                    for index_6 in 0..cv_len(seq_7):
                        v_arg = cv_at(seq_7, index_6)
                        cc_check_expr(v_self, v_defer, v_arg)
                else:
                    if cv_classes(v_expr, "Index"):
                        cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "base"))
                        cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "idx"))
                    else:
                        if cv_classes(v_expr, "Member"):
                            if not cc_is_sum_ctor(v_expr):
                                cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "base"))
                        else:
                            if cv_classes(v_expr, "Cast"):
                                cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "x"))
                            else:
                                if cv_classes(v_expr, "Deref") or cv_classes(v_expr, "AddrOf"):
                                    cc_check_expr(v_self, v_defer, cv_getkey(v_expr, "x"))
                                else:
                                    if cv_classes(v_expr, "ArrayLit"):
                                        let seq_9: i64 = cv_getkey(v_expr, "items")
                                        for index_8 in 0..cv_len(seq_9):
                                            v_item = cv_at(seq_9, index_8)
                                            cc_check_expr(v_self, v_defer, v_item)
    return 0

unsafe fn ccs_typecheck_st(v_self: i64, v_st: i64) -> i64:
    let v_action_exprs: i64 = 0
    let v_expr: i64 = 0
    let v_typ: i64 = 0
    let v_want: i64 = 0
    let v_value: i64 = 0
    let v_lo: i64 = 0
    let v_hi: i64 = 0
    let v_zero_flag: i64 = 0
    let v_items: i64 = 0
    let v_bold: i64 = 0
    let v_elem: i64 = 0
    let v_n: i64 = 0
    let v_init_t: i64 = 0
    let v_it: i64 = 0
    let v_at: i64 = 0
    let v_want_t: i64 = 0
    let v_expected: i64 = 0
    let v_tg: i64 = 0
    let v_rt: i64 = 0
    let v_slot: i64 = 0
    let v_cond: i64 = 0
    let v_body: i64 = 0
    let v_a: i64 = 0
    let v_b: i64 = 0
    let v_vt: i64 = 0
    let v_mt: i64 = 0
    let v_covered: i64 = 0
    let v_wildcard: i64 = 0
    let v_arm: i64 = 0
    let v_p: i64 = 0
    let v_v: i64 = 0
    let v_key: i64 = 0
    let v_variants: i64 = 0
    let v_payload: i64 = 0
    if cv_classes(v_st, "DeferStmt"):
        let choice_1: i64 = 0
        if cv_classes(cv_getkey(v_st, "action"), "AssignStmt"):
            let items_2: i64 = cv_vector(CV_LIST)
            cv_push(items_2, cv_getkey(cv_getkey(v_st, "action"), "target"))
            cv_push(items_2, cv_getkey(cv_getkey(v_st, "action"), "value"))
            choice_1 = items_2
        else:
            let choice_3: i64 = 0
            if cv_classes(cv_getkey(v_st, "action"), "ExprStmt"):
                let items_4: i64 = cv_vector(CV_LIST)
                cv_push(items_4, cv_getkey(cv_getkey(v_st, "action"), "expr"))
                choice_3 = items_4
            else:
                let items_5: i64 = cv_vector(CV_LIST)
                choice_3 = items_5
            choice_1 = choice_3
        v_action_exprs = choice_1
        let seq_7: i64 = v_action_exprs
        for index_6 in 0..cv_len(seq_7):
            v_expr = cv_at(seq_7, index_6)
            cc_precheck_expr(v_self, v_expr)
        cv_field(v_st, "defer_scope", cv_sub(cv_length(cv_getkey(v_self, "defer_stack")), 11))
        cv_field(v_st, "defer_outer_slot_count", cv_length(cv_getkey(v_self, "slots")))
        let collect_8: i64 = cv_vector(CV_LIST)
        let seq_10: i64 = cv_getkey(v_self, "scope")
        for index_9 in 0..cv_len(seq_10):
            let scope_11: i64 = cv_at(seq_10, index_9)
            let seq_13: i64 = scope_11
            for index_12 in 0..cv_len(seq_13):
                let name_14: i64 = cv_at(seq_13, index_12)
                cv_push(collect_8, name_14)
        cv_field(v_st, "defer_visible_names", cv_asset(collect_8))
        let collect_15: i64 = cv_vector(CV_LIST)
        let seq_17: i64 = cv_getkey(v_self, "const_scope")
        for index_16 in 0..cv_len(seq_17):
            let scope_18: i64 = cv_at(seq_17, index_16)
            let seq_20: i64 = scope_18
            for index_19 in 0..cv_len(seq_20):
                let name_21: i64 = cv_at(seq_20, index_19)
                cv_push(collect_15, name_21)
        cv_field(v_st, "defer_visible_names", cv_or(cv_getkey(v_st, "defer_visible_names"), cv_asset(collect_15)))
        let collect_22: i64 = cv_vector(CV_LIST)
        let seq_24: i64 = cv_getkey(v_self, "scope")
        for index_23 in 0..cv_len(seq_24):
            let scope_25: i64 = cv_at(seq_24, index_23)
            let seq_27: i64 = cv_values(scope_25)
            for index_26 in 0..cv_len(seq_27):
                let sid_28: i64 = cv_at(seq_27, index_26)
                cv_push(collect_22, cv_subscript(cv_getkey(v_self, "slots"), sid_28))
        cv_field(v_st, "defer_visible_slots", cv_asset(collect_22))
        let v_exclusive: i64 = cv_getkey(v_self, "exclusive_slots")
        let v_exclusive_before: i64 = cv_length(v_exclusive)
        ccs_typecheck_defer_action(v_self, cv_getkey(v_st, "action"))
        # These loans start inside this action, whose evaluation order has already been checked.
        cv_field(v_st, "exclusive_loans", cv_slice(v_exclusive, v_exclusive_before, 0))
        let collect_29: i64 = cv_vector(CV_LIST)
        let seq_31: i64 = cv_slice(cv_getkey(v_self, "slots"), cv_getkey(v_st, "defer_outer_slot_count"), 0)
        for index_30 in 0..cv_len(seq_31):
            let s_32: i64 = cv_at(seq_31, index_30)
            cv_push(collect_29, cv_bool((not (cv_equal(cv_getkey(s_32, "kind"), cv_text("temp"))))))
        if cv_truth(cv_any(collect_29)):
            ccs_error(cv_text("deferred action не может объявлять локальные переменные"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        ccs_validate_defer_reads(v_self, v_st)
        cv_push(cv_subscript(cv_getkey(v_self, "defer_stack"), cv_neg(11)), v_st)
        return 0
    if cv_classes(v_st, "ConstStmt"):
        if ((cv_contains(cv_subscript(cv_getkey(v_self, "scope"), cv_neg(11)), cv_getkey(v_st, "name"))) or (cv_contains(cv_subscript(cv_getkey(v_self, "const_scope"), cv_neg(11)), cv_getkey(v_st, "name"))) or (cv_contains(cv_getkey(v_self, "fn_param_names"), cv_getkey(v_st, "name")))):
            let pieces_33: i64 = cv_list()
            cv_push(pieces_33, cv_text("имя "))
            cv_push(pieces_33, cv_format(cv_getkey(v_st, "name"), ""))
            cv_push(pieces_33, cv_text(" объявлено дважды в этой области видимости"))
            ccs_error(cv_join(cv_text(""), pieces_33), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        if (cv_getkey(v_st, "init") == 0):
            ccs_error(cv_text("const требует инициализатор"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        if (cv_classes(cv_getkey(v_st, "init"), "Call") or cv_classes(cv_getkey(v_st, "init"), "VarRef")):
            if cv_classes(cv_getkey(v_st, "init"), "Call"):
                ccs_error(cv_text("const требует константное выражение"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
        v_typ = ccs_tf(v_self, cv_getkey(v_st, "init"), 0)
        let choice_34: i64 = 0
        if (not (cv_getkey(v_st, "typ") == 0)):
            choice_34 = ccs_resolve_type(v_self, cv_getkey(v_st, "typ"), CV_FALSE)
        else:
            choice_34 = v_typ
        v_want = choice_34
        if ((not (cv_equal(v_want, v_typ))) and not (cv_truth(cc_can_assign(v_typ, v_want)))):
            let pieces_35: i64 = cv_list()
            cv_push(pieces_35, cv_text("const "))
            cv_push(pieces_35, cv_format(cv_getkey(v_st, "name"), ""))
            cv_push(pieces_35, cv_text(": "))
            cv_push(pieces_35, cv_format(cc_display(v_typ), ""))
            cv_push(pieces_35, cv_text(" нельзя присвоить "))
            cv_push(pieces_35, cv_format(cc_display(v_want), ""))
            ccs_error(cv_join(cv_text(""), pieces_35), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        if cv_classes(v_want, "TWrapper"):
            ccs_error(cv_text("Option/Result нельзя использовать в const"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        if (cv_truth(cc_is_array(v_want)) or cv_truth(cc_is_struct(v_want)) or cv_truth(cc_is_ptr(v_want)) or cv_truth(cc_is_string(v_want)) or cv_classes(v_want, "TFnPtr") or cv_classes(v_want, "TTaggedEnum")):
            ccs_error(cv_text("const поддерживает только скалярные типы"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        v_value = ccs_fold_const(v_self, cv_getkey(v_st, "init"))
        if cv_truth(cc_is_int(v_want)):
            v_value = cv_int(v_value, 83)
            let unpack_36: i64 = cc_int_bounds(v_want)
            v_lo = cv_at(unpack_36, 0)
            v_hi = cv_at(unpack_36, 1)
            if ((cv_less(v_value, v_lo)) or (cv_less(v_hi, v_value))):
                ccs_error(cv_text("целочисленное переполнение в const"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
        else:
            if cv_truth(cc_is_float(v_want)):
                let choice_37: i64 = 0
                if (cv_equal(cv_getkey(v_want, "bits"), 259)):
                    choice_37 = cv_round32(v_value)
                else:
                    choice_37 = cv_f(v_value)
                v_value = choice_37
        cv_set(cv_subscript(cv_getkey(v_self, "const_scope"), cv_neg(11)), cv_getkey(v_st, "name"), cv_pair(v_want, v_value))
        cv_field(v_st, "const_type", v_want)
        cv_field(v_st, "const_value", v_value)
        return 0
    if cv_classes(v_st, "UnsafeStmt"):
        cv_field(v_self, "unsafe_depth", cv_add(cv_getkey(v_self, "unsafe_depth"), 11))
        ccs_typecheck_stmts(v_self, cv_getkey(v_st, "body"))
        cv_field(v_self, "unsafe_depth", cv_sub(cv_getkey(v_self, "unsafe_depth"), 11))
        return 0
    if cv_classes(v_st, "LetStmt"):
        cv_field(v_st, "init_t", 0)
        if (cv_getkey(v_st, "init") == 0):
            if (cv_getkey(v_st, "typ") == 0):
                ccs_error(cv_text("let без типа требует = значение"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            v_typ = ccs_resolve_type(v_self, cv_getkey(v_st, "typ"), CV_FALSE)
            ccs_default_access(v_typ, cv_getkey(cv_getkey(v_self, "fn"), "file"), cv_getkey(v_st, "line"))
            if cv_classes(v_typ, "TTaggedEnum"):
                ccs_error(cv_text("enum с payload требует явного конструктора или инициализатора"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            if cv_classes(v_typ, "TSlice"):
                ccs_error(cv_text("slice требует инициализатор"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            if (cv_truth(cc_is_array(v_typ)) or cv_truth(cc_is_struct(v_typ))):
                if cv_truth(cc_is_array(v_typ)):
                    v_zero_flag = CV_TRUE
            cv_field(v_st, "init", 0)
        else:
            if (cv_classes(cv_getkey(v_st, "init"), "ArrayLit") or ((not (cv_getkey(v_st, "typ") == 0)) and cv_truth(cc_is_array(ccs_resolve_type(v_self, cv_getkey(v_st, "typ"), CV_FALSE))))):
                let choice_38: i64 = 0
                if cv_classes(cv_getkey(v_st, "init"), "ArrayLit"):
                    choice_38 = cv_getkey(cv_getkey(v_st, "init"), "items")
                else:
                    choice_38 = 0
                v_items = choice_38
                if (not (cv_getkey(v_st, "typ") == 0)):
                    v_bold = ccs_resolve_type(v_self, cv_getkey(v_st, "typ"), CV_FALSE)
                    if not (cv_truth(cc_is_array(v_bold))):
                        ccs_error(cv_text("объявлен не-массив, а передан список"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    v_elem = cv_getkey(v_bold, "elem")
                    v_n = cv_getkey(v_bold, "n")
                    cv_field(v_st, "init_elem", v_elem)
                    cv_field(v_st, "init_len", v_n)
                    if (v_items == 0):
                        v_init_t = ccs_tf(v_self, cv_getkey(v_st, "init"), 0)
                        if (not (cv_equal(v_init_t, v_bold))):
                            let pieces_39: i64 = cv_list()
                            cv_push(pieces_39, cv_text("инициализатор массива "))
                            cv_push(pieces_39, cv_format(cc_display(v_init_t), ""))
                            cv_push(pieces_39, cv_text(" не совпадает с "))
                            cv_push(pieces_39, cv_format(cc_display(v_bold), ""))
                            ccs_error(cv_join(cv_text(""), pieces_39), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                            return 0
                    else:
                        if (cv_less(v_n, cv_length(v_items))):
                            let pieces_40: i64 = cv_list()
                            cv_push(pieces_40, cv_text("инициализатор содержит "))
                            cv_push(pieces_40, cv_format(cv_length(v_items), ""))
                            cv_push(pieces_40, cv_text(" элементов для массива длины "))
                            cv_push(pieces_40, cv_format(v_n, ""))
                            ccs_error(cv_join(cv_text(""), pieces_40), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                            return 0
                        if cv_less(cv_length(v_items), v_n):
                            ccs_default_access(v_elem, cv_getkey(cv_getkey(v_self, "fn"), "file"), cv_getkey(v_st, "line"))
                        let seq_42: i64 = v_items
                        for index_41 in 0..cv_len(seq_42):
                            v_it = cv_at(seq_42, index_41)
                            v_at = ccs_tf(v_self, v_it, v_elem)
                            if not (cv_truth(cc_can_assign(v_at, v_elem))):
                                let pieces_43: i64 = cv_list()
                                cv_push(pieces_43, cv_text("элемент массива: "))
                                cv_push(pieces_43, cv_format(cc_display(v_at), ""))
                                cv_push(pieces_43, cv_text(" вместо "))
                                cv_push(pieces_43, cv_format(cc_display(v_elem), ""))
                                ccs_error(cv_join(cv_text(""), pieces_43), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_it)
                                return 0
                            if (cv_truth(cc_is_struct(v_elem)) and cv_classes(v_it, "Call") and (cv_equal(cv_get(v_it, cv_text("kindt"), 0), cv_text("ctor"))) and (cv_get(v_it, cv_text("temp_slot"), 0) == 0)):
                                cv_field(v_it, "temp_slot", ccs_declare_temp(v_self, v_elem, cv_getkey(v_it, "line")))
                        cv_field(v_st, "init", 0)
                        cv_field(v_st, "init_elem", v_elem)
                        cv_field(v_st, "init_len", v_n)
                        cv_field(v_st, "aitems", v_items)
                else:
                    if not (cv_truth(v_items)):
                        ccs_error(cv_text("пустой массив не имеет разрешённого типа"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    v_elem = ccs_tf(v_self, cv_subscript(v_items, 3), 0)
                    if cc_is_owned(v_elem) or cc_is_owned_ptr(v_elem):
                        ccs_error(cv_text("OwnedBuffer и его адрес нельзя хранить в массиве"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                    if cv_classes(v_elem, "TSlice"):
                        ccs_error(cv_text("slice нельзя хранить в массиве"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    if cv_truth(cc_contains_tagged_type(v_elem)):
                        ccs_error(cv_text("Option/Result нельзя помещать в массив (как и enum с payload)"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    let seq_45: i64 = cv_slice(v_items, 11, 0)
                    for index_44 in 0..cv_len(seq_45):
                        v_it = cv_at(seq_45, index_44)
                        v_at = ccs_tf(v_self, v_it, 0)
                        if not (cv_truth(cc_can_assign(v_at, v_elem))):
                            let pieces_46: i64 = cv_list()
                            cv_push(pieces_46, cv_text("элемент массива: "))
                            cv_push(pieces_46, cv_format(cc_display(v_at), ""))
                            cv_push(pieces_46, cv_text(" вместо "))
                            cv_push(pieces_46, cv_format(cc_display(v_elem), ""))
                            ccs_error(cv_join(cv_text(""), pieces_46), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_it)
                            return 0
                    if cv_truth(cc_is_struct(v_elem)):
                        let seq_48: i64 = v_items
                        for index_47 in 0..cv_len(seq_48):
                            v_it = cv_at(seq_48, index_47)
                            if (cv_classes(v_it, "Call") and (cv_equal(cv_get(v_it, cv_text("kindt"), 0), cv_text("ctor"))) and (cv_get(v_it, cv_text("temp_slot"), 0) == 0)):
                                cv_field(v_it, "temp_slot", ccs_declare_temp(v_self, v_elem, cv_getkey(v_it, "line")))
                    cv_field(v_st, "init", 0)
                    cv_field(v_st, "init_elem", v_elem)
                    cv_field(v_st, "init_len", cv_length(v_items))
                    cv_field(v_st, "aitems", v_items)
                v_typ = cc_TArray(cv_getkey(v_st, "init_elem"), cv_getkey(v_st, "init_len"))
            else:
                let choice_49: i64 = 0
                if (not (cv_getkey(v_st, "typ") == 0)):
                    choice_49 = ccs_resolve_type(v_self, cv_getkey(v_st, "typ"), CV_FALSE)
                else:
                    choice_49 = 0
                v_want_t = choice_49
                let logic_51: bool = cv_classes(cv_getkey(v_st, "init"), "Call")
                if logic_51:
                    let subject_50: i64 = cv_getkey(cv_getkey(v_st, "init"), "name")
                    logic_51 = ((cv_equal(subject_50, cv_text("Some")) or cv_equal(subject_50, cv_text("None")) or cv_equal(subject_50, cv_text("Ok")) or cv_equal(subject_50, cv_text("Err"))))
                if (logic_51 and (not (v_want_t == 0))):
                    cv_field(cv_getkey(v_st, "init"), "context_type", v_want_t)
                v_init_t = ccs_tf(v_self, cv_getkey(v_st, "init"), v_want_t)
                if (not (v_want_t == 0)):
                    if ((not (cv_equal(v_want_t, v_init_t))) and not (cv_truth(cc_can_assign(v_init_t, v_want_t)))):
                        let pieces_52: i64 = cv_list()
                        cv_push(pieces_52, cv_text("let "))
                        cv_push(pieces_52, cv_format(cv_getkey(v_st, "name"), ""))
                        cv_push(pieces_52, cv_text(": "))
                        cv_push(pieces_52, cv_format(cc_display(v_init_t), ""))
                        cv_push(pieces_52, cv_text(" нельзя присвоить "))
                        cv_push(pieces_52, cv_format(cc_display(v_want_t), ""))
                        ccs_error(cv_join(cv_text(""), pieces_52), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    if cv_truth(cc_is_array(v_want_t)):
                        ccs_error(cv_cat(cv_format(cc_display(v_want_t), ""), cv_text(": инициализация списка")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    v_init_t = v_want_t
                v_typ = v_init_t
                if cv_classes(v_typ, "TSlice"):
                    let v_init: i64 = cv_getkey(v_st, "init")
                    if cc_is_mut_slice(v_typ) and not cv_classes(v_init, "SliceExpr"):
                        ccs_error(cv_text("изменяемый slice нельзя копировать: нужен диапазон локального массива"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    if ccs_slice_origin(v_init) == 0:
                        ccs_error(cv_text("инициализатор slice: нужен диапазон локального массива или имя неизменяемого slice либо результат с известным источником"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
        let choice_53: i64 = cv_bool((cv_getkey(v_st, "init") == 0))
        if not cv_truth(choice_53):
            let items_55: i64 = cv_vector(CV_TUPLE)
            cv_push(items_55, cv_getkey(v_self, "_ptr_char"))
            let choice_54: i64 = cv_bool((not (cv_contains(items_55, v_typ))))
            if cv_truth(choice_54):
                choice_54 = cv_bool(not (cv_truth(cc_is_num(v_typ))))
            if cv_truth(choice_54):
                choice_54 = cv_bool(not (cv_truth(cc_is_bool(v_typ))))
            if cv_truth(choice_54):
                choice_54 = cv_bool((not (cv_equal(v_typ, cv_getkey(v_self, "_ptr_char")))))
            if cv_truth(choice_54):
                choice_54 = cv_bool(not (cv_classes(v_typ, "TPtr")))
            choice_53 = choice_54
        let v_sid: i64 = ccs_declare(v_self, cv_getkey(v_st, "name"), v_typ, choice_53, cv_getkey(v_st, "line"), cv_text("local"))
        cv_field(v_st, "slot", v_sid)
        if cv_classes(v_typ, "TSlice"):
            cv_field(cv_subscript(cv_getkey(v_self, "slots"), v_sid), "slice_origin", ccs_slice_origin(cv_getkey(v_st, "init")))
        if cv_truth(cv_getkey(cv_getkey(v_st, "init"), "buffer_read_generated")):
            cv_field(cv_subscript(cv_getkey(v_self, "slots"), v_sid), "buffer_read_loan", CV_TRUE)
        return 0
    if cv_classes(v_st, "AssignStmt"):
        let target: i64 = cv_getkey(v_st, "target")
        ccs_tf(v_self, target, 0)
        if cv_has(target, cv_text("const_binding")):
            let name: i64 = cv_get(target, cv_text("name"), cv_getkey(target, "field"))
            ccs_error(cv_mod(cv_text("const %s нельзя изменить"), name), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        v_expected = cv_getkey(cv_getkey(v_st, "target"), "type")
        if cv_classes(v_expected, "TSlice"):
            ccs_error(cv_text("присваивание slice запрещено; создайте новый срез через let"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        let logic_59: bool = cv_classes(v_expected, "TWrapper") and cv_classes(cv_getkey(v_st, "value"), "Call")
        if logic_59:
            let subject_58: i64 = cv_getkey(cv_getkey(v_st, "value"), "name")
            logic_59 = ((cv_equal(subject_58, cv_text("Some")) or cv_equal(subject_58, cv_text("None")) or cv_equal(subject_58, cv_text("Ok")) or cv_equal(subject_58, cv_text("Err"))))
        if (logic_59):
            cv_field(cv_getkey(v_st, "value"), "context_type", v_expected)
        ccs_tf(v_self, cv_getkey(v_st, "value"), v_expected)
        v_tg = cv_getkey(cv_getkey(v_st, "target"), "type")
        v_rt = cv_getkey(cv_getkey(v_st, "value"), "type")
        if cv_classes(v_tg, "TTaggedEnum") and (not cv_name(cv_getkey(v_st, "op"), "=") or cv_getkey(cv_getkey(v_st, "target"), "slot") == 0):
            ccs_error(cv_text("enum с payload поддерживает только '=' для локальных переменных и параметров"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        if cv_classes(v_tg, "TWrapper"):
            v_slot = cv_get(cv_getkey(v_st, "target"), cv_text("slot"), 0)
            if (not (cv_equal(cv_getkey(v_st, "op"), cv_text("=")))):
                ccs_error(cv_text("Option/Result поддерживает только присваивание '='"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            let logic_61: bool = (v_slot == 0)
            if not logic_61:
                let subject_60: i64 = cv_getkey(v_slot, "kind")
                logic_61 = (not ((cv_equal(subject_60, cv_text("local")) or cv_equal(subject_60, cv_text("param")))))
            if (logic_61):
                ccs_error(cv_text("Option/Result присваивание поддерживается только для локальных переменных и параметров"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            if (not (cv_equal(v_rt, v_tg))):
                let pieces_62: i64 = cv_list()
                cv_push(pieces_62, cv_text("присваивание "))
                cv_push(pieces_62, cv_format(cc_display(v_tg), ""))
                cv_push(pieces_62, cv_text(" <- "))
                cv_push(pieces_62, cv_format(cc_display(v_rt), ""))
                cv_push(pieces_62, cv_text(" недопустимо"))
                ccs_error(cv_join(cv_text(""), pieces_62), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
        if (cv_classes(cv_getkey(v_st, "op"), "str") and (not (cv_equal(cv_getkey(v_st, "op"), cv_text("="))))):
            if (cv_classes(v_tg, "TEnum") or cv_classes(v_rt, "TEnum")):
                let pieces_63: i64 = cv_list()
                cv_push(pieces_63, cv_text("'"))
                cv_push(pieces_63, cv_format(cv_getkey(v_st, "op"), ""))
                cv_push(pieces_63, cv_text("' не поддерживается для enum"))
                ccs_error(cv_join(cv_text(""), pieces_63), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            if not (cv_truth(cc_is_num(v_tg))):
                let pieces_64: i64 = cv_list()
                cv_push(pieces_64, cv_text("'"))
                cv_push(pieces_64, cv_format(cv_getkey(v_st, "op"), ""))
                cv_push(pieces_64, cv_text("' требует числовой тип"))
                ccs_error(cv_join(cv_text(""), pieces_64), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            if not (cv_truth(cc_is_num(v_rt))):
                let pieces_65: i64 = cv_list()
                cv_push(pieces_65, cv_text("'"))
                cv_push(pieces_65, cv_format(cv_getkey(v_st, "op"), ""))
                cv_push(pieces_65, cv_text("' требует числовой тип"))
                ccs_error(cv_join(cv_text(""), pieces_65), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            if (not (cv_equal(cv_bool(cv_classes(cv_getkey(cv_getkey(v_st, "value"), "type"), "TFloat")), cv_bool(cv_classes(cv_getkey(cv_getkey(v_st, "target"), "type"), "TFloat"))))):
                let pieces_66: i64 = cv_list()
                cv_push(pieces_66, cv_text("'"))
                cv_push(pieces_66, cv_format(cv_getkey(v_st, "op"), ""))
                cv_push(pieces_66, cv_text("': смешение int/float запрещено; приведите через as"))
                ccs_error(cv_join(cv_text(""), pieces_66), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            let subject_67: i64 = cv_getkey(v_st, "op")
            if (((cv_equal(subject_67, cv_text("%")) or cv_equal(subject_67, cv_text("&")) or cv_equal(subject_67, cv_text("|")) or cv_equal(subject_67, cv_text("^")) or cv_equal(subject_67, cv_text("<<")) or cv_equal(subject_67, cv_text(">>")))) and (not (cv_truth(cc_is_int(v_tg))) or not (cv_truth(cc_is_int(v_rt))))):
                let pieces_68: i64 = cv_list()
                cv_push(pieces_68, cv_text("'"))
                cv_push(pieces_68, cv_format(cv_getkey(v_st, "op"), ""))
                cv_push(pieces_68, cv_text("' требует целые числа"))
                ccs_error(cv_join(cv_text(""), pieces_68), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
            let choice_69: i64 = 0
            let subject_70: i64 = cv_getkey(v_st, "op")
            if ((cv_equal(subject_70, cv_text("<<")) or cv_equal(subject_70, cv_text(">>")))):
                choice_69 = v_tg
            else:
                let choice_71: i64 = cc_num_widen(v_tg, v_rt)
                if not cv_truth(choice_71):
                    choice_71 = v_tg
                choice_69 = choice_71
            cv_field(v_st, "compound_type", choice_69)
        if (cv_equal(cv_getkey(v_st, "op"), cv_text("="))):
            if not (cv_truth(cc_can_assign(v_rt, v_tg))):
                let pieces_72: i64 = cv_list()
                cv_push(pieces_72, cv_text("присваивание "))
                cv_push(pieces_72, cv_format(cc_display(v_tg), ""))
                cv_push(pieces_72, cv_text(" <- "))
                cv_push(pieces_72, cv_format(cc_display(v_rt), ""))
                cv_push(pieces_72, cv_text(" недопустимо"))
                ccs_error(cv_join(cv_text(""), pieces_72), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
        else:
            if (not (cv_equal(cv_bool(cv_classes(cv_getkey(cv_getkey(v_st, "target"), "type"), "TFloat")), cv_bool(cv_classes(cv_getkey(cv_getkey(v_st, "value"), "type"), "TFloat"))))):
                ccs_error(cv_text("смешение int/float в составном присваивании"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
        ccs_check_lvalue(v_self, cv_getkey(v_st, "target"))
        if ((cv_equal(cv_getkey(v_st, "op"), cv_text("="))) and cv_classes(cv_getkey(v_st, "value"), "Call") and (cv_equal(cv_get(cv_getkey(v_st, "value"), cv_text("kindt"), 0), cv_text("ctor")))):
            cv_field(cv_getkey(v_st, "value"), "temp_slot", ccs_declare_temp(v_self, cv_getkey(cv_getkey(v_st, "value"), "type"), cv_getkey(v_st, "line")))
        return 0
    if cv_classes(v_st, "IfStmt"):
        let seq_74: i64 = cv_getkey(v_st, "conds")
        for index_73 in 0..cv_len(seq_74):
            let unpack_75: i64 = cv_at(seq_74, index_73)
            v_cond = cv_at(unpack_75, 0)
            v_body = cv_at(unpack_75, 1)
            ccs_tf(v_self, v_cond, 0)
            ccs_truthy_check(v_self, cv_getkey(v_cond, "type"), v_cond)
            # Temporary slice arguments of the condition end their loans before the body.
            ccs_apply_temp_slice_releases(v_self)
            cv_push(cv_getkey(v_self, "scope"), cv_dict())
            ccs_typecheck_stmts(v_self, v_body)
            cv_pop(cv_getkey(v_self, "scope"))
        if cv_truth(cv_getkey(v_st, "els")):
            cv_push(cv_getkey(v_self, "scope"), cv_dict())
            ccs_typecheck_stmts(v_self, cv_getkey(v_st, "els"))
            cv_pop(cv_getkey(v_self, "scope"))
        return 0
    if cv_classes(v_st, "WhileStmt"):
        ccs_tf(v_self, cv_getkey(v_st, "cond"), 0)
        ccs_truthy_check(v_self, cv_getkey(cv_getkey(v_st, "cond"), "type"), cv_getkey(v_st, "cond"))
        ccs_apply_temp_slice_releases(v_self)
        cv_push(cv_getkey(cv_getkey(v_self, "fn"), "loop_stack"), v_st)
        cv_push(cv_getkey(v_self, "loop_scope_depth"), cv_length(cv_getkey(v_self, "defer_stack")))
        cv_push(cv_getkey(v_self, "scope"), cv_dict())
        ccs_typecheck_stmts(v_self, cv_getkey(v_st, "body"))
        cv_pop(cv_getkey(v_self, "scope"))
        cv_pop(cv_getkey(v_self, "loop_scope_depth"))
        cv_pop(cv_getkey(cv_getkey(v_self, "fn"), "loop_stack"))
        return 0
    if cv_classes(v_st, "ForStmt"):
        v_a = ccs_tf(v_self, cv_getkey(v_st, "start"), 0)
        v_b = ccs_tf(v_self, cv_getkey(v_st, "stop"), 0)
        ccs_apply_temp_slice_releases(v_self)
        if (not (cv_truth(cc_is_int(v_a))) or not (cv_truth(cc_is_int(v_b))) or cv_classes(v_a, "TEnum") or cv_classes(v_b, "TEnum")):
            ccs_error(cv_text("границы for должны иметь целочисленный тип, кроме enum"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        cv_push(cv_getkey(v_self, "scope"), cv_dict())
        ccs_declare(v_self, cv_getkey(v_st, "var"), cc_int(CV_TRUE, 515), CV_FALSE, cv_getkey(v_st, "line"), cv_text("local"))
        cv_field(v_st, "var_slot", cv_subscript(cv_subscript(cv_getkey(v_self, "scope"), cv_neg(11)), cv_getkey(v_st, "var")))
        cv_push(cv_getkey(cv_getkey(v_self, "fn"), "loop_stack"), v_st)
        cv_push(cv_getkey(v_self, "loop_scope_depth"), cv_length(cv_getkey(v_self, "defer_stack")))
        ccs_typecheck_stmts(v_self, cv_getkey(v_st, "body"))
        cv_pop(cv_getkey(v_self, "loop_scope_depth"))
        cv_pop(cv_getkey(v_self, "scope"))
        cv_pop(cv_getkey(cv_getkey(v_self, "fn"), "loop_stack"))
        cv_field(v_st, "end_t", v_b)
        return 0
    if cv_classes(v_st, "BreakStmt"):
        if not (cv_truth(cv_getkey(cv_getkey(v_self, "fn"), "loop_stack"))):
            ccs_error(cv_text("break вне цикла"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        cv_field(v_st, "cleanup_scopes", cv_sub(cv_length(cv_getkey(v_self, "defer_stack")), cv_subscript(cv_getkey(v_self, "loop_scope_depth"), cv_neg(11))))
        return 0
    if cv_classes(v_st, "ContinueStmt"):
        if not (cv_truth(cv_getkey(cv_getkey(v_self, "fn"), "loop_stack"))):
            ccs_error(cv_text("continue вне цикла"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        cv_field(v_st, "cleanup_scopes", cv_sub(cv_length(cv_getkey(v_self, "defer_stack")), cv_subscript(cv_getkey(v_self, "loop_scope_depth"), cv_neg(11))))
        return 0
    if cv_classes(v_st, "ReturnStmt"):
        if (not (cv_getkey(v_st, "value") == 0)):
            let logic_77: bool = cv_classes(cv_getkey(v_st, "value"), "Call")
            if logic_77:
                let subject_76: i64 = cv_getkey(cv_getkey(v_st, "value"), "name")
                logic_77 = ((cv_equal(subject_76, cv_text("Some")) or cv_equal(subject_76, cv_text("None")) or cv_equal(subject_76, cv_text("Ok")) or cv_equal(subject_76, cv_text("Err"))))
            if (logic_77):
                cv_field(cv_getkey(v_st, "value"), "context_type", cv_getkey(cv_getkey(v_self, "fn"), "sig_ret"))
            let logic_79: bool = cv_classes(cv_getkey(v_st, "value"), "Unary") and (cv_equal(cv_getkey(cv_getkey(v_st, "value"), "op"), cv_text("?"))) and cv_classes(cv_getkey(cv_getkey(v_st, "value"), "x"), "Call")
            if logic_79:
                let subject_78: i64 = cv_getkey(cv_getkey(cv_getkey(v_st, "value"), "x"), "name")
                logic_79 = ((cv_equal(subject_78, cv_text("Some")) or cv_equal(subject_78, cv_text("None")) or cv_equal(subject_78, cv_text("Ok")) or cv_equal(subject_78, cv_text("Err"))))
            if (logic_79):
                cv_field(cv_getkey(cv_getkey(v_st, "value"), "x"), "context_type", cv_getkey(cv_getkey(v_self, "fn"), "sig_ret"))
            v_vt = ccs_tf(v_self, cv_getkey(v_st, "value"), cv_getkey(cv_getkey(v_self, "fn"), "sig_ret"))
            let v_fn: i64 = cv_getkey(v_self, "fn")
            if cv_classes(cv_getkey(v_fn, "sig_ret"), "TSlice"):
                let v_source: i64 = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_fn, "ret_source_index"))
                # Источник по адресу владельца: доверенный домашний модуль сам строит
                # срез из сырого хранилища, лексического источника у него нет.
                if not cc_is_owned_ptr(cv_getkey(v_source, "typ")) and ccs_slice_origin(cv_getkey(v_st, "value")) != v_source:
                    let v_msg: i64 = cv_cat(cv_text("return: срез должен происходить из параметра "), cv_getkey(v_fn, "ret_source"))
                    ccs_error(v_msg, cv_getkey(v_fn, "file"), v_st)
                    return 0
            if (cv_getkey(cv_getkey(v_self, "fn"), "sig_ret") == 0):
                cv_field(v_self, "had_ret_values", CV_TRUE)
            else:
                if cv_classes(cv_getkey(cv_getkey(v_self, "fn"), "sig_ret"), "TWrapper"):
                    if (not (cv_equal(v_vt, cv_getkey(cv_getkey(v_self, "fn"), "sig_ret")))):
                        let pieces_80: i64 = cv_list()
                        cv_push(pieces_80, cv_text("return: "))
                        cv_push(pieces_80, cv_format(cc_display(v_vt), ""))
                        cv_push(pieces_80, cv_text(" вместо "))
                        cv_push(pieces_80, cv_format(cc_display(cv_getkey(cv_getkey(v_self, "fn"), "sig_ret")), ""))
                        ccs_error(cv_join(cv_text(""), pieces_80), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    let value: i64 = cv_getkey(v_st, "value")
                    if cv_name(cv_getkey(value, "kindt"), "wrapper_ctor") and cv_getkey(value, "temp_slot") == 0:
                        cv_field(value, "temp_slot", ccs_declare_temp(v_self, v_vt, cv_getkey(v_st, "line")))
                else:
                    if cv_classes(v_vt, "TWrapper"):
                        ccs_error(cv_text("Option/Result return требует сигнатуру с тем же wrapper-типом"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                        return 0
                    ccs_check_buffer_cast(v_self, v_vt, cv_getkey(cv_getkey(v_self, "fn"), "sig_ret"), cv_getkey(v_st, "value"))
                    ccs_chk_cast(v_self, v_vt, cv_getkey(cv_getkey(v_self, "fn"), "sig_ret"), v_st, CV_FALSE)
        else:
            if (not (cv_getkey(cv_getkey(v_self, "fn"), "sig_ret") == 0)):
                ccs_error(cv_text("return без значения в функции с ->"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
                return 0
        cv_field(v_st, "cleanup_scopes", cv_length(cv_getkey(v_self, "defer_stack")))
        cv_field(v_self, "had_ret", CV_TRUE)
        return 0
    if cv_classes(v_st, "MatchStmt"):
        v_mt = ccs_tf(v_self, cv_getkey(v_st, "value"), 0)
        let enum_match: bool = cv_classes(v_mt, "TEnum") or cv_classes(v_mt, "TTaggedEnum")
        if not (enum_match or cv_classes(v_mt, "TWrapper")):
            ccs_error(cv_text("match поддерживает только enum, Option и Result"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        if (cv_classes(v_mt, "TWrapper") and cv_classes(cv_getkey(v_st, "value"), "Call") and (cv_equal(cv_get(cv_getkey(v_st, "value"), cv_text("kindt"), 0), cv_text("wrapper_ctor")))):
            ccs_error(cv_text("match временного wrapper-конструктора пока не поддерживается; используйте локальную переменную"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        v_covered = cv_vector(CV_SET)
        v_wildcard = CV_FALSE
        let seq_82: i64 = cv_getkey(v_st, "arms")
        for index_81 in 0..cv_len(seq_82):
            v_arm = cv_at(seq_82, index_81)
            v_p = cv_getkey(v_arm, "pattern")
            v_payload = 0
            if (cv_equal(v_p, cv_text("_"))):
                let logic_84: bool = cv_truth(v_wildcard)
                if not logic_84:
                    let choice_83: i64 = 0
                    if enum_match:
                        choice_83 = cv_length(cv_getkey(v_mt, "values"))
                    else:
                        choice_83 = 19
                    logic_84 = (cv_equal(cv_length(v_covered), choice_83))
                if (logic_84):
                    ccs_error(cv_text("повторный или перекрывающийся pattern"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arm)
                    return 0
                v_wildcard = CV_TRUE
                cv_field(v_arm, "tag", 0)
            else:
                if cv_truth(v_wildcard):
                    ccs_error(cv_text("pattern после _ перекрывает уже покрытые варианты"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arm)
                    return 0
                if enum_match:
                    let parts: i64 = cv_split(v_p, cv_text("."), 0)
                    let type_name: i64 = cv_at(parts, 0)
                    if cv_len(parts) == 3: type_name = cc_qualified_variant(type_name, cv_at(parts, 1))
                    let file: i64 = cv_getkey(cv_getkey(v_self, "fn"), "file")
                    let resolved: i64 = ccs_module_name(v_self, type_name, file, cv_getkey(v_arm, "line"))
                    if cv_len(parts) < 2 or cv_len(parts) > 3 or not cv_equal(resolved, cv_getkey(v_mt, "name")) or not cv_has(cv_getkey(v_mt, "values"), cv_at(parts, -1)):
                        let pieces_85: i64 = cv_list()
                        cv_push(pieces_85, cv_text("неподходящий вариант "))
                        cv_push(pieces_85, cv_format(v_p, "r"))
                        cv_push(pieces_85, cv_text(" для "))
                        cv_push(pieces_85, cv_format(cc_display(v_mt), ""))
                        ccs_error(cv_join(cv_text(""), pieces_85), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arm)
                        return 0
                    v_v = cv_at(parts, -1)
                    v_key = v_v
                    cv_field(v_arm, "tag", cv_subscript(cv_getkey(v_mt, "values"), v_v))
                    v_payload = cv_get(cv_getkey(v_mt, "payloads"), v_v, 0)
                else:
                    v_key = v_p
                    let choice_86: i64 = 0
                    if (cv_equal(cv_getkey(v_mt, "name"), cv_text("Option"))):
                        let dict_87: i64 = cv_dict()
                        cv_set(dict_87, cv_text("None"), 3)
                        cv_set(dict_87, cv_text("Some"), 11)
                        choice_86 = dict_87
                    else:
                        let dict_88: i64 = cv_dict()
                        cv_set(dict_88, cv_text("Ok"), 3)
                        cv_set(dict_88, cv_text("Err"), 11)
                        choice_86 = dict_88
                    v_variants = choice_86
                    if (not (cv_contains(v_variants, v_p))):
                        ccs_error(cv_cat(cv_text("неподходящий pattern "), cv_format(v_p, "r")), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arm)
                        return 0
                    cv_field(v_arm, "tag", cv_subscript(v_variants, v_p))
                    if cv_name(v_p, "Some") or cv_name(v_p, "Ok"):
                        v_payload = cv_at(cv_getkey(v_mt, "args"), 0)
                    elif cv_name(v_p, "Err"):
                        v_payload = cv_at(cv_getkey(v_mt, "args"), 1)
                if not cv_equal(cv_bool(v_payload != 0), cv_bool(cv_getkey(v_arm, "binding") != 0)):
                    ccs_error(cv_mod(cv_text("pattern %s: некорректная binding"), v_p), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arm)
                    return 0
                if (cv_contains(v_covered, v_key)):
                    ccs_error(cv_text("повторный pattern"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_arm)
                    return 0
                cv_add_set(v_covered, v_key)
            cv_push(cv_getkey(v_self, "scope"), cv_dict())
            if cv_truth(cv_getkey(v_arm, "binding")):
                cv_field(v_arm, "binding_slot", ccs_declare(v_self, cv_getkey(v_arm, "binding"), v_payload, CV_FALSE, cv_getkey(v_arm, "line"), cv_text("local")))
            ccs_typecheck_stmts(v_self, cv_getkey(v_arm, "body"))
            cv_pop(cv_getkey(v_self, "scope"))
        let choice_91: i64 = 0
        if enum_match:
            choice_91 = cv_asset(cv_getkey(v_mt, "values"))
        else:
            let choice_92: i64 = 0
            if (cv_equal(cv_getkey(v_mt, "name"), cv_text("Option"))):
                let items_93: i64 = cv_vector(CV_SET)
                cv_add_set(items_93, cv_text("None"))
                cv_add_set(items_93, cv_text("Some"))
                choice_92 = items_93
            else:
                let items_94: i64 = cv_vector(CV_SET)
                cv_add_set(items_94, cv_text("Ok"))
                cv_add_set(items_94, cv_text("Err"))
                choice_92 = items_94
            choice_91 = choice_92
        v_expected = choice_91
        if (not (cv_truth(v_wildcard)) and (not (cv_equal(v_covered, v_expected)))):
            ccs_error(cv_add(cv_text("match не исчерпывающий: "), cv_join(cv_text(", "), cv_sorted(cv_sub(v_expected, v_covered)))), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
            return 0
        return 0
    if cv_classes(v_st, "ExprStmt"):
        ccs_tf(v_self, cv_getkey(v_st, "expr"), 0)
        return 0
    ccs_error(cv_add(cv_text("неизвестный stmt "), cv_typename(v_st)), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_st)
    return 0

unsafe fn cc_precheck_expr(v_self: i64, v_expr: i64) -> i64:
    let v_child: i64 = 0
    if (v_expr == 0):
        return 0
    # A propagating defer would enter block cleanup again while it is being emitted.
    if cv_classes(v_expr, "Unary") and cv_name(cv_getkey(v_expr, "op"), "?"):
        ccs_error(cv_text("постфиксный ? нельзя использовать в defer"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_expr)
        return 0
    if cv_classes(v_expr, "SliceExpr"):
        cc_precheck_expr(v_self, cv_getkey(v_expr, "base"))
        cc_precheck_expr(v_self, cv_getkey(v_expr, "start"))
        cc_precheck_expr(v_self, cv_getkey(v_expr, "end"))
        return 0
    if cv_classes(v_expr, "VarRef"):
        let name: i64 = cv_getkey(v_expr, "name")
        if cv_contains(cv_getkey(v_self, "future_local_names"), name) and ccs_find_slot(v_self, name) == 0 and ccs_const_lookup(v_self, name) == 0:
            cc_error(cv_cat(cv_cat(cv_text("defer использует локальную переменную "), name), cv_text(", объявленную после defer")),
                     cv_getkey(cv_getkey(v_self, "fn"), "file"), cv_getkey(v_expr, "line"))
        return 0
    if cv_classes(v_expr, "Unary") or cv_classes(v_expr, "Deref") or cv_classes(v_expr, "AddrOf") or cv_classes(v_expr, "Cast"):
        cc_precheck_expr(v_self, cv_getkey(v_expr, "x"))
    else:
        if cv_classes(v_expr, "Binary"):
            cc_precheck_expr(v_self, cv_getkey(v_expr, "l"))
            cc_precheck_expr(v_self, cv_getkey(v_expr, "r"))
        else:
            if cv_classes(v_expr, "Call"):
                if cv_truth(ccs_is_callback_builtin(v_self, cv_getkey(v_expr, "name"))):
                    return 0
                let seq_3: i64 = cv_getkey(v_expr, "args")
                for index_2 in 0..cv_len(seq_3):
                    v_child = cv_at(seq_3, index_2)
                    cc_precheck_expr(v_self, v_child)
            else:
                if cv_classes(v_expr, "Index"):
                    cc_precheck_expr(v_self, cv_getkey(v_expr, "base"))
                    cc_precheck_expr(v_self, cv_getkey(v_expr, "idx"))
                else:
                    if cv_classes(v_expr, "Member"):
                        let base: i64 = cv_getkey(v_expr, "base")
                        if not (cv_classes(base, "VarRef") and cv_classes(cv_get(cv_getkey(v_self, "enums"), cv_getkey(base, "name"), 0), "TTaggedEnum")):
                            cc_precheck_expr(v_self, base)
                    else:
                        if cv_classes(v_expr, "ArrayLit"):
                            let seq_5: i64 = cv_getkey(v_expr, "items")
                            for index_4 in 0..cv_len(seq_5):
                                v_child = cv_at(seq_5, index_4)
                                cc_precheck_expr(v_self, v_child)
    return 0

unsafe fn ccs_borrow_base(v_e: i64) -> i64:
    # Follow only projections that address the same storage, not raw pointers.
    while cv_classes(v_e, "Member") or cv_classes(v_e, "Index"):
        let v_base: i64 = cv_getkey(v_e, "base")
        let v_typ: i64 = cv_getkey(v_base, "type")
        if cv_classes(v_e, "Member") and cv_classes(v_typ, "TStruct"):
            v_e = v_base
        elif cv_classes(v_e, "Index") and (cv_classes(v_typ, "TArray") or cv_classes(v_typ, "TSlice")):
            v_e = v_base
        else:
            break
    return v_e

unsafe fn ccs_check_lvalue(v_self: i64, v_e: i64) -> i64:
    let v_place: i64 = ccs_borrow_base(v_e)
    let v_typ: i64 = cv_getkey(v_place, "type")
    if cv_classes(v_typ, "TSlice") and not cc_is_mut_slice(v_typ):
        ccs_error(cv_text("неизменяемый slice нельзя изменять"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    ccs_check_exclusive_owner(v_self, v_place)
    if cv_classes(v_place, "VarRef") and cv_contains(cv_getkey(v_self, "frozen_mut_slots"), cv_getkey(v_place, "slot")):
        ccs_error(cv_text("нельзя писать через изменяемый slice, пока из него создан slice на чтение"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_place, "VarRef") and cv_contains(cv_getkey(v_self, "borrowed_slots"), cv_getkey(v_place, "slot")):
        ccs_error(cv_text("нельзя менять массив, пока slice ссылается на него"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    let v_bt: i64 = 0
    if cv_classes(v_e, "Member"):
        if cv_has(v_e, cv_text("enum_value")):
            ccs_error(cv_text("вариант enum нельзя изменить"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        v_bt = cv_getkey(cv_getkey(v_e, "base"), "type")
        if (cv_truth(cc_is_struct(v_bt)) or (cv_truth(cc_is_ptr(v_bt)) and cv_classes(cv_getkey(v_bt, "elem"), "TStruct"))):
            return 0
        ccs_error(cv_text("нельзя присвоить это поле"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
        return 0
    if cv_classes(v_e, "Index"):
        if cv_truth(cc_is_string(cv_getkey(cv_getkey(v_e, "base"), "type"))):
            ccs_error(cv_text("string неизменяем; изменяйте копию в массиве байтов"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
            return 0
        return 0
    if cv_classes(v_e, "VarRef") or cv_classes(v_e, "Deref"):
        return 0
    ccs_error(cv_text("слева от '=' нельзя ставить это выражение"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)
    return 0

unsafe fn ccs_check_exclusive_owner(v_self: i64, v_e: i64):
    if cv_classes(v_e, "VarRef") and cv_contains(cv_getkey(v_self, "exclusive_slots"), cv_getkey(v_e, "slot")):
        ccs_error(cv_text("нельзя обращаться к массиву, пока он заимствован изменяемым slice"), cv_getkey(cv_getkey(v_self, "fn"), "file"), v_e)

unsafe fn ccs_check_main(v_self: i64, v_entry_prog: i64) -> i64:
    let v_init_steps: i64 = 0
    let v_p: i64 = 0
    let v_body: i64 = 0
    let v_entry_main: i64 = 0
    let v_call: i64 = 0
    let v_mf: i64 = 0
    let items_1: i64 = cv_vector(CV_LIST)
    v_init_steps = items_1
    let seq_3: i64 = cv_getkey(v_self, "progs")
    for index_2 in 0..cv_len(seq_3):
        v_p = cv_at(seq_3, index_2)
        if not (cv_truth(cv_getkey(v_p, "is_entry"))):
            let items_4: i64 = cv_vector(CV_LIST)
            cv_extend(v_init_steps, cv_get(v_p, cv_text("init_calls"), items_4))
    v_body = cv_add(v_init_steps, cv_getkey(v_entry_prog, "main"))
    let main_name: i64 = ccs_module_name(v_self, cv_text("main"), cv_getkey(v_entry_prog, "file"), cv_i(1))
    v_entry_main = cv_get(cv_getkey(v_self, "fns"), main_name, 0)
    if ((not (v_entry_main == 0)) and (cv_equal(cv_getkey(v_entry_main, "file"), cv_getkey(v_entry_prog, "file")))):
        if cv_truth(cv_getkey(v_entry_main, "params")):
            ccs_error(cv_text("fn main не должен иметь параметров"), cv_getkey(v_entry_main, "file"), v_entry_main)
            return 0
        let items_5: i64 = cv_vector(CV_LIST)
        v_call = cc_Call(main_name, items_5, cv_getkey(v_entry_main, "line"))
        if (not (cv_getkey(v_entry_main, "sig_ret") == 0)):
            let items_6: i64 = cv_vector(CV_LIST)
            cv_push(items_6, cc_ReturnStmt(v_call, cv_getkey(v_entry_main, "line")))
            v_body = cv_add(v_body, items_6)
        else:
            let items_7: i64 = cv_vector(CV_LIST)
            cv_push(items_7, cc_ExprStmt(v_call, cv_getkey(v_entry_main, "line")))
            cv_push(items_7, cc_ReturnStmt(cc_IntLit(3, cv_getkey(v_entry_main, "line")), cv_getkey(v_entry_main, "line")))
            v_body = cv_add(v_body, items_7)
    else:
        let items_8: i64 = cv_vector(CV_LIST)
        cv_push(items_8, cc_ReturnStmt(cc_IntLit(3, 11), 11))
        v_body = cv_add(v_body, items_8)
    let items_9: i64 = cv_vector(CV_LIST)
    let extra_10: i64 = cv_tuple()
    cv_push(extra_10, 0)
    cv_push(extra_10, 11)
    cv_push(extra_10, CV_FALSE)
    cv_push(extra_10, 0)
    v_mf = cc_FnDef(cv_getkey(v_entry_prog, "file"), cv_text("__voltmain__"), items_9, 0, v_body, extra_10)
    let items_11: i64 = cv_vector(CV_LIST)
    cv_field(v_mf, "sig_params", items_11)
    cv_field(v_mf, "sig_ret", cc_int(CV_TRUE, 515))
    ccs_setup_fn(v_self, v_mf)
    cv_field(v_self, "had_ret", CV_FALSE)
    cv_field(v_self, "had_ret_values", CV_FALSE)
    cv_field(v_self, "fn", v_mf)
    ccs_typecheck_stmts(v_self, cv_getkey(v_mf, "body"))
    ccs_check_ownership(v_self, v_mf)
    cv_field(v_mf, "slots", cv_getkey(v_self, "slots"))
    cv_field(v_mf, "ret_type", cc_int(CV_TRUE, 515))
    cv_field(v_self, "main_fn", v_mf)
    return 0

unsafe fn ccs_run(v_self: i64) -> i64:
    let v_prog: i64 = 0
    let v_fn: i64 = 0
    let v_entry: i64 = 0
    let v_p: i64 = 0
    ccs_auto_std(v_self)
    ccs_collect(v_self)
    let seq_2: i64 = cv_getkey(v_self, "progs")
    for index_1 in 0..cv_len(seq_2):
        v_prog = cv_at(seq_2, index_1)
        let seq_4: i64 = cv_getkey(v_prog, "fns")
        for index_3 in 0..cv_len(seq_4):
            v_fn = cv_at(seq_4, index_3)
            if not (cv_truth(cv_getkey(v_fn, "type_params"))):
                ccs_typecheck_fn(v_self, v_fn)
    ccs_check_specializations(v_self)
    v_entry = 0
    let seq_6: i64 = cv_getkey(v_self, "progs")
    for index_5 in 0..cv_len(seq_6):
        v_p = cv_at(seq_6, index_5)
        if cv_truth(cv_getkey(v_p, "is_entry")):
            v_entry = v_p
    if (v_entry == 0):
        cc_error(cv_text("внутр: входной файл не определён"), 0, 11)
        return 0
    ccs_check_main(v_self, v_entry)
    ccs_check_specializations(v_self)
    return 0

unsafe fn ccs_check_specializations(v_self: i64) -> i64:
    let v_pending: i64 = 0
    let v_fn: i64 = 0
    if not (cv_has(v_self, cv_text("_checked_specializations"))):
        cv_field(v_self, "_checked_specializations", cv_vector(CV_SET))
    while cv_truth(CV_TRUE):
        let collect_1: i64 = cv_vector(CV_LIST)
        let seq_3: i64 = cv_getkey(v_self, "specializations")
        for index_2 in 0..cv_len(seq_3):
            let fn_4: i64 = cv_at(seq_3, index_2)
            if not ((not (cv_contains(cv_getkey(v_self, "_checked_specializations"), cv_i(fn_4))))): continue
            cv_push(collect_1, fn_4)
        v_pending = collect_1
        if not (cv_truth(v_pending)):
            break
        let seq_6: i64 = v_pending
        for index_5 in 0..cv_len(seq_6):
            v_fn = cv_at(seq_6, index_5)
            cv_add_set(cv_getkey(v_self, "_checked_specializations"), cv_i(v_fn))
            ccs_typecheck_fn(v_self, v_fn)
    return 0
