# VOLT compiler, native self-hosted implementation.
use volt_syntax
use cv_helpers

unsafe fn cc_SlotK(v_name: i64, v_typ: i64, v_off: i64, v_size: i64, v_zero: i64, v_packed: i64) -> i64:
    let v_line: i64 = cv_at(v_packed, 0)
    let v_kind: i64 = cv_at(v_packed, 1)
    let v_self: i64 = cv_node("SlotK")
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "typ", v_typ)
    cv_field(v_self, "off", v_off)
    cv_field(v_self, "size", v_size)
    cv_field(v_self, "zero", v_zero)
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "kind", v_kind)
    return v_self

unsafe fn cc_TInt(v_signed: i64, v_bits: i64, v_alias: i64) -> i64:
    let v_self: i64 = cv_node("TInt")
    cv_field(v_self, "signed", v_signed)
    cv_field(v_self, "bits", v_bits)
    cv_field(v_self, "alias", v_alias)
    return v_self

unsafe fn cc_TFloat(v_bits: i64) -> i64:
    let v_self: i64 = cv_node("TFloat")
    cv_field(v_self, "bits", v_bits)
    return v_self

unsafe fn cc_TBool() -> i64:
    return cv_node("TBool")

unsafe fn cc_TPtr(v_elem: i64) -> i64:
    let v_self: i64 = cv_node("TPtr")
    cv_field(v_self, "elem", v_elem)
    return v_self

unsafe fn cc_TFnPtr(v_params: i64, v_result: i64) -> i64:
    let v_self: i64 = cv_node("TFnPtr")
    cv_field(v_self, "params", cv_astuple(v_params))
    cv_field(v_self, "result", v_result)
    return v_self

unsafe fn cc_TSlice(v_elem: i64, v_mutable: i64) -> i64:
    let v_self: i64 = cv_node("TSlice")
    cv_field(v_self, "elem", v_elem)
    cv_field(v_self, "mutable", v_mutable)
    return v_self

unsafe fn cc_TString() -> i64:
    return cv_node("TString")

unsafe fn cc_TArray(v_elem: i64, v_n: i64) -> i64:
    let v_self: i64 = cv_node("TArray")
    cv_field(v_self, "elem", v_elem)
    cv_field(v_self, "n", v_n)
    return v_self

unsafe fn cc_TTypeVar(v_name: i64) -> i64:
    let v_self: i64 = cv_node("TTypeVar")
    cv_field(v_self, "name", v_name)
    return v_self

unsafe fn cc_TStruct(v_name: i64, v_args: i64) -> i64:
    let v_self: i64 = cv_node("TStruct")
    cv_field(v_self, "name", v_name)
    let items_1: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "fields", items_1)
    cv_field(v_self, "args", cv_astuple(v_args))
    cv_field(v_self, "size", 0)
    cv_field(v_self, "align", 0)
    let collect_2: i64 = cv_vector(CV_LIST)
    let seq_4: i64 = cv_getkey(v_self, "args")
    for index_3 in 0..cv_len(seq_4):
        let t_5: i64 = cv_at(seq_4, index_3)
        cv_push(collect_2, cc_type_depth(t_5))
    cv_field(v_self, "type_depth", cv_add(11, cv_maximum(collect_2, 3)))
    return v_self

unsafe fn cc_TWrapper(v_name: i64, v_args: i64) -> i64:
    let v_payload: i64 = 0
    let v_pa: i64 = 0
    let v_self: i64 = cv_node("TWrapper")
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "args", cv_astuple(v_args))
    let choice_1: i64 = 0
    if (cv_equal(v_name, cv_text("Option"))):
        choice_1 = cv_pair(cv_text("None"), cv_text("Some"))
    else:
        choice_1 = cv_pair(cv_text("Ok"), cv_text("Err"))
    cv_field(v_self, "variant_names", choice_1)
    let choice_2: i64 = 0
    if (cv_equal(v_name, cv_text("Option"))):
        choice_2 = cv_pair(cv_subscript(v_args, 3), 0)
    else:
        choice_2 = cv_astuple(v_args)
    cv_field(v_self, "payload_types", choice_2)
    let seq_4: i64 = cv_getkey(v_self, "payload_types")
    for index_3 in 0..cv_len(seq_4):
        v_payload = cv_at(seq_4, index_3)
        if ((not (v_payload == 0)) and (not (cv_truth(cc_isscalar(v_payload))) or cv_classes(v_payload, "TWrapper"))):
            cc_error(cv_text("payload Option/Result должен быть скалярным типом"), 0, 11)
            return 0
    let collect_5: i64 = cv_vector(CV_LIST)
    let seq_7: i64 = cv_getkey(v_self, "payload_types")
    for index_6 in 0..cv_len(seq_7):
        let t_8: i64 = cv_at(seq_7, index_6)
        if not ((not (t_8 == 0))): continue
        cv_push(collect_5, cc_type_align(t_8))
    v_pa = cv_maximum(collect_5, 0)
    cv_field(v_self, "payload_off", cc_base_align(67, v_pa))
    cv_field(v_self, "align", cv_max(67, v_pa))
    let collect_9: i64 = cv_vector(CV_LIST)
    let seq_11: i64 = cv_getkey(v_self, "payload_types")
    for index_10 in 0..cv_len(seq_11):
        let t_12: i64 = cv_at(seq_11, index_10)
        if not ((not (t_12 == 0))): continue
        cv_push(collect_9, cc_type_size(t_12))
    cv_field(v_self, "size", cc_base_align(cv_add(cv_getkey(v_self, "payload_off"), cv_maximum(collect_9, 0)), cv_getkey(v_self, "align")))
    return v_self

unsafe fn cc_TEnum(v_name: i64, v_values: i64) -> i64:
    let v_self: i64 = cv_node("TEnum")
    cc_enum_base(v_self)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "values", v_values)
    return v_self

unsafe fn cc_int(v_signed: i64, v_bits: i64) -> i64:
    let v_k: i64 = 0
    v_k = cv_pair(v_signed, v_bits)
    if (not (cv_contains(cc_k_int_table, v_k))):
        cv_set(cc_k_int_table, v_k, cc_TInt(v_signed, v_bits, 0))
    return cv_subscript(cc_k_int_table, v_k)

unsafe fn cc_type_size(v_t: i64) -> i64:
    if (cv_classes(v_t, "TInt") or cv_classes(v_t, "TFloat")):
        return cv_floor(cv_getkey(v_t, "bits"), 67)
    if cv_classes(v_t, "TBool"):
        return 11
    if cv_classes(v_t, "TPtr") or cv_classes(v_t, "TFnPtr") or cv_classes(v_t, "TString"):
        return 67
    if cv_classes(v_t, "TSlice"):
        return 131
    if cv_classes(v_t, "TArray"):
        return cv_mul(cv_getkey(v_t, "n"), cc_type_size(cv_getkey(v_t, "elem")))
    if cv_classes(v_t, "TStruct"):
        if (cv_getkey(v_t, "size") == 0):
            cc_error(cv_add(cv_text("размер структуры ещё не вычислен: "), cc_display(v_t)), 0, 0)
            return 0
        return cv_getkey(v_t, "size")
    if cv_classes(v_t, "TWrapper"):
        return cv_getkey(v_t, "size")
    cc_error(cv_add(cv_text("невычислимый размер типа "), cc_display(v_t)), 0, 0)
    return 0

unsafe fn cc_type_align(v_t: i64) -> i64:
    if (cv_classes(v_t, "TInt") or cv_classes(v_t, "TFloat")):
        return cv_floor(cv_getkey(v_t, "bits"), 67)
    if cv_classes(v_t, "TBool"):
        return 11
    if cv_classes(v_t, "TPtr") or cv_classes(v_t, "TFnPtr") or cv_classes(v_t, "TString"):
        return 67
    if cv_classes(v_t, "TSlice"):
        return 67
    if cv_classes(v_t, "TArray"):
        return cc_type_align(cv_getkey(v_t, "elem"))
    if cv_classes(v_t, "TStruct"):
        if (cv_getkey(v_t, "align") == 0):
            cc_error(cv_add(cv_text("невозможно вычислить выравнивание незавершённой структуры "), cc_display(v_t)), 0, 0)
            return 0
        return cv_getkey(v_t, "align")
    if cv_classes(v_t, "TWrapper"):
        return cv_getkey(v_t, "align")
    cc_error(cv_add(cv_text("unknown align "), cc_display(v_t)), 0, 0)
    return 0

unsafe fn cc_is_num(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TInt") or cv_classes(v_t, "TFloat"))

unsafe fn cc_is_int(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TInt"))

unsafe fn cc_is_float(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TFloat"))

unsafe fn cc_is_ptr(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TPtr"))

unsafe fn cc_is_string(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TString"))

unsafe fn cc_is_bool(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TBool"))

unsafe fn cc_is_array(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TArray"))

unsafe fn cc_is_struct(v_t: i64) -> i64:
    return cv_bool(cv_classes(v_t, "TStruct"))

unsafe fn cc_type_depth(v_t: i64) -> i64:
    let v_depth: i64 = 0
    v_depth = 3
    while cv_classes(v_t, "TPtr") or cv_classes(v_t, "TArray") or cv_classes(v_t, "TSlice"):
        v_depth = cv_add(v_depth, 11)
        v_t = cv_getkey(v_t, "elem")
    if cv_classes(v_t, "TFnPtr"):
        let collect_1: i64 = cv_vector(CV_LIST)
        let items_2: i64 = cv_vector(CV_TUPLE)
        cv_extend(items_2, cv_getkey(v_t, "params"))
        cv_push(items_2, cv_getkey(v_t, "result"))
        let seq_4: i64 = items_2
        for index_3 in 0..cv_len(seq_4):
            let part_5: i64 = cv_at(seq_4, index_3)
            if not ((not (part_5 == 0))): continue
            cv_push(collect_1, cc_type_depth(part_5))
        return cv_add(cv_add(v_depth, 11), cv_maximum(collect_1, 3))
    let choice_6: i64 = 0
    if cv_classes(v_t, "TStruct"):
        choice_6 = cv_getkey(v_t, "type_depth")
    else:
        choice_6 = 11
    return cv_add(v_depth, choice_6)

unsafe fn cc_type_variables(v_t: i64) -> i64:
    if cv_classes(v_t, "TTypeVar"):
        let items_1: i64 = cv_vector(CV_SET)
        cv_add_set(items_1, cv_getkey(v_t, "name"))
        return items_1
    if cv_classes(v_t, "TPtr") or cv_classes(v_t, "TArray") or cv_classes(v_t, "TSlice"):
        return cc_type_variables(cv_getkey(v_t, "elem"))
    if cv_classes(v_t, "TStruct"):
        let collect_2: i64 = cv_vector(CV_LIST)
        let seq_4: i64 = cv_getkey(v_t, "args")
        for index_3 in 0..cv_len(seq_4):
            let arg_5: i64 = cv_at(seq_4, index_3)
            cv_push(collect_2, cc_type_variables(arg_5))
        return cv_union(collect_2)
    if cv_classes(v_t, "TFnPtr"):
        let collect_6: i64 = cv_vector(CV_LIST)
        let items_7: i64 = cv_vector(CV_TUPLE)
        cv_extend(items_7, cv_getkey(v_t, "params"))
        cv_push(items_7, cv_getkey(v_t, "result"))
        let seq_9: i64 = items_7
        for index_8 in 0..cv_len(seq_9):
            let part_10: i64 = cv_at(seq_9, index_8)
            cv_push(collect_6, cc_type_variables(part_10))
        return cv_union(collect_6)
    return cv_vector(CV_SET)

unsafe fn cc_contains_wrapper_type(v_t: i64) -> i64:
    let v_pending: i64 = 0
    let v_seen: i64 = 0
    let v_item: i64 = 0
    let v_ident: i64 = 0
    let items_1: i64 = cv_vector(CV_LIST)
    cv_push(items_1, v_t)
    v_pending = items_1
    v_seen = cv_vector(CV_SET)
    while cv_truth(v_pending):
        v_item = cv_pop(v_pending)
        if cv_classes(v_item, "TWrapper"):
            return CV_TRUE
        v_ident = cv_i(v_item)
        if (cv_contains(v_seen, v_ident)):
            continue
        cv_add_set(v_seen, v_ident)
        if cv_classes(v_item, "TPtr") or cv_classes(v_item, "TArray") or cv_classes(v_item, "TSlice"):
            cv_push(v_pending, cv_getkey(v_item, "elem"))
        else:
            if cv_classes(v_item, "TStruct"):
                let collect_2: i64 = cv_vector(CV_LIST)
                let seq_4: i64 = cv_getkey(v_item, "fields")
                for index_3 in 0..cv_len(seq_4):
                    let unpack_5: i64 = cv_at(seq_4, index_3)
                    let ft_6: i64 = cv_at(unpack_5, 1)
                    cv_push(collect_2, ft_6)
                cv_extend(v_pending, collect_2)
            else:
                if cv_classes(v_item, "TFnPtr"):
                    let items_7: i64 = cv_vector(CV_TUPLE)
                    cv_extend(items_7, cv_getkey(v_item, "params"))
                    cv_push(items_7, cv_getkey(v_item, "result"))
                    cv_extend(v_pending, items_7)
    return CV_FALSE

unsafe fn cc_int_bounds(v_t: i64) -> i64:
    if cv_truth(cv_getkey(v_t, "signed")):
        return cv_pair(cv_neg(cv_shl(11, cv_sub(cv_getkey(v_t, "bits"), 11))), cv_sub(cv_shl(11, cv_sub(cv_getkey(v_t, "bits"), 11)), 11))
    return cv_pair(3, cv_sub(cv_shl(11, cv_getkey(v_t, "bits")), 11))

unsafe fn cc_base_align(v_offset: i64, v_n: i64) -> i64:
    return cv_mul(cv_floor(cv_sub(cv_add(v_offset, v_n), 11), v_n), v_n)

unsafe fn cc_num_widen(v_a: i64, v_b: i64) -> i64:
    let v_signed: i64 = 0
    let v_unsigned: i64 = 0
    if (cv_classes(v_a, "TFloat") and cv_classes(v_b, "TFloat")):
        return cc_TFloat(cv_max(cv_getkey(v_a, "bits"), cv_getkey(v_b, "bits")))
    if (cv_classes(v_a, "TFloat") or cv_classes(v_b, "TFloat")):
        return 0
    if (cv_equal(cv_getkey(v_a, "signed"), cv_getkey(v_b, "signed"))):
        return cc_int(cv_getkey(v_a, "signed"), cv_max(cv_getkey(v_a, "bits"), cv_getkey(v_b, "bits")))
    let choice_1: i64 = 0
    if cv_truth(cv_getkey(v_a, "signed")):
        choice_1 = v_a
    else:
        choice_1 = v_b
    v_signed = choice_1
    let choice_2: i64 = 0
    if cv_truth(cv_getkey(v_a, "signed")):
        choice_2 = v_b
    else:
        choice_2 = v_a
    v_unsigned = choice_2
    if (cv_less(cv_getkey(v_unsigned, "bits"), cv_getkey(v_signed, "bits"))):
        return cc_int(CV_TRUE, cv_getkey(v_signed, "bits"))
    return cc_int(CV_FALSE, cv_getkey(v_unsigned, "bits"))

unsafe fn cc_widen_num(v_x: i64, v_t: i64) -> i64:
    if (cv_equal(v_x, v_t)):
        return CV_TRUE
    if (cv_classes(v_x, "TInt") and cv_classes(v_t, "TInt") and (cv_less(cv_getkey(v_x, "bits"), cv_getkey(v_t, "bits")))):
        return CV_TRUE
    if (cv_classes(v_x, "TFloat") and cv_classes(v_t, "TFloat") and (cv_less(cv_getkey(v_x, "bits"), cv_getkey(v_t, "bits")))):
        return CV_TRUE
    if (cv_classes(v_x, "TInt") and cv_classes(v_t, "TFloat") and (cv_equal(cv_getkey(v_t, "bits"), 515))):
        return CV_TRUE
    return CV_FALSE

unsafe fn cc_can_assign(v_a: i64, v_t: i64) -> i64:
    if (cv_truth(cc_is_string(v_a)) or cv_truth(cc_is_string(v_t))):
        let choice_1: i64 = cc_is_string(v_a)
        if cv_truth(choice_1):
            choice_1 = cc_is_string(v_t)
        return choice_1
    if (cv_classes(v_a, "TEnum") or cv_classes(v_t, "TEnum")):
        return cv_bool((cv_equal(v_a, v_t)))
    if (cv_equal(v_a, v_t)):
        return CV_TRUE
    if (cv_truth(cc_is_num(v_a)) and cv_truth(cc_is_num(v_t))):
        return CV_TRUE
    if (cv_truth(cc_is_ptr(v_a)) and cv_truth(cc_is_ptr(v_t))):
        return cv_bool((cv_equal(cv_getkey(v_a, "elem"), cv_getkey(v_t, "elem"))))
    return CV_FALSE

unsafe fn cc_isscalar(v_t: i64) -> i64:
    let choice_1: i64 = cc_is_num(v_t)
    if not cv_truth(choice_1):
        choice_1 = cc_is_bool(v_t)
    if not cv_truth(choice_1):
        choice_1 = cc_is_ptr(v_t)
    if not cv_truth(choice_1):
        choice_1 = cc_is_string(v_t)
    return choice_1
