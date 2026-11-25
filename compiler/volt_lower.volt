# VOLT compiler, native self-hosted implementation.
use volt_semantic
use asm_object

unsafe fn cce_new(v_sem: i64) -> i64:
    let v_self: i64 = cv_node("Emitter")
    cv_field(v_self, "sem", v_sem)
    let items_1: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "text", items_1)
    let items_2: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "rodata", items_2)
    let items_3: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "data", items_3)
    let items_4: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "bss", items_4)
    cv_field(v_self, "lbln", 3)
    cv_field(v_self, "str_cache", cv_dict())
    cv_field(v_self, "f_cache", cv_dict())
    cv_field(v_self, "cur", 0)
    cv_field(v_self, "cur_name", 0)
    let items_5: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "slots", items_5)
    cv_field(v_self, "lsize", 3)
    cv_field(v_self, "frame", 3)
    cv_field(v_self, "nt", 3)
    cv_field(v_self, "ntpeak", 3)
    cv_field(v_self, "for_floor", 3)
    let items_6: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "loop", items_6)
    let items_7: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "defer_frames", items_7)
    return v_self

unsafe fn cce_e(v_self: i64, v_line: i64) -> i64:
    cv_push(cv_getkey(v_self, "text"), cv_add(cv_text("    "), v_line))
    return 0

unsafe fn cce_lbl(v_self: i64) -> i64:
    cv_field(v_self, "lbln", cv_add(cv_getkey(v_self, "lbln"), 11))
    return cv_add(cv_getkey(cv_getkey(v_self, "sem"), "lbl_prefix"), cv_str(cv_getkey(v_self, "lbln")))

unsafe fn cce_label(v_self: i64, v_L: i64, v_sec: i64) -> i64:
    cv_push(cv_getkey(v_self, "text"), cv_add(v_L, cv_text(":")))
    return 0

unsafe fn cce_fconst(v_self: i64, v_val: i64) -> i64:
    let v_bits: i64 = 0
    let v_cached: i64 = 0
    let v_label: i64 = 0
    v_bits = cv_subscript(cv_single(cv_u(cv_fbits(cv_real_value(cv_f(v_val))))), 3)
    v_cached = cv_get(cv_getkey(v_self, "f_cache"), v_bits, 0)
    if (not (v_cached == 0)):
        return v_cached
    v_label = cv_mod(cv_text("VOLT_c%d"), cv_add(cv_add(cv_length(cv_getkey(v_self, "rodata")), cv_getkey(v_self, "lbln")), 11))
    cv_push(cv_getkey(v_self, "rodata"), cv_mod(cv_text("%s: .quad 0x%x"), cv_pair(v_label, v_bits)))
    cv_set(cv_getkey(v_self, "f_cache"), v_bits, v_label)
    return v_label

unsafe fn cce_slconst(v_self: i64, v_s: i64) -> i64:
    let v_nm: i64 = 0
    if (cv_contains(cv_getkey(v_self, "str_cache"), v_s)):
        return cv_subscript(cv_getkey(v_self, "str_cache"), v_s)
    v_nm = cv_mod(cv_text("VOLT_%d"), cv_add(cv_add(cv_length(cv_getkey(v_self, "rodata")), cv_getkey(v_self, "lbln")), 11))
    cv_push(cv_getkey(v_self, "rodata"), cv_mod(cv_text("%s: .string \"%s\""), cv_pair(v_nm, cc_esc_str(v_s))))
    cv_set(cv_getkey(v_self, "str_cache"), v_s, v_nm)
    return v_nm

unsafe fn cce_soff(v_self: i64, v_s: i64) -> i64:
    return cv_neg(cv_add(131, cv_getkey(v_s, "off")))

unsafe fn cce_toff(v_self: i64, v_i: i64) -> i64:
    return cv_neg(cv_add(cv_add(259, cv_getkey(v_self, "lsize")), cv_mul(131, v_i)))

unsafe fn cce_talloc(v_self: i64) -> i64:
    let v_i: i64 = 0
    v_i = cv_getkey(v_self, "nt")
    cv_field(v_self, "nt", cv_add(cv_getkey(v_self, "nt"), 11))
    if (cv_le(cc_k_temp_slots, v_i)):
        cc_error(cv_text("слишком глубокое выражение в одной инструкции"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(cv_getkey(v_self, "cur"), "line"))
        return 0
    if (cv_less(cv_getkey(v_self, "ntpeak"), cv_getkey(v_self, "nt"))):
        cv_field(v_self, "ntpeak", cv_getkey(v_self, "nt"))
    return v_i

unsafe fn cce_trelease(v_self: i64, v_i: i64) -> i64:
    if (cv_less(v_i, cv_getkey(v_self, "nt"))):
        cv_field(v_self, "nt", v_i)
    return 0

unsafe fn cce_load_from_slot(v_self: i64, v_off: i64, v_t: i64) -> i64:
    let v_opw: i64 = 0
    if cv_truth(cc_is_bool(v_t)):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("movzx eax, byte ptr [rbp"))
        cv_push(pieces_1, cv_format(v_off, "+d"))
        cv_push(pieces_1, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_1))
        return 0
    if cv_truth(cc_is_int(v_t)):
        let logic_3: bool = cv_truth(cv_getkey(v_t, "signed"))
        if logic_3:
            let subject_2: i64 = cv_getkey(v_t, "bits")
            logic_3 = ((cv_equal(subject_2, 67) or cv_equal(subject_2, 131) or cv_equal(subject_2, 259)))
        if (logic_3):
            let dict_4: i64 = cv_dict()
            cv_set(dict_4, 67, cv_text("byte"))
            cv_set(dict_4, 131, cv_text("word"))
            cv_set(dict_4, 259, cv_text("dword"))
            v_opw = cv_subscript(dict_4, cv_getkey(v_t, "bits"))
            let pieces_5: i64 = cv_list()
            cv_push(pieces_5, cv_text("movsx rax, "))
            cv_push(pieces_5, cv_format(v_opw, ""))
            cv_push(pieces_5, cv_text(" ptr [rbp"))
            cv_push(pieces_5, cv_format(v_off, "+d"))
            cv_push(pieces_5, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_5))
        else:
            if (not (cv_truth(cv_getkey(v_t, "signed"))) and (cv_equal(cv_getkey(v_t, "bits"), 67))):
                let pieces_6: i64 = cv_list()
                cv_push(pieces_6, cv_text("movzx rax, byte ptr [rbp"))
                cv_push(pieces_6, cv_format(v_off, "+d"))
                cv_push(pieces_6, cv_text("]"))
                cce_e(v_self, cv_join(cv_text(""), pieces_6))
            else:
                if (not (cv_truth(cv_getkey(v_t, "signed"))) and (cv_equal(cv_getkey(v_t, "bits"), 131))):
                    let pieces_7: i64 = cv_list()
                    cv_push(pieces_7, cv_text("movzx rax, word ptr [rbp"))
                    cv_push(pieces_7, cv_format(v_off, "+d"))
                    cv_push(pieces_7, cv_text("]"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_7))
                else:
                    if (not (cv_truth(cv_getkey(v_t, "signed"))) and (cv_equal(cv_getkey(v_t, "bits"), 259))):
                        let pieces_8: i64 = cv_list()
                        cv_push(pieces_8, cv_text("mov eax, dword ptr [rbp"))
                        cv_push(pieces_8, cv_format(v_off, "+d"))
                        cv_push(pieces_8, cv_text("]"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_8))
                    else:
                        let pieces_9: i64 = cv_list()
                        cv_push(pieces_9, cv_text("mov rax, qword ptr [rbp"))
                        cv_push(pieces_9, cv_format(v_off, "+d"))
                        cv_push(pieces_9, cv_text("]"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_9))
        return 0
    if cv_truth(cc_is_float(v_t)):
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            let pieces_10: i64 = cv_list()
            cv_push(pieces_10, cv_text("movsd xmm0, qword ptr [rbp"))
            cv_push(pieces_10, cv_format(v_off, "+d"))
            cv_push(pieces_10, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_10))
        else:
            let pieces_11: i64 = cv_list()
            cv_push(pieces_11, cv_text("movss xmm0, dword ptr [rbp"))
            cv_push(pieces_11, cv_format(v_off, "+d"))
            cv_push(pieces_11, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_11))
        return 0
    if (cv_truth(cc_is_ptr(v_t)) or cv_truth(cc_is_string(v_t)) or cv_classes(v_t, "TFnPtr")):
        let pieces_12: i64 = cv_list()
        cv_push(pieces_12, cv_text("mov rax, qword ptr [rbp"))
        cv_push(pieces_12, cv_format(v_off, "+d"))
        cv_push(pieces_12, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_12))
        return 0
    if cv_classes(v_t, "TSlice"):
        let pieces_13: i64 = cv_list()
        cv_push(pieces_13, cv_text("lea rax, [rbp"))
        cv_push(pieces_13, cv_format(v_off, "+d"))
        cv_push(pieces_13, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_13))
        return 0
    if cc_is_tagged_value(v_t):
        let pieces_14: i64 = cv_list()
        cv_push(pieces_14, cv_text("lea rax, [rbp"))
        cv_push(pieces_14, cv_format(v_off, "+d"))
        cv_push(pieces_14, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_14))
        return 0
    cc_error(cv_add(cv_text("load не поддерживает "), cc_display(v_t)), 0, 0)
    return 0

unsafe fn cce_int_width(v_self: i64, v_t: i64) -> i64:
    let choice_1: i64 = 0
    if cv_truth(cc_is_int(v_t)):
        choice_1 = cv_max(11, cv_floor(cv_getkey(v_t, "bits"), 67))
    else:
        choice_1 = 67
    return choice_1

unsafe fn cce_store_scalar(v_self: i64, v_off: i64, v_t: i64, v_kind: i64) -> i64:
    let v_w: i64 = 0
    let v_m: i64 = 0
    let v_r: i64 = 0
    if (cv_equal(v_kind, cv_text("float"))):
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            let pieces_1: i64 = cv_list()
            cv_push(pieces_1, cv_text("movsd qword ptr [rbp"))
            cv_push(pieces_1, cv_format(v_off, "+d"))
            cv_push(pieces_1, cv_text("], xmm0"))
            cce_e(v_self, cv_join(cv_text(""), pieces_1))
        else:
            let pieces_2: i64 = cv_list()
            cv_push(pieces_2, cv_text("movss dword ptr [rbp"))
            cv_push(pieces_2, cv_format(v_off, "+d"))
            cv_push(pieces_2, cv_text("], xmm0"))
            cce_e(v_self, cv_join(cv_text(""), pieces_2))
        return 0
    if cv_truth(cc_is_bool(v_t)):
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("mov byte ptr [rbp"))
        cv_push(pieces_3, cv_format(v_off, "+d"))
        cv_push(pieces_3, cv_text("], al"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        return 0
    v_w = cce_int_width(v_self, v_t)
    let dict_4: i64 = cv_dict()
    cv_set(dict_4, 11, cv_text("byte"))
    cv_set(dict_4, 19, cv_text("word"))
    cv_set(dict_4, 35, cv_text("dword"))
    cv_set(dict_4, 67, cv_text("qword"))
    v_m = cv_subscript(dict_4, v_w)
    let dict_5: i64 = cv_dict()
    cv_set(dict_5, 11, cv_text("al"))
    cv_set(dict_5, 19, cv_text("ax"))
    cv_set(dict_5, 35, cv_text("eax"))
    cv_set(dict_5, 67, cv_text("rax"))
    v_r = cv_subscript(dict_5, v_w)
    let pieces_6: i64 = cv_list()
    cv_push(pieces_6, cv_text("mov "))
    cv_push(pieces_6, cv_format(v_m, ""))
    cv_push(pieces_6, cv_text(" ptr [rbp"))
    cv_push(pieces_6, cv_format(v_off, "+d"))
    cv_push(pieces_6, cv_text("], "))
    cv_push(pieces_6, cv_format(v_r, ""))
    cce_e(v_self, cv_join(cv_text(""), pieces_6))
    return 0

unsafe fn cce_val_slot(v_self: i64, v_s: i64) -> i64:
    cce_load_from_slot(v_self, cce_soff(v_self, v_s), cv_getkey(v_s, "typ"))
    return 0

unsafe fn cce_val_global(v_self: i64, v_g: i64) -> i64:
    let v_t: i64 = 0
    let v_lbl: i64 = 0
    let v_opw: i64 = 0
    v_t = cv_getkey(v_g, "glob_type")
    v_lbl = cc_global_label(cv_getkey(v_g, "name"), cv_getkey(v_g, "file"))
    if cv_truth(cc_is_bool(v_t)):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("movzx eax, byte ptr [rip+"))
        cv_push(pieces_1, cv_format(v_lbl, ""))
        cv_push(pieces_1, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_1))
        return 0
    if (cv_truth(cc_is_ptr(v_t)) or cv_truth(cc_is_string(v_t)) or cv_classes(v_t, "TFnPtr")):
        let pieces_2: i64 = cv_list()
        cv_push(pieces_2, cv_text("mov rax, qword ptr [rip+"))
        cv_push(pieces_2, cv_format(v_lbl, ""))
        cv_push(pieces_2, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_2))
        return 0
    if cv_truth(cc_is_int(v_t)):
        if (cv_truth(cv_getkey(v_t, "signed")) and (not (cv_equal(cv_getkey(v_t, "bits"), 515)))):
            let dict_3: i64 = cv_dict()
            cv_set(dict_3, 67, cv_text("byte"))
            cv_set(dict_3, 131, cv_text("word"))
            cv_set(dict_3, 259, cv_text("dword"))
            v_opw = cv_subscript(dict_3, cv_getkey(v_t, "bits"))
            let pieces_4: i64 = cv_list()
            cv_push(pieces_4, cv_text("movsx rax, "))
            cv_push(pieces_4, cv_format(v_opw, ""))
            cv_push(pieces_4, cv_text(" ptr [rip+"))
            cv_push(pieces_4, cv_format(v_lbl, ""))
            cv_push(pieces_4, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_4))
        else:
            let logic_6: bool = not (cv_truth(cv_getkey(v_t, "signed")))
            if logic_6:
                let subject_5: i64 = cv_getkey(v_t, "bits")
                logic_6 = ((cv_equal(subject_5, 67) or cv_equal(subject_5, 131)))
            if (logic_6):
                let dict_7: i64 = cv_dict()
                cv_set(dict_7, 67, cv_text("byte"))
                cv_set(dict_7, 131, cv_text("word"))
                v_opw = cv_subscript(dict_7, cv_getkey(v_t, "bits"))
                let pieces_8: i64 = cv_list()
                cv_push(pieces_8, cv_text("movzx rax, "))
                cv_push(pieces_8, cv_format(v_opw, ""))
                cv_push(pieces_8, cv_text(" ptr [rip+"))
                cv_push(pieces_8, cv_format(v_lbl, ""))
                cv_push(pieces_8, cv_text("]"))
                cce_e(v_self, cv_join(cv_text(""), pieces_8))
            else:
                if (not (cv_truth(cv_getkey(v_t, "signed"))) and (cv_equal(cv_getkey(v_t, "bits"), 259))):
                    let pieces_9: i64 = cv_list()
                    cv_push(pieces_9, cv_text("mov eax, dword ptr [rip+"))
                    cv_push(pieces_9, cv_format(v_lbl, ""))
                    cv_push(pieces_9, cv_text("]"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_9))
                else:
                    let pieces_10: i64 = cv_list()
                    cv_push(pieces_10, cv_text("mov rax, qword ptr [rip+"))
                    cv_push(pieces_10, cv_format(v_lbl, ""))
                    cv_push(pieces_10, cv_text("]"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_10))
        return 0
    if cv_truth(cc_is_float(v_t)):
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            let pieces_11: i64 = cv_list()
            cv_push(pieces_11, cv_text("movsd xmm0, qword ptr [rip+"))
            cv_push(pieces_11, cv_format(v_lbl, ""))
            cv_push(pieces_11, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_11))
        else:
            let pieces_12: i64 = cv_list()
            cv_push(pieces_12, cv_text("movss xmm0, dword ptr [rip+"))
            cv_push(pieces_12, cv_format(v_lbl, ""))
            cv_push(pieces_12, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_12))
        return 0
    cc_error(cv_add(cv_text("глобал "), cc_display(v_t)), 0, cv_getkey(v_g, "line"))
    return 0

unsafe fn cce_eaddr(v_self: i64, v_e: i64) -> i64:
    let v_s: i64 = 0
    let v_g: i64 = 0
    let v_off: i64 = 0
    let v_bt: i64 = 0
    let v_tmp: i64 = 0
    let v_oob: i64 = 0
    let v_in_range: i64 = 0
    let v_msg: i64 = 0
    let v_idx: i64 = 0
    let v_ok: i64 = 0
    let v_elem: i64 = 0
    let v_sz: i64 = 0
    let v_t: i64 = 0
    if cv_classes(v_e, "SliceExpr"):
        cce_emit_slice(v_self, v_e)
        return cv_getkey(v_e, "type")
    if cv_classes(v_e, "VarRef"):
        v_s = cv_get(v_e, cv_text("slot"), 0)
        if (not (v_s == 0)):
            let pieces_1: i64 = cv_list()
            cv_push(pieces_1, cv_text("lea rax, [rbp"))
            cv_push(pieces_1, cv_format(cce_soff(v_self, v_s), "+d"))
            cv_push(pieces_1, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_1))
            return cv_getkey(v_s, "typ")
        if (cv_equal(cv_getkey(v_e, "kind"), cv_text("glob"))):
            v_g = cv_subscript(cv_getkey(cv_getkey(v_self, "sem"), "globals"), cv_getkey(v_e, "name"))
            let pieces_2: i64 = cv_list()
            cv_push(pieces_2, cv_text("lea rax, [rip+"))
            cv_push(pieces_2, cv_format(cc_global_label(cv_getkey(v_g, "name"), cv_getkey(v_g, "file")), ""))
            cv_push(pieces_2, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_2))
            return cv_getkey(v_g, "glob_type")
        cc_error(cv_cat(cv_format(cv_getkey(v_e, "name"), ""), cv_text(": не адресуемое")), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
        return 0
    if cv_classes(v_e, "Member"):
        if cv_has(v_e, cv_text("enum_value")):
            cc_error(cv_text("вариант enum не имеет адреса"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
            return 0
        v_off = cv_getkey(v_e, "toff")
        if cv_truth(cc_is_ptr(cv_getkey(cv_getkey(v_e, "base"), "type"))):
            cce_expr_value(v_self, cv_getkey(v_e, "base"), 0)
            if cv_truth(v_off):
                cce_e(v_self, cv_cat(cv_text("add rax, "), cv_format(v_off, "")))
            return cv_getkey(v_e, "field_type")
        cce_eaddr(v_self, cv_getkey(v_e, "base"))
        if cv_truth(v_off):
            cce_e(v_self, cv_cat(cv_text("add rax, "), cv_format(v_off, "")))
        return cv_getkey(v_e, "field_type")
    if cv_classes(v_e, "Index"):
        v_bt = cv_getkey(cv_getkey(v_e, "base"), "type")
        v_tmp = cce_talloc(v_self)
        if cv_truth(cc_is_array(v_bt)):
            cce_eaddr(v_self, cv_getkey(v_e, "base"))
        else:
            if cv_classes(v_bt, "TSlice"):
                cce_eaddr(v_self, cv_getkey(v_e, "base"))
            else:
                cce_expr_value(v_self, cv_getkey(v_e, "base"), 0)
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("mov qword ptr [rbp"))
        cv_push(pieces_3, cv_format(cce_toff(v_self, v_tmp), "+d"))
        cv_push(pieces_3, cv_text("], rax"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        cce_expr_value(v_self, cv_getkey(v_e, "idx"), cc_int(CV_TRUE, 515))
        cce_e(v_self, cv_text("mov rcx, rax"))
        if cv_truth(cc_is_array(v_bt)):
            v_oob = cce_lbl(v_self)
            v_in_range = cce_lbl(v_self)
            if cv_truth(cv_getkey(cv_getkey(cv_getkey(v_e, "idx"), "type"), "signed")):
                cce_e(v_self, cv_text("test rcx, rcx"))
                cce_e(v_self, cv_cat(cv_text("js "), cv_format(v_oob, "")))
            cce_e(v_self, cv_cat(cv_text("mov rdx, "), cv_format(cv_getkey(v_bt, "n"), "")))
            cce_e(v_self, cv_text("cmp rcx, rdx"))
            cce_e(v_self, cv_cat(cv_text("jae "), cv_format(v_oob, "")))
            cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_in_range, "")))
            cce_label(v_self, v_oob, 0)
            v_msg = cce_slconst(v_self, cv_text("volt: array index out of bounds\n"))
            let pieces_4: i64 = cv_list()
            cv_push(pieces_4, cv_text("lea rdi, [rip+"))
            cv_push(pieces_4, cv_format(v_msg, ""))
            cv_push(pieces_4, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_4))
            cce_e(v_self, cv_text("call VOLT_rt_panic"))
            cce_label(v_self, v_in_range, 0)
        else:
            if cv_truth(cc_is_string(v_bt)):
                v_idx = cce_talloc(v_self)
                v_oob = cce_lbl(v_self)
                v_in_range = cce_lbl(v_self)
                let pieces_5: i64 = cv_list()
                cv_push(pieces_5, cv_text("mov qword ptr [rbp"))
                cv_push(pieces_5, cv_format(cce_toff(v_self, v_idx), "+d"))
                cv_push(pieces_5, cv_text("], rcx"))
                cce_e(v_self, cv_join(cv_text(""), pieces_5))
                if cv_truth(cv_getkey(cv_getkey(cv_getkey(v_e, "idx"), "type"), "signed")):
                    cce_e(v_self, cv_text("test rcx, rcx"))
                    cce_e(v_self, cv_cat(cv_text("js "), cv_format(v_oob, "")))
                let pieces_6: i64 = cv_list()
                cv_push(pieces_6, cv_text("mov rdi, qword ptr [rbp"))
                cv_push(pieces_6, cv_format(cce_toff(v_self, v_tmp), "+d"))
                cv_push(pieces_6, cv_text("]"))
                cce_e(v_self, cv_join(cv_text(""), pieces_6))
                cce_e(v_self, cv_text("test rdi, rdi"))
                cce_e(v_self, cv_cat(cv_text("jz "), cv_format(v_oob, "")))
                cce_e(v_self, cv_text("call VOLT_rt_strlen"))
                cce_e(v_self, cv_text("mov rdx, rax"))
                let pieces_7: i64 = cv_list()
                cv_push(pieces_7, cv_text("mov rcx, qword ptr [rbp"))
                cv_push(pieces_7, cv_format(cce_toff(v_self, v_idx), "+d"))
                cv_push(pieces_7, cv_text("]"))
                cce_e(v_self, cv_join(cv_text(""), pieces_7))
                cce_e(v_self, cv_text("cmp rcx, rdx"))
                cce_e(v_self, cv_cat(cv_text("jae "), cv_format(v_oob, "")))
                cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_in_range, "")))
                cce_label(v_self, v_oob, 0)
                v_msg = cce_slconst(v_self, cv_text("volt: string index out of bounds\n"))
                let pieces_8: i64 = cv_list()
                cv_push(pieces_8, cv_text("lea rdi, [rip+"))
                cv_push(pieces_8, cv_format(v_msg, ""))
                cv_push(pieces_8, cv_text("]"))
                cce_e(v_self, cv_join(cv_text(""), pieces_8))
                cce_e(v_self, cv_text("call VOLT_rt_panic"))
                cce_label(v_self, v_in_range, 0)
                let pieces_9: i64 = cv_list()
                cv_push(pieces_9, cv_text("mov rcx, qword ptr [rbp"))
                cv_push(pieces_9, cv_format(cce_toff(v_self, v_idx), "+d"))
                cv_push(pieces_9, cv_text("]"))
                cce_e(v_self, cv_join(cv_text(""), pieces_9))
            else:
                if cv_classes(v_bt, "TSlice"):
                    v_idx = cce_talloc(v_self)
                    let pieces_10: i64 = cv_list()
                    cv_push(pieces_10, cv_text("mov qword ptr [rbp"))
                    cv_push(pieces_10, cv_format(cce_toff(v_self, v_idx), "+d"))
                    cv_push(pieces_10, cv_text("], rcx"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_10))
                    let pieces_11: i64 = cv_list()
                    cv_push(pieces_11, cv_text("mov rdx, qword ptr [rbp"))
                    cv_push(pieces_11, cv_format(cce_toff(v_self, v_tmp), "+d"))
                    cv_push(pieces_11, cv_text("]"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_11))
                    if cv_truth(cv_getkey(cv_getkey(cv_getkey(v_e, "idx"), "type"), "signed")):
                        v_oob = cce_lbl(v_self)
                        v_in_range = cce_lbl(v_self)
                        cce_e(v_self, cv_text("test rcx, rcx"))
                        cce_e(v_self, cv_cat(cv_text("js "), cv_format(v_oob, "")))
                        cce_e(v_self, cv_text("mov rdx, qword ptr [rdx + 8]"))
                        cce_e(v_self, cv_text("cmp rcx, rdx"))
                        cce_e(v_self, cv_cat(cv_text("jae "), cv_format(v_oob, "")))
                        cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_in_range, "")))
                        cce_label(v_self, v_oob, 0)
                        cce_emit_panic(v_self, cv_text("volt: slice index out of bounds\n"))
                        cce_label(v_self, v_in_range, 0)
                    else:
                        v_oob = cce_lbl(v_self)
                        cce_e(v_self, cv_text("mov rdx, qword ptr [rdx + 8]"))
                        cce_e(v_self, cv_text("cmp rcx, rdx"))
                        cce_e(v_self, cv_cat(cv_text("jae "), cv_format(v_oob, "")))
                        v_ok = cce_lbl(v_self)
                        cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_ok, "")))
                        cce_label(v_self, v_oob, 0)
                        cce_emit_panic(v_self, cv_text("volt: slice index out of bounds\n"))
                        cce_label(v_self, v_ok, 0)
                    let pieces_12: i64 = cv_list()
                    cv_push(pieces_12, cv_text("mov rcx, qword ptr [rbp"))
                    cv_push(pieces_12, cv_format(cce_toff(v_self, v_idx), "+d"))
                    cv_push(pieces_12, cv_text("]"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_12))
        let pieces_13: i64 = cv_list()
        cv_push(pieces_13, cv_text("mov rax, qword ptr [rbp"))
        cv_push(pieces_13, cv_format(cce_toff(v_self, v_tmp), "+d"))
        cv_push(pieces_13, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_13))
        if cv_classes(v_bt, "TSlice"):
            cce_e(v_self, cv_text("mov rax, qword ptr [rax]"))
            if (cv_less(11, cc_type_size(cv_getkey(v_bt, "elem")))):
                cce_e(v_self, cv_cat(cv_text("imul rcx, rcx, "), cv_format(cc_type_size(cv_getkey(v_bt, "elem")), "")))
            cce_e(v_self, cv_text("add rax, rcx"))
            cce_trelease(v_self, v_tmp)
            return cv_getkey(v_bt, "elem")
        let choice_14: i64 = 0
        if (cv_truth(cc_is_array(v_bt)) or cv_truth(cc_is_ptr(v_bt))):
            choice_14 = cv_getkey(v_bt, "elem")
        else:
            let choice_15: i64 = 0
            if cv_truth(cc_is_string(v_bt)):
                choice_15 = cc_k_char_type
            else:
                choice_15 = 0
            choice_14 = choice_15
        v_elem = choice_14
        let choice_16: i64 = 0
        if cv_truth(v_elem):
            choice_16 = cc_type_size(v_elem)
        else:
            choice_16 = 67
        v_sz = choice_16
        if (cv_less(11, v_sz)):
            cce_e(v_self, cv_cat(cv_text("imul rcx, rcx, "), cv_format(v_sz, "")))
        cce_e(v_self, cv_text("add rax, rcx"))
        return v_elem
    if cv_classes(v_e, "Deref"):
        v_t = cce_expr_value(v_self, cv_getkey(v_e, "x"), 0)
        if not (cv_truth(cc_is_ptr(v_t))):
            cc_error(cv_text("* не указатель"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
            return 0
        return cv_getkey(v_t, "elem")
    if cv_classes(v_e, "Cast") and cv_truth(cv_getkey(v_e, "array_len_address")):
        let operand: i64 = cv_getkey(v_e, "x")
        let typ: i64 = cv_getkey(v_e, "type")
        if (cv_classes(typ, "TArray") or cv_classes(typ, "TStruct")) and cv_equal(typ, cv_getkey(operand, "type")):
            return cce_eaddr(v_self, operand)
    if (cv_classes(v_e, "Call") and (cv_equal(cv_get(v_e, cv_text("kindt"), 0), cv_text("ctor")))):
        if cv_truth(cv_getkey(v_e, "array_len_address")):
            let temporary: i64 = cv_getkey(v_e, "temp_slot")
            let offset: i64 = cce_soff(v_self, cv_subscript(cv_getkey(v_self, "slots"), temporary))
            cce_emit_ctor(v_self, v_e, offset)
            cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), offset))
            return cv_getkey(v_e, "type")
        cc_error(cv_text("конструктор структуры не адресуемый"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
        return 0
    if cv_classes(v_e, "Call") and (cv_classes(cv_getkey(v_e, "type"), "TStruct") or cv_classes(cv_getkey(v_e, "type"), "TSlice")):
        cce_expr_call(v_self, v_e)
        return cv_getkey(v_e, "type")
    if cv_classes(v_e, "Unary") and cv_name(cv_getkey(v_e, "op"), "?") and cv_classes(cv_getkey(v_e, "type"), "TStruct"):
        return cce_expr_propagate(v_self, v_e)
    cc_error(cv_text("невозможно взять адрес этого выражения"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
    return 0

unsafe fn cce_emit_propagated_wrapper_return(v_self: i64, v_typ: i64, v_addr_temp: i64) -> i64:
    let v_ret_type: i64 = 0
    let v_snapshot: i64 = 0
    let v_snap_off: i64 = 0
    let v_src_payload: i64 = 0
    let v_saved_nt: i64 = 0
    let v_saved_floor: i64 = 0
    let v_sret: i64 = 0
    v_ret_type = cv_getkey(cv_getkey(v_self, "cur"), "sig_ret")
    v_snapshot = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(cv_getkey(v_self, "cur"), "ret_snapshot_slot"))
    v_snap_off = cce_soff(v_self, v_snapshot)
    cce_zero_range(v_self, v_snap_off, cc_type_size(v_ret_type))
    let choice_1: i64 = 0
    if (cv_equal(cv_getkey(v_typ, "name"), cv_text("Option"))):
        choice_1 = 3
    else:
        choice_1 = 11
    let pieces_2: i64 = cv_list()
    cv_push(pieces_2, cv_text("mov qword ptr [rbp"))
    cv_push(pieces_2, cv_format(v_snap_off, "+d"))
    cv_push(pieces_2, cv_text("], "))
    cv_push(pieces_2, cv_format(choice_1, ""))
    cce_e(v_self, cv_join(cv_text(""), pieces_2))
    if (cv_equal(cv_getkey(v_typ, "name"), cv_text("Result"))):
        v_src_payload = cce_talloc(v_self)
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("mov rax, qword ptr [rbp"))
        cv_push(pieces_3, cv_format(cce_toff(v_self, v_addr_temp), "+d"))
        cv_push(pieces_3, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        cce_e(v_self, cv_cat(cv_text("add rax, "), cv_format(cv_getkey(v_typ, "payload_off"), "")))
        let pieces_4: i64 = cv_list()
        cv_push(pieces_4, cv_text("mov qword ptr [rbp"))
        cv_push(pieces_4, cv_format(cce_toff(v_self, v_src_payload), "+d"))
        cv_push(pieces_4, cv_text("], rax"))
        cce_e(v_self, cv_join(cv_text(""), pieces_4))
        let pieces_5: i64 = cv_list()
        cv_push(pieces_5, cv_text("mov rsi, qword ptr [rbp"))
        cv_push(pieces_5, cv_format(cce_toff(v_self, v_src_payload), "+d"))
        cv_push(pieces_5, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_5))
        let pieces_6: i64 = cv_list()
        cv_push(pieces_6, cv_text("lea rdi, [rbp"))
        cv_push(pieces_6, cv_format(cv_add(v_snap_off, cv_getkey(v_ret_type, "payload_off")), "+d"))
        cv_push(pieces_6, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_6))
        cce_copy_bytes(v_self, cc_type_size(cv_subscript(cv_getkey(v_typ, "args"), 11)))
        cce_trelease(v_self, v_src_payload)
    v_saved_nt = cv_getkey(v_self, "nt")
    v_saved_floor = cv_getkey(v_self, "for_floor")
    cv_field(v_self, "for_floor", v_saved_nt)
    cce_emit_cleanup_scopes(v_self, cv_length(cv_getkey(v_self, "defer_frames")))
    cv_field(v_self, "for_floor", v_saved_floor)
    cv_field(v_self, "nt", v_saved_nt)
    v_sret = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(cv_getkey(v_self, "cur"), "sret_slot"))
    let pieces_7: i64 = cv_list()
    cv_push(pieces_7, cv_text("mov rdi, qword ptr [rbp"))
    cv_push(pieces_7, cv_format(cce_soff(v_self, v_sret), "+d"))
    cv_push(pieces_7, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_7))
    let pieces_8: i64 = cv_list()
    cv_push(pieces_8, cv_text("lea rsi, [rbp"))
    cv_push(pieces_8, cv_format(v_snap_off, "+d"))
    cv_push(pieces_8, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_8))
    cce_copy_bytes(v_self, cc_type_size(v_ret_type))
    cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(cv_getkey(v_self, "ret_l"), "")))
    return 0

unsafe fn cce_expr_propagate(v_self: i64, v_e: i64) -> i64:
    let v_typ: i64 = 0
    let v_src: i64 = 0
    let v_fail: i64 = 0
    let v_done: i64 = 0
    let v_success_tag: i64 = 0
    v_typ = cv_getkey(v_e, "wrapper_type")
    v_src = cce_talloc(v_self)
    let operand: i64 = cv_getkey(v_e, "x")
    cce_expr_value(v_self, operand, 0)
    cce_e(v_self, cv_mod(cv_text("mov qword ptr [rbp%+d], rax"), cce_toff(v_self, v_src)))
    # A failing owned Result has no buffer; its error remains available to snapshot.
    cce_owner_flag(v_self, cv_getkey(operand, "owner_transfer"), 0)
    v_fail = cce_lbl(v_self)
    v_done = cce_lbl(v_self)
    let choice_3: i64 = 0
    if (cv_equal(cv_getkey(v_typ, "name"), cv_text("Option"))):
        choice_3 = 11
    else:
        choice_3 = 3
    v_success_tag = choice_3
    cce_e(v_self, cv_mod(cv_text("cmp qword ptr [rax], %d"), v_success_tag))
    cce_e(v_self, cv_cat(cv_text("jne "), cv_format(v_fail, "")))
    if cv_truth(cv_getkey(v_typ, "payload_off")):
        cce_e(v_self, cv_cat(cv_text("add rax, "), cv_format(cv_getkey(v_typ, "payload_off"), "")))
    let payload: i64 = cv_at(cv_getkey(v_typ, "args"), 0)
    if cv_classes(payload, "TStruct") or cc_is_tagged_value(payload):
        let off: i64 = cce_soff(v_self, cv_at(cv_getkey(v_self, "slots"), cv_index(cv_getkey(v_e, "temp_slot"))))
        cce_copy_from_rax(v_self, off, cc_type_size(payload))
        cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), off))
    else:
        cce_load_from_mem(v_self, payload)
    cce_owner_flag(v_self, cv_getkey(v_e, "owner_result"), 1)
    cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_done, "")))
    cce_label(v_self, v_fail, 0)
    cce_emit_propagated_wrapper_return(v_self, v_typ, v_src)
    cce_label(v_self, v_done, 0)
    cce_trelease(v_self, v_src)
    return payload

unsafe fn cce_expr_value(v_self: i64, v_e: i64, v_hint_int: i64) -> i64:
    let v_t: i64 = 0
    let v_lbl: i64 = 0
    let v_val: i64 = 0
    let v_typ: i64 = 0
    let v_s: i64 = 0
    let v_g: i64 = 0
    let v_temp: i64 = 0
    let v_at: i64 = 0
    v_t = cv_get(v_e, cv_text("type"), 0)
    if ((v_t == 0) and cv_classes(v_e, "Call") and (cv_equal(cv_getkey(v_e, "name"), cv_text("print")))):
        cc_error(cv_text("print ничего не возвращает"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
        return 0
    if cv_classes(v_e, "SizeAlignExpr"):
        cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(cv_getkey(v_e, "const_value"), "")))
        return cv_getkey(v_e, "type")
    if cv_classes(v_e, "IntLit"):
        cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(cv_getkey(v_e, "val"), "")))
        return cv_getkey(v_e, "type")
    if cv_classes(v_e, "FloatLit"):
        v_lbl = cce_fconst(v_self, cv_getkey(v_e, "val"))
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("movsd xmm0, qword ptr [rip+"))
        cv_push(pieces_1, cv_format(v_lbl, ""))
        cv_push(pieces_1, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_1))
        return cc_TFloat(515)
    if cv_classes(v_e, "CharLit"):
        cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(cv_ordinal(cv_getkey(v_e, "val")), "")))
        return cc_k_char_type
    if cv_classes(v_e, "BoolLit"):
        let choice_2: i64 = 0
        if cv_truth(cv_getkey(v_e, "val")):
            choice_2 = 11
        else:
            choice_2 = 3
        cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(choice_2, "")))
        return cc_TBool()
    if cv_classes(v_e, "StrLit"):
        v_lbl = cce_slconst(v_self, cv_getkey(v_e, "val"))
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("lea rax, [rip+"))
        cv_push(pieces_3, cv_format(v_lbl, ""))
        cv_push(pieces_3, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        return cv_getkey(cv_getkey(v_self, "sem"), "_string")
    if cv_classes(v_e, "VarRef") or cv_has(v_e, cv_text("const_binding")):
        if cv_has(v_e, cv_text("const_binding")):
            v_val = cv_subscript(cv_getkey(v_e, "const_binding"), 11)
            v_typ = cv_subscript(cv_getkey(v_e, "const_binding"), 3)
            if cv_truth(cc_is_float(v_typ)):
                v_lbl = cce_fconst(v_self, v_val)
                let pieces_4: i64 = cv_list()
                cv_push(pieces_4, cv_text("movsd xmm0, qword ptr [rip+"))
                cv_push(pieces_4, cv_format(v_lbl, ""))
                cv_push(pieces_4, cv_text("]"))
                cce_e(v_self, cv_join(cv_text(""), pieces_4))
                if (cv_equal(cv_getkey(v_typ, "bits"), 259)):
                    cce_e(v_self, cv_text("cvtsd2ss xmm0, xmm0"))
            else:
                cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(cv_int(v_val, 83), "")))
            return v_typ
        v_s = cv_get(v_e, cv_text("slot"), 0)
        if (not (v_s == 0)):
            cce_val_slot(v_self, v_s)
            return cv_getkey(v_s, "typ")
        if (cv_equal(cv_getkey(v_e, "kind"), cv_text("glob"))):
            v_g = cv_subscript(cv_getkey(cv_getkey(v_self, "sem"), "globals"), cv_getkey(v_e, "name"))
            cce_val_global(v_self, v_g)
            return cv_getkey(v_g, "glob_type")
        cc_error(cv_add(cv_text("нет значения "), cv_getkey(v_e, "name")), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
        return 0
    if cv_classes(v_e, "Unary"):
        if ((cv_equal(cv_getkey(v_e, "op"), cv_text("-"))) and cv_classes(cv_getkey(v_e, "x"), "IntLit") and (cv_equal(cv_getkey(cv_getkey(v_e, "x"), "val"), cv_shl(11, 507)))):
            cce_e(v_self, cv_text("mov rax, -9223372036854775808"))
            return cc_int(CV_TRUE, 515)
        if (cv_equal(cv_getkey(v_e, "op"), cv_text("?"))):
            return cce_expr_propagate(v_self, v_e)
        if (cv_equal(cv_getkey(v_e, "op"), cv_text("not"))):
            cce_expr_truthy(v_self, cv_getkey(v_e, "x"))
            cce_e(v_self, cv_text("xor al, 1"))
            return cc_TBool()
        v_t = cce_expr_value(v_self, cv_getkey(v_e, "x"), 0)
        if (cv_equal(cv_getkey(v_e, "op"), cv_text("-"))):
            if cv_truth(cc_is_float(v_t)):
                # Subtracting from +0.0 does not negate the sign of +0.0.
                let mask: i64 = cce_float_sign_mask(v_self, cv_getkey(v_t, "bits"), true)
                cce_e(v_self, cv_cat(cv_cat(cv_text("xorpd xmm0, xmmword ptr [rip+"), mask), cv_text("]")))
                return v_t
            cce_e(v_self, cv_text("neg rax"))
            cce_check_neg_overflow(v_self, v_t)
            cce_narrow(v_self, v_t)
            return v_t
        cc_error(cv_add(cv_text("оператор "), cv_getkey(v_e, "op")), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
        return 0
    if cv_classes(v_e, "Binary"):
        return cce_expr_binary(v_self, v_e)
    if cc_is_sum_ctor(v_e):
        v_temp = cv_getkey(v_e, "temp_slot")
        let off: i64 = 0
        if v_temp != 0:
            off = cce_soff(v_self, cv_subscript(cv_getkey(v_self, "slots"), v_temp))
        else:
            off = cce_toff(v_self, cce_talloc(v_self))
        cce_emit_sum_ctor(v_self, v_e, off)
        cce_owner_flag(v_self, cv_getkey(v_e, "owner_result"), 1)
        cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), off))
        return v_t
    if cv_classes(v_e, "Call"):
        return cce_expr_call(v_self, v_e)
    if cv_classes(v_e, "Index"):
        v_at = cce_eaddr(v_self, v_e)
        return cce_load_from_mem(v_self, v_at)
    if cv_classes(v_e, "SliceExpr"):
        return cce_eaddr(v_self, v_e)
    if cv_classes(v_e, "Member"):
        if cv_has(v_e, cv_text("enum_value")):
            cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(cv_getkey(v_e, "enum_value"), "")))
            return cv_getkey(v_e, "type")
        v_at = cce_eaddr(v_self, v_e)
        return cce_load_from_mem(v_self, v_at)
    if cv_classes(v_e, "Cast"):
        return cce_expr_cast(v_self, v_e)
    if cv_classes(v_e, "Deref"):
        v_at = cce_eaddr(v_self, v_e)
        return cce_load_from_mem(v_self, v_at)
    if cv_classes(v_e, "AddrOf"):
        cce_eaddr(v_self, cv_getkey(v_e, "x"))
        return cc_TPtr(cv_getkey(cv_getkey(v_e, "x"), "type"))
    if cv_classes(v_e, "ArrayLit"):
        cc_error(cv_text("массив-список нельзя использовать как значение"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
        return 0
    cc_error(cv_add(cv_text("не могу вычислить значение "), cv_typename(v_e)), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
    return 0

unsafe fn cce_load_from_mem(v_self: i64, v_t: i64) -> i64:
    if cv_truth(cc_is_bool(v_t)):
        cce_e(v_self, cv_text("movzx eax, byte ptr [rax]"))
        return v_t
    if cv_truth(cc_is_float(v_t)):
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            cce_e(v_self, cv_text("movsd xmm0, qword ptr [rax]"))
        else:
            cce_e(v_self, cv_text("movss xmm0, dword ptr [rax]"))
        return v_t
    if cv_truth(cc_is_int(v_t)):
        if (cv_truth(cc_is_bool(v_t)) or ((cv_getkey(v_t, "signed") == CV_FALSE) and (cv_equal(cv_getkey(v_t, "bits"), 67)))):
            cce_e(v_self, cv_text("movzx eax, byte ptr [rax]"))
        else:
            if ((cv_getkey(v_t, "signed") == CV_FALSE) and (cv_equal(cv_getkey(v_t, "bits"), 131))):
                cce_e(v_self, cv_text("movzx eax, word ptr [rax]"))
            else:
                if ((cv_getkey(v_t, "signed") == CV_FALSE) and (cv_equal(cv_getkey(v_t, "bits"), 259))):
                    cce_e(v_self, cv_text("mov eax, dword ptr [rax]"))
                else:
                    if (cv_truth(cv_getkey(v_t, "signed")) and (cv_equal(cv_getkey(v_t, "bits"), 259))):
                        cce_e(v_self, cv_text("movsxd rax, dword ptr [rax]"))
                    else:
                        if (cv_truth(cv_getkey(v_t, "signed")) and (cv_equal(cv_getkey(v_t, "bits"), 131))):
                            cce_e(v_self, cv_text("movsx rax, word ptr [rax]"))
                        else:
                            if (cv_truth(cv_getkey(v_t, "signed")) and (cv_equal(cv_getkey(v_t, "bits"), 67))):
                                cce_e(v_self, cv_text("movsx rax, byte ptr [rax]"))
                            else:
                                cce_e(v_self, cv_text("mov rax, qword ptr [rax]"))
        return v_t
    if (cv_truth(cc_is_ptr(v_t)) or cv_truth(cc_is_string(v_t)) or cv_classes(v_t, "TFnPtr")):
        cce_e(v_self, cv_text("mov rax, qword ptr [rax]"))
        return v_t
    if cv_classes(v_t, "TSlice"):
        return v_t
    if cc_is_tagged_value(v_t):
        return v_t
    cc_error(cv_add(cv_text("load_from_mem "), cc_display(v_t)), 0, 0)
    return 0

unsafe fn cce_expr_binary(v_self: i64, v_e: i64) -> i64:
    let v_op: i64 = 0
    let v_name: i64 = 0
    let v_fn: i64 = 0
    let v_result: i64 = 0
    let v_lf: i64 = 0
    let v_le: i64 = 0
    let v_rt: i64 = 0
    let v_tc: i64 = 0
    let v_i: i64 = 0
    let v_pw: i64 = 0
    let v_ins: i64 = 0
    let v_pl: i64 = 0
    let v_pr: i64 = 0
    let v_sz: i64 = 0
    v_op = cv_getkey(v_e, "op")
    if cv_truth(cv_get(v_e, cv_text("sugar"), 0)):
        v_name = cv_at(cv_getkey(v_e, "sugar"), 0)
        v_fn = cv_get(cv_getkey(cv_getkey(v_self, "sem"), "fns"), v_name, 0)
        if (v_fn == 0):
            let pieces_2: i64 = cv_list()
            cv_push(pieces_2, cv_text("сахар "))
            cv_push(pieces_2, cv_format(v_op, ""))
            cv_push(pieces_2, cv_text(": модуль str не загружен"))
            cc_error(cv_join(cv_text(""), pieces_2), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
            return 0
        let v_args: i64 = cv_pair(cv_getkey(v_e, "l"), cv_getkey(v_e, "r"))
        v_result = cce_call_gen(v_self, v_e, v_args, cv_getkey(v_fn, "sig_params"), cv_getkey(v_fn, "sig_ret"), cc_function_label(cv_getkey(v_fn, "name"), cv_getkey(v_fn, "file")))
        if cv_truth(cv_get(v_e, cv_text("negate_sugar"), CV_FALSE)):
            cce_e(v_self, cv_text("test rax, rax"))
            cce_e(v_self, cv_text("setz al"))
            cce_e(v_self, cv_text("movzx eax, al"))
            return cc_TBool()
        return v_result
    if ((cv_equal(v_op, cv_text("and")) or cv_equal(v_op, cv_text("or")))):
        cce_expr_truthy(v_self, cv_getkey(v_e, "l"))
        v_lf = cce_lbl(v_self)
        v_le = cce_lbl(v_self)
        if (cv_equal(v_op, cv_text("and"))):
            cce_e(v_self, cv_text("test rax, rax"))
            cce_e(v_self, cv_cat(cv_text("jz "), cv_format(v_lf, "")))
            cce_expr_truthy(v_self, cv_getkey(v_e, "r"))
            cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_le, "")))
            cce_label(v_self, v_lf, 0)
            cce_e(v_self, cv_text("xor eax, eax"))
            cce_label(v_self, v_le, 0)
        else:
            v_rt = cce_lbl(v_self)
            cce_e(v_self, cv_text("test rax, rax"))
            cce_e(v_self, cv_cat(cv_text("jnz "), cv_format(v_rt, "")))
            cce_expr_truthy(v_self, cv_getkey(v_e, "r"))
            cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_le, "")))
            cce_label(v_self, v_rt, 0)
            cce_e(v_self, cv_text("mov eax, 1"))
            cce_label(v_self, v_le, 0)
        return cc_TBool()
    if cv_truth(cc_is_float(cv_getkey(cv_getkey(v_e, "l"), "type"))):
        let choice_6: i64 = cv_get(v_e, cv_text("common"), 0)
        if not cv_truth(choice_6):
            choice_6 = cv_getkey(cv_getkey(v_e, "l"), "type")
        v_tc = choice_6
        v_i = cce_talloc(v_self)
        cce_expr_value(v_self, cv_getkey(v_e, "l"), 0)
        cce_fconv(v_self, cv_getkey(cv_getkey(v_e, "l"), "type"), v_tc)
        cce_store_scalar(v_self, cce_toff(v_self, v_i), v_tc, cv_text("float"))
        cce_expr_value(v_self, cv_getkey(v_e, "r"), 0)
        cce_fconv(v_self, cv_getkey(cv_getkey(v_e, "r"), "type"), v_tc)
        let choice_7: i64 = 0
        if (cv_equal(cv_getkey(v_tc, "bits"), 515)):
            choice_7 = cv_text("qword")
        else:
            choice_7 = cv_text("dword")
        v_pw = choice_7
        let choice_8: i64 = 0
        if (cv_equal(cv_getkey(v_tc, "bits"), 515)):
            choice_8 = cv_text("movsd xmm1")
        else:
            choice_8 = cv_text("movss xmm1")
        v_ins = choice_8
        let pieces_9: i64 = cv_list()
        cv_push(pieces_9, cv_format(v_ins, ""))
        cv_push(pieces_9, cv_text(", "))
        cv_push(pieces_9, cv_format(v_pw, ""))
        cv_push(pieces_9, cv_text(" ptr [rbp"))
        cv_push(pieces_9, cv_format(cce_toff(v_self, v_i), "+d"))
        cv_push(pieces_9, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_9))
        cce_trelease(v_self, v_i)
        return cce_float_op(v_self, v_e, v_tc)
    if ((cv_truth(cc_is_ptr(cv_getkey(cv_getkey(v_e, "l"), "type"))) and ((cv_equal(v_op, cv_text("+")) or cv_equal(v_op, cv_text("-"))))) or (cv_truth(cc_is_ptr(cv_getkey(cv_getkey(v_e, "r"), "type"))) and (cv_equal(v_op, cv_text("+"))))):
        let choice_10: i64 = 0
        if cv_truth(cc_is_ptr(cv_getkey(cv_getkey(v_e, "r"), "type"))):
            choice_10 = cv_pair(cv_getkey(v_e, "r"), cv_getkey(v_e, "l"))
        else:
            choice_10 = cv_pair(cv_getkey(v_e, "l"), cv_getkey(v_e, "r"))
        let unpack_11: i64 = choice_10
        v_pl = cv_at(unpack_11, 0)
        v_pr = cv_at(unpack_11, 1)
        v_i = cce_talloc(v_self)
        cce_expr_value(v_self, v_pl, 0)
        let pieces_12: i64 = cv_list()
        cv_push(pieces_12, cv_text("mov qword ptr [rbp"))
        cv_push(pieces_12, cv_format(cce_toff(v_self, v_i), "+d"))
        cv_push(pieces_12, cv_text("], rax"))
        cce_e(v_self, cv_join(cv_text(""), pieces_12))
        cce_expr_value(v_self, v_pr, cc_int(CV_TRUE, 515))
        cce_e(v_self, cv_text("mov rcx, rax"))
        v_sz = cc_type_size(cv_getkey(cv_getkey(v_pl, "type"), "elem"))
        if (not ((cv_equal(v_op, cv_text("+")) or cv_equal(v_op, cv_text("-"))))):
            cc_error(cv_text("указанную пару операций с указателем не поддерживаем"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
            return 0
        if (cv_less(11, v_sz)):
            cce_e(v_self, cv_cat(cv_text("imul rcx, rcx, "), cv_format(v_sz, "")))
        let pieces_13: i64 = cv_list()
        cv_push(pieces_13, cv_text("mov rax, qword ptr [rbp"))
        cv_push(pieces_13, cv_format(cce_toff(v_self, v_i), "+d"))
        cv_push(pieces_13, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_13))
        if (cv_equal(v_op, cv_text("-"))):
            cce_e(v_self, cv_text("sub rax, rcx"))
        else:
            cce_e(v_self, cv_text("add rax, rcx"))
        cce_trelease(v_self, v_i)
        return cv_getkey(v_pl, "type")
    let choice_14: i64 = cv_get(v_e, cv_text("common"), 0)
    if not cv_truth(choice_14):
        choice_14 = cv_get(v_e, cv_text("cmp_common"), 0)
    if not cv_truth(choice_14):
        choice_14 = cv_getkey(cv_getkey(v_e, "l"), "type")
    v_tc = choice_14
    v_i = cce_talloc(v_self)
    cce_expr_value(v_self, cv_getkey(v_e, "l"), 0)
    if cv_truth(cc_is_int(v_tc)):
        cce_narrow(v_self, v_tc)
    cce_store_scalar(v_self, cce_toff(v_self, v_i), v_tc, cv_text("int"))
    cce_expr_value(v_self, cv_getkey(v_e, "r"), 0)
    if (cv_truth(cc_is_int(v_tc)) and (not ((cv_equal(v_op, cv_text("<<")) or cv_equal(v_op, cv_text(">>")))))):
        cce_narrow(v_self, v_tc)
    cce_e(v_self, cv_text("mov rcx, rax"))
    cce_load_from_slot(v_self, cce_toff(v_self, v_i), v_tc)
    cce_trelease(v_self, v_i)
    return cce_int_op(v_self, v_e, v_tc)

unsafe fn cce_emit_panic(v_self: i64, v_message: i64) -> i64:
    let v_label: i64 = 0
    v_label = cce_slconst(v_self, v_message)
    let pieces_1: i64 = cv_list()
    cv_push(pieces_1, cv_text("lea rdi, [rip+"))
    cv_push(pieces_1, cv_format(v_label, ""))
    cv_push(pieces_1, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_1))
    cce_e(v_self, cv_text("call VOLT_rt_panic"))
    return 0

unsafe fn cce_trap_on(v_self: i64, v_condition: i64, v_message: i64) -> i64:
    let v_inverse: i64 = 0
    let v_ok: i64 = 0
    let dict_1: i64 = cv_dict()
    cv_set(dict_1, cv_text("o"), cv_text("no"))
    cv_set(dict_1, cv_text("c"), cv_text("nc"))
    cv_set(dict_1, cv_text("e"), cv_text("ne"))
    cv_set(dict_1, cv_text("ne"), cv_text("e"))
    cv_set(dict_1, cv_text("z"), cv_text("nz"))
    cv_set(dict_1, cv_text("s"), cv_text("ns"))
    cv_set(dict_1, cv_text("nz"), cv_text("z"))
    cv_set(dict_1, cv_text("a"), cv_text("be"))
    cv_set(dict_1, cv_text("ae"), cv_text("b"))
    cv_set(dict_1, cv_text("b"), cv_text("ae"))
    cv_set(dict_1, cv_text("p"), cv_text("np"))
    v_inverse = dict_1
    v_ok = cce_lbl(v_self)
    let pieces_2: i64 = cv_list()
    cv_push(pieces_2, cv_text("j"))
    cv_push(pieces_2, cv_format(cv_subscript(v_inverse, v_condition), ""))
    cv_push(pieces_2, cv_text(" "))
    cv_push(pieces_2, cv_format(v_ok, ""))
    cce_e(v_self, cv_join(cv_text(""), pieces_2))
    cce_emit_panic(v_self, v_message)
    cce_label(v_self, v_ok, 0)
    return 0

unsafe fn cce_check_int_range(v_self: i64, v_t: i64) -> i64:
    let v_shift: i64 = 0
    if (not (cv_truth(cc_is_int(v_t))) or (cv_equal(cv_getkey(v_t, "bits"), 515))):
        return 0
    if cv_truth(cv_getkey(v_t, "signed")):
        v_shift = cv_sub(515, cv_getkey(v_t, "bits"))
        cce_e(v_self, cv_text("mov rdx, rax"))
        cce_e(v_self, cv_cat(cv_text("shl rdx, "), cv_format(v_shift, "")))
        cce_e(v_self, cv_cat(cv_text("sar rdx, "), cv_format(v_shift, "")))
        cce_e(v_self, cv_text("cmp rdx, rax"))
        cce_trap_on(v_self, cv_text("ne"), cv_text("volt: integer overflow\n"))
    else:
        cce_e(v_self, cv_text("mov rdx, rax"))
        cce_e(v_self, cv_cat(cv_text("shr rdx, "), cv_format(cv_getkey(v_t, "bits"), "")))
        cce_e(v_self, cv_text("test rdx, rdx"))
        cce_trap_on(v_self, cv_text("nz"), cv_text("volt: integer overflow\n"))
    return 0

unsafe fn cce_check_int_conversion(v_self: i64, v_source: i64, v_target: i64) -> i64:
    if (not (cv_truth(cc_is_int(v_source))) or not (cv_truth(cc_is_int(v_target))) or (cv_equal(v_source, v_target))):
        return 0
    if (not (cv_equal(cv_getkey(v_source, "signed"), cv_getkey(v_target, "signed")))):
        cce_e(v_self, cv_text("test rax, rax"))
        cce_trap_on(v_self, cv_text("s"), cv_text("volt: integer overflow\n"))
    if (cv_less(cv_getkey(v_target, "bits"), 515)):
        cce_check_int_range(v_self, v_target)
    else:
        if (cv_truth(cv_getkey(v_target, "signed")) and not (cv_truth(cv_getkey(v_source, "signed")))):
            cce_e(v_self, cv_text("test rax, rax"))
            cce_trap_on(v_self, cv_text("s"), cv_text("volt: integer overflow\n"))
    cce_narrow(v_self, v_target)
    return 0

unsafe fn cce_float_to_int(v_self: i64, v_source: i64, v_target: i64) -> i64:
    let v_lo: i64 = 0
    let v_hi: i64 = 0
    let v_lower: i64 = 0
    let v_upper: i64 = 0
    let v_high: i64 = 0
    let v_done: i64 = 0
    let v_two63: i64 = 0
    if (cv_equal(cv_getkey(v_source, "bits"), 259)):
        cce_e(v_self, cv_text("cvtss2sd xmm0, xmm0"))
    cce_e(v_self, cv_text("ucomisd xmm0, xmm0"))
    cce_trap_on(v_self, cv_text("p"), cv_text("volt: float-to-int out of range\n"))
    let unpack_1: i64 = cc_int_bounds(v_target)
    v_lo = cv_at(unpack_1, 0)
    v_hi = cv_at(unpack_1, 1)
    v_lower = cce_fconst(v_self, cv_f(v_lo))
    v_upper = cce_fconst(v_self, cv_f(cv_add(v_hi, 11)))
    let pieces_2: i64 = cv_list()
    cv_push(pieces_2, cv_text("movsd xmm1, qword ptr [rip+"))
    cv_push(pieces_2, cv_format(v_lower, ""))
    cv_push(pieces_2, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_2))
    cce_e(v_self, cv_text("ucomisd xmm0, xmm1"))
    cce_trap_on(v_self, cv_text("b"), cv_text("volt: float-to-int out of range\n"))
    let pieces_3: i64 = cv_list()
    cv_push(pieces_3, cv_text("movsd xmm1, qword ptr [rip+"))
    cv_push(pieces_3, cv_format(v_upper, ""))
    cv_push(pieces_3, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_3))
    cce_e(v_self, cv_text("ucomisd xmm0, xmm1"))
    cce_trap_on(v_self, cv_text("ae"), cv_text("volt: float-to-int out of range\n"))
    if (not (cv_truth(cv_getkey(v_target, "signed"))) and (cv_equal(cv_getkey(v_target, "bits"), 515))):
        v_high = cce_lbl(v_self)
        v_done = cce_lbl(v_self)
        v_two63 = cce_fconst(v_self, cv_f(cv_shl(11, 507)))
        let pieces_4: i64 = cv_list()
        cv_push(pieces_4, cv_text("movsd xmm1, qword ptr [rip+"))
        cv_push(pieces_4, cv_format(v_two63, ""))
        cv_push(pieces_4, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_4))
        cce_e(v_self, cv_text("ucomisd xmm0, xmm1"))
        cce_e(v_self, cv_cat(cv_text("jae "), cv_format(v_high, "")))
        cce_e(v_self, cv_text("cvttsd2si rax, xmm0"))
        cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_done, "")))
        cce_label(v_self, v_high, 0)
        cce_e(v_self, cv_text("subsd xmm0, xmm1"))
        cce_e(v_self, cv_text("cvttsd2si rax, xmm0"))
        cce_e(v_self, cv_text("bts rax, 63"))
        cce_label(v_self, v_done, 0)
    else:
        cce_e(v_self, cv_text("cvttsd2si rax, xmm0"))
        cce_narrow(v_self, v_target)
    return 0

unsafe fn cce_check_neg_overflow(v_self: i64, v_t: i64) -> i64:
    if not (cv_truth(cc_is_int(v_t))):
        return 0
    if (cv_truth(cv_getkey(v_t, "signed")) and (cv_equal(cv_getkey(v_t, "bits"), 515))):
        cce_trap_on(v_self, cv_text("o"), cv_text("volt: integer overflow\n"))
    else:
        if (not (cv_truth(cv_getkey(v_t, "signed"))) and (cv_equal(cv_getkey(v_t, "bits"), 515))):
            cce_trap_on(v_self, cv_text("c"), cv_text("volt: integer overflow\n"))
        else:
            cce_check_int_range(v_self, v_t)
    return 0

unsafe fn cce_check_int_result(v_self: i64, v_t: i64, v_op: i64) -> i64:
    if not (cv_truth(cc_is_int(v_t))):
        return 0
    if (cv_less(cv_getkey(v_t, "bits"), 515)):
        cce_check_int_range(v_self, v_t)
    else:
        if cv_truth(cv_getkey(v_t, "signed")):
            cce_trap_on(v_self, cv_text("o"), cv_text("volt: integer overflow\n"))
        else:
            if ((cv_equal(v_op, cv_text("+")) or cv_equal(v_op, cv_text("-")))):
                cce_trap_on(v_self, cv_text("c"), cv_text("volt: integer overflow\n"))
            else:
                if (cv_equal(v_op, cv_text("*"))):
                    cce_e(v_self, cv_text("test rdx, rdx"))
                    cce_trap_on(v_self, cv_text("nz"), cv_text("volt: integer overflow\n"))
    return 0

unsafe fn cce_check_shift_count(v_self: i64, v_e: i64, v_t: i64) -> i64:
    let v_shift_type: i64 = 0
    v_shift_type = cv_get(v_e, cv_text("shift_type"), 0)
    if ((v_shift_type == 0) and (not (cv_get(v_e, cv_text("r"), 0) == 0))):
        v_shift_type = cv_getkey(cv_getkey(v_e, "r"), "type")
    if (cv_truth(cc_is_int(v_shift_type)) and cv_truth(cv_getkey(v_shift_type, "signed"))):
        cce_e(v_self, cv_text("test rcx, rcx"))
        cce_trap_on(v_self, cv_text("s"), cv_text("volt: invalid shift count\n"))
    cce_e(v_self, cv_cat(cv_text("cmp rcx, "), cv_format(cv_getkey(v_t, "bits"), "")))
    cce_trap_on(v_self, cv_text("ae"), cv_text("volt: invalid shift count\n"))
    return 0

unsafe fn cce_int_op(v_self: i64, v_e: i64, v_t: i64) -> i64:
    let v_op: i64 = 0
    let v_signed: i64 = 0
    let v_not_min: i64 = 0
    let v_CC: i64 = 0
    v_op = cv_getkey(v_e, "op")
    let choice_1: i64 = cc_is_int(v_t)
    if cv_truth(choice_1):
        choice_1 = cv_getkey(v_t, "signed")
    v_signed = choice_1
    if (cv_equal(v_op, cv_text("+"))):
        cce_e(v_self, cv_text("add rax, rcx"))
    else:
        if (cv_equal(v_op, cv_text("-"))):
            cce_e(v_self, cv_text("sub rax, rcx"))
        else:
            if (cv_equal(v_op, cv_text("*"))):
                if (cv_truth(cc_is_int(v_t)) and not (cv_truth(v_signed)) and (cv_equal(cv_getkey(v_t, "bits"), 515))):
                    cce_e(v_self, cv_text("mul rcx"))
                else:
                    cce_e(v_self, cv_text("imul rax, rcx"))
            else:
                if (cv_equal(v_op, cv_text("/"))):
                    cce_e(v_self, cv_text("test rcx, rcx"))
                    cce_trap_on(v_self, cv_text("z"), cv_text("volt: division by zero\n"))
                    if cv_truth(v_signed):
                        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
                            v_not_min = cce_lbl(v_self)
                            cce_e(v_self, cv_text("mov rdx, -9223372036854775808"))
                            cce_e(v_self, cv_text("cmp rax, rdx"))
                            cce_e(v_self, cv_cat(cv_text("jne "), cv_format(v_not_min, "")))
                            cce_e(v_self, cv_text("cmp rcx, -1"))
                            cce_trap_on(v_self, cv_text("e"), cv_text("volt: integer overflow\n"))
                            cce_label(v_self, v_not_min, 0)
                        cce_e(v_self, cv_text("cqo"))
                        cce_e(v_self, cv_text("idiv rcx"))
                    else:
                        cce_e(v_self, cv_text("xor edx, edx"))
                        cce_e(v_self, cv_text("div rcx"))
                else:
                    if (cv_equal(v_op, cv_text("%"))):
                        cce_e(v_self, cv_text("test rcx, rcx"))
                        cce_trap_on(v_self, cv_text("z"), cv_text("volt: division by zero\n"))
                        if cv_truth(v_signed):
                            if (cv_equal(cv_getkey(v_t, "bits"), 515)):
                                v_not_min = cce_lbl(v_self)
                                cce_e(v_self, cv_text("mov rdx, -9223372036854775808"))
                                cce_e(v_self, cv_text("cmp rax, rdx"))
                                cce_e(v_self, cv_cat(cv_text("jne "), cv_format(v_not_min, "")))
                                cce_e(v_self, cv_text("cmp rcx, -1"))
                                cce_trap_on(v_self, cv_text("e"), cv_text("volt: integer overflow\n"))
                                cce_label(v_self, v_not_min, 0)
                            cce_e(v_self, cv_text("cqo"))
                            cce_e(v_self, cv_text("idiv rcx"))
                            cce_e(v_self, cv_text("mov rax, rdx"))
                        else:
                            cce_e(v_self, cv_text("xor edx, edx"))
                            cce_e(v_self, cv_text("div rcx"))
                            cce_e(v_self, cv_text("mov rax, rdx"))
                    else:
                        if (cv_equal(v_op, cv_text("<<"))):
                            cce_check_shift_count(v_self, v_e, v_t)
                            cce_e(v_self, cv_text("shl rax, cl"))
                        else:
                            if (cv_equal(v_op, cv_text(">>"))):
                                cce_check_shift_count(v_self, v_e, v_t)
                                let choice_2: i64 = 0
                                if cv_truth(v_signed):
                                    choice_2 = cv_text("sar")
                                else:
                                    choice_2 = cv_text("shr")
                                cce_e(v_self, cv_add(choice_2, cv_text(" rax, cl")))
                            else:
                                if (cv_equal(v_op, cv_text("&"))):
                                    cce_e(v_self, cv_text("and rax, rcx"))
                                else:
                                    if (cv_equal(v_op, cv_text("|"))):
                                        cce_e(v_self, cv_text("or rax, rcx"))
                                    else:
                                        if (cv_equal(v_op, cv_text("^"))):
                                            cce_e(v_self, cv_text("xor rax, rcx"))
                                        else:
                                            if ((cv_equal(v_op, cv_text("==")) or cv_equal(v_op, cv_text("!=")) or cv_equal(v_op, cv_text("<")) or cv_equal(v_op, cv_text("<=")) or cv_equal(v_op, cv_text(">")) or cv_equal(v_op, cv_text(">=")))):
                                                let dict_3: i64 = cv_dict()
                                                cv_set(dict_3, cv_text("=="), cv_text("e"))
                                                cv_set(dict_3, cv_text("!="), cv_text("ne"))
                                                v_CC = dict_3
                                                if cv_truth(v_signed):
                                                    let dict_4: i64 = cv_dict()
                                                    cv_set(dict_4, cv_text("<"), cv_text("l"))
                                                    cv_set(dict_4, cv_text("<="), cv_text("le"))
                                                    cv_set(dict_4, cv_text(">"), cv_text("g"))
                                                    cv_set(dict_4, cv_text(">="), cv_text("ge"))
                                                    cv_update(v_CC, dict_4)
                                                else:
                                                    let dict_5: i64 = cv_dict()
                                                    cv_set(dict_5, cv_text("<"), cv_text("b"))
                                                    cv_set(dict_5, cv_text("<="), cv_text("be"))
                                                    cv_set(dict_5, cv_text(">"), cv_text("a"))
                                                    cv_set(dict_5, cv_text(">="), cv_text("ae"))
                                                    cv_update(v_CC, dict_5)
                                                cce_e(v_self, cv_text("cmp rax, rcx"))
                                                let pieces_6: i64 = cv_list()
                                                cv_push(pieces_6, cv_text("set"))
                                                cv_push(pieces_6, cv_format(cv_subscript(v_CC, v_op), ""))
                                                cv_push(pieces_6, cv_text(" al"))
                                                cce_e(v_self, cv_join(cv_text(""), pieces_6))
                                                cce_e(v_self, cv_text("movzx eax, al"))
                                                return cc_TBool()
                                            else:
                                                cc_error(cv_add(cv_text("неподдерж. операция "), v_op), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
                                                return 0
    if ((cv_equal(v_op, cv_text("+")) or cv_equal(v_op, cv_text("-")) or cv_equal(v_op, cv_text("*")))):
        cce_check_int_result(v_self, v_t, v_op)
    else:
        if ((cv_equal(v_op, cv_text("/"))) and cv_truth(cc_is_int(v_t)) and (cv_less(cv_getkey(v_t, "bits"), 515))):
            cce_check_int_range(v_self, v_t)
    if cv_truth(cc_is_int(v_t)):
        cce_narrow(v_self, v_t)
    return v_t

unsafe fn cce_float_op(v_self: i64, v_e: i64, v_t: i64) -> i64:
    let v_op: i64 = 0
    let v_S: i64 = 0
    let v_base: i64 = 0
    v_op = cv_getkey(v_e, "op")
    let choice_1: i64 = 0
    if (cv_equal(cv_getkey(v_t, "bits"), 515)):
        choice_1 = cv_text("sd")
    else:
        choice_1 = cv_text("ss")
    v_S = choice_1
    if (cv_equal(v_op, cv_text("+"))):
        let pieces_2: i64 = cv_list()
        cv_push(pieces_2, cv_text("add"))
        cv_push(pieces_2, cv_format(v_S, ""))
        cv_push(pieces_2, cv_text(" xmm0, xmm1"))
        cce_e(v_self, cv_join(cv_text(""), pieces_2))
    else:
        if (cv_equal(v_op, cv_text("*"))):
            let pieces_3: i64 = cv_list()
            cv_push(pieces_3, cv_text("mul"))
            cv_push(pieces_3, cv_format(v_S, ""))
            cv_push(pieces_3, cv_text(" xmm0, xmm1"))
            cce_e(v_self, cv_join(cv_text(""), pieces_3))
        else:
            if (cv_equal(v_op, cv_text("-"))):
                let pieces_4: i64 = cv_list()
                cv_push(pieces_4, cv_text("sub"))
                cv_push(pieces_4, cv_format(v_S, ""))
                cv_push(pieces_4, cv_text(" xmm1, xmm0"))
                cce_e(v_self, cv_join(cv_text(""), pieces_4))
                let choice_5: i64 = 0
                if (cv_equal(cv_getkey(v_t, "bits"), 515)):
                    choice_5 = cv_text("movsd xmm0, xmm1")
                else:
                    choice_5 = cv_text("movss xmm0, xmm1")
                cce_e(v_self, choice_5)
            else:
                if (cv_equal(v_op, cv_text("/"))):
                    let pieces_6: i64 = cv_list()
                    cv_push(pieces_6, cv_text("div"))
                    cv_push(pieces_6, cv_format(v_S, ""))
                    cv_push(pieces_6, cv_text(" xmm1, xmm0"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_6))
                    let choice_7: i64 = 0
                    if (cv_equal(cv_getkey(v_t, "bits"), 515)):
                        choice_7 = cv_text("movsd xmm0, xmm1")
                    else:
                        choice_7 = cv_text("movss xmm0, xmm1")
                    cce_e(v_self, choice_7)
                else:
                    if ((cv_equal(v_op, cv_text("==")) or cv_equal(v_op, cv_text("!=")) or cv_equal(v_op, cv_text("<")) or cv_equal(v_op, cv_text("<=")) or cv_equal(v_op, cv_text(">")) or cv_equal(v_op, cv_text(">=")))):
                        let pieces_8: i64 = cv_list()
                        cv_push(pieces_8, cv_text("ucomis_"))
                        cv_push(pieces_8, cv_format(v_S, ""))
                        cv_push(pieces_8, cv_text(" xmm1, xmm0"))
                        cce_e(v_self, cv_replace(cv_join(cv_text(""), pieces_8), cv_text("is_"), cv_text("i")))
                        let dict_9: i64 = cv_dict()
                        cv_set(dict_9, cv_text("<"), cv_text("b"))
                        cv_set(dict_9, cv_text("<="), cv_text("be"))
                        cv_set(dict_9, cv_text(">"), cv_text("a"))
                        cv_set(dict_9, cv_text(">="), cv_text("ae"))
                        v_base = cv_get(dict_9, v_op, 0)
                        if (cv_equal(v_op, cv_text("=="))):
                            cce_e(v_self, cv_text("sete al"))
                            cce_e(v_self, cv_text("setnp cl"))
                            cce_e(v_self, cv_text("and al, cl"))
                        else:
                            if (cv_equal(v_op, cv_text("!="))):
                                cce_e(v_self, cv_text("sete al"))
                                cce_e(v_self, cv_text("setnp cl"))
                                cce_e(v_self, cv_text("and al, cl"))
                                cce_e(v_self, cv_text("xor al, 1"))
                            else:
                                let pieces_10: i64 = cv_list()
                                cv_push(pieces_10, cv_text("set"))
                                cv_push(pieces_10, cv_format(v_base, ""))
                                cv_push(pieces_10, cv_text(" al"))
                                cce_e(v_self, cv_join(cv_text(""), pieces_10))
                                cce_e(v_self, cv_text("setnp cl"))
                                cce_e(v_self, cv_text("and al, cl"))
                        cce_e(v_self, cv_text("movzx eax, al"))
                        return cc_TBool()
                    else:
                        cc_error(cv_add(cv_text("float-операция "), v_op), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_e, "line"))
                        return 0
    return cc_TFloat(cv_getkey(v_t, "bits"))

unsafe fn cce_fconv(v_self: i64, v_a: i64, v_b: i64) -> i64:
    if ((cv_equal(cv_getkey(v_a, "bits"), cv_getkey(v_b, "bits"))) or not (cv_truth(cc_is_float(v_a))) or not (cv_truth(cc_is_float(v_b)))):
        return 0
    if (cv_equal(cv_getkey(v_a, "bits"), 515)):
        cce_e(v_self, cv_text("cvtsd2ss xmm0, xmm0"))
    else:
        cce_e(v_self, cv_text("cvtss2sd xmm0, xmm0"))
    return 0

unsafe fn cce_int_to_float(v_self: i64, v_src: i64, v_dst: i64) -> i64:
    let v_suffix: i64 = 0
    let v_convert: i64 = 0
    let v_signed: i64 = 0
    let v_done: i64 = 0
    let choice_1: i64 = 0
    if (cv_equal(cv_getkey(v_dst, "bits"), 515)):
        choice_1 = cv_text("sd")
    else:
        choice_1 = cv_text("ss")
    v_suffix = choice_1
    let pieces_2: i64 = cv_list()
    cv_push(pieces_2, cv_text("cvtsi2"))
    cv_push(pieces_2, cv_format(v_suffix, ""))
    cv_push(pieces_2, cv_text(" xmm0, rax"))
    v_convert = cv_join(cv_text(""), pieces_2)
    if (cv_truth(cc_is_int(v_src)) and not (cv_truth(cv_getkey(v_src, "signed"))) and (cv_equal(cv_getkey(v_src, "bits"), 515))):
        v_signed = cce_lbl(v_self)
        v_done = cce_lbl(v_self)
        cce_e(v_self, cv_text("test rax, rax"))
        cce_e(v_self, cv_cat(cv_text("jns "), cv_format(v_signed, "")))
        cce_e(v_self, cv_text("mov rcx, rax"))
        cce_e(v_self, cv_text("and ecx, 1"))
        cce_e(v_self, cv_text("shr rax, 1"))
        cce_e(v_self, cv_text("or rax, rcx"))
        cce_e(v_self, v_convert)
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("add"))
        cv_push(pieces_3, cv_format(v_suffix, ""))
        cv_push(pieces_3, cv_text(" xmm0, xmm0"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_done, "")))
        cce_label(v_self, v_signed, 0)
        cce_e(v_self, v_convert)
        cce_label(v_self, v_done, 0)
        return 0
    cce_e(v_self, v_convert)
    return 0

unsafe fn cce_expr_truthy(v_self: i64, v_e: i64) -> i64:
    let v_t: i64 = 0
    v_t = cce_expr_value(v_self, v_e, 0)
    if cv_truth(cc_is_bool(v_t)):
        return 0
    if cv_truth(cc_is_float(v_t)):
        cce_e(v_self, cv_text("xorpd xmm1, xmm1"))
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            cce_e(v_self, cv_text("ucomisd xmm0, xmm1"))
        else:
            cce_e(v_self, cv_text("ucomiss xmm0, xmm1"))
        cce_e(v_self, cv_text("setne al"))
        cce_e(v_self, cv_text("setnp cl"))
        cce_e(v_self, cv_text("and al, cl"))
        cce_e(v_self, cv_text("movzx eax, al"))
        return 0
    cce_e(v_self, cv_text("test rax, rax"))
    cce_e(v_self, cv_text("setne al"))
    cce_e(v_self, cv_text("movzx eax, al"))
    return 0

unsafe fn cce_float_sign_mask(emitter: i64, bits: i64, negate: bool) -> i64:
    let label: string = "VOLT_absmask_f64"
    let data: string = ": .quad 0x7fffffffffffffff, 0"
    if cv_equal(bits, cv_i(32)):
        if negate:
            label = "VOLT_negmask_f32"
            data = ": .quad 0x80000000, 0"
        else:
            label = "VOLT_absmask_f32"
            data = ": .quad 0x7fffffff, 0"
    elif negate:
        label = "VOLT_negmask_f64"
        data = ": .quad 0x8000000000000000, 0"
    let symbol: i64 = cv_text(label)
    if not cv_has(emitter, symbol):
        let rodata: i64 = cv_getkey(emitter, "rodata")
        cv_push(rodata, cv_text(".align 16"))
        cv_push(rodata, cv_cat(symbol, cv_text(data)))
        cv_set(emitter, symbol, CV_TRUE)
    return symbol

unsafe fn cce_narrow(v_self: i64, v_tt: i64) -> i64:
    if (not (cv_truth(cc_is_int(v_tt))) or (cv_equal(cv_getkey(v_tt, "bits"), 515))):
        return 0
    if cv_truth(cv_getkey(v_tt, "signed")):
        if (cv_equal(cv_getkey(v_tt, "bits"), 259)):
            cce_e(v_self, cv_text("movsxd rax, eax"))
        else:
            if (cv_equal(cv_getkey(v_tt, "bits"), 131)):
                cce_e(v_self, cv_text("movsx rax, ax"))
            else:
                cce_e(v_self, cv_text("movsx rax, al"))
    else:
        if (cv_equal(cv_getkey(v_tt, "bits"), 259)):
            cce_e(v_self, cv_text("mov eax, eax"))
        else:
            if (cv_equal(cv_getkey(v_tt, "bits"), 131)):
                cce_e(v_self, cv_text("movzx rax, ax"))
            else:
                cce_e(v_self, cv_text("movzx rax, al"))
    return 0

unsafe fn cce_expr_cast(v_self: i64, v_e: i64) -> i64:
    let v_st: i64 = 0
    let v_tt: i64 = 0
    v_st = cv_getkey(cv_getkey(v_e, "x"), "type")
    v_tt = cv_getkey(v_e, "type")
    cce_expr_value(v_self, cv_getkey(v_e, "x"), 0)
    if (cv_truth(cc_is_ptr(v_st)) or cv_truth(cc_is_ptr(v_tt)) or cv_truth(cc_is_string(v_st)) or cv_truth(cc_is_string(v_tt))):
        return v_tt
    if cv_truth(cc_is_float(v_st)):
        if cv_truth(cc_is_int(v_tt)):
            cce_float_to_int(v_self, v_st, v_tt)
            return v_tt
        if ((cv_equal(cv_getkey(v_st, "bits"), 515)) and (cv_equal(cv_getkey(v_tt, "bits"), 259))):
            cce_e(v_self, cv_text("cvtsd2ss xmm0, xmm0"))
        else:
            if ((cv_equal(cv_getkey(v_st, "bits"), 259)) and (cv_equal(cv_getkey(v_tt, "bits"), 515))):
                cce_e(v_self, cv_text("cvtss2sd xmm0, xmm0"))
        return v_tt
    if cv_truth(cc_is_float(v_tt)):
        cce_int_to_float(v_self, v_st, v_tt)
        return v_tt
    if (cv_truth(cc_is_int(v_st)) and cv_truth(cc_is_int(v_tt))):
        cce_check_int_conversion(v_self, v_st, v_tt)
        return v_tt
    return v_tt

const CC_ABI_GP: i64 = 0
const CC_ABI_SSE: i64 = 1
const CC_ABI_STACK: i64 = 2
const CC_ABI_RECORD: i64 = 3

struct CCEAbiCursor:
    gp: i64
    sse: i64
    stack_bytes: i64

struct CCEAbiLocation:
    kind: i64
    index: i64 # Register index or byte offset in the outgoing area.

struct CCEAbiArg:
    typ: i64
    temp: i64
    place: CCEAbiLocation

unsafe fn cce_abi_has_sret(result: i64) -> bool:
    return cc_is_tagged_value(result) or cv_classes(result, "TStruct")

unsafe fn cce_abi_start(result: i64) -> CCEAbiCursor:
    let gp: i64 = 0
    if cce_abi_has_sret(result): gp = 1
    return CCEAbiCursor(gp, 0, 0)

unsafe fn cce_abi_words(typ: i64) -> i64:
    if cv_classes(typ, "TSlice"): return 2
    return 1

unsafe fn cce_abi_next(cursor: ptr<CCEAbiCursor>, typ: i64) -> CCEAbiLocation:
    let words: i64 = cce_abi_words(typ)
    if cv_truth(cc_is_float(typ)):
        if cursor.sse < 8:
            let reg: i64 = cursor.sse
            cursor.sse += 1
            return CCEAbiLocation(CC_ABI_SSE, reg)
    elif cursor.gp + words <= cv_len(cc_k_int_arg_regs):
        let reg: i64 = cursor.gp
        cursor.gp += words
        return CCEAbiLocation(CC_ABI_GP, reg)
    # A slice either takes both GP registers or spills whole without consuming a GP register.
    let offset: i64 = cursor.stack_bytes
    cursor.stack_bytes += words * 8
    return CCEAbiLocation(CC_ABI_STACK, offset)

unsafe fn cce_c_record_next(cursor: ptr<CCEAbiCursor>, typ: i64) -> CCEAbiLocation:
    let size: i64 = cv_index(cc_type_size(typ))
    let words: i64 = (size + 7) / 8
    let mask: i64 = cv_index(cv_getkey(typ, "c_abi"))
    let sse: i64 = (mask & 1) + ((mask >> 1) & 1)
    let gp: i64 = words - sse
    if cursor.gp + gp <= 6 and cursor.sse + sse <= 8:
        let index: i64 = cursor.gp + cursor.sse * 8
        cursor.gp += gp
        cursor.sse += sse
        return CCEAbiLocation(CC_ABI_RECORD, index)
    # SysV rolls back the allocation of the entire record if either class is exhausted.
    let offset: i64 = cursor.stack_bytes
    cursor.stack_bytes += words * 8
    return CCEAbiLocation(CC_ABI_STACK, offset)

unsafe fn cce_abi_mem(base: string, offset: i64, width: i64) -> i64:
    let size: i64 = cv_subscript(cc_k_wmap, cv_i(width))
    return cv_cat(size, cv_mod(cv_text(" ptr [%s%+d]"), cv_pair(cv_text(base), cv_i(offset))))

unsafe fn cce_abi_mov(emitter: i64, mnemonic: string, dest: i64, src: i64):
    cce_e(emitter, cv_cat(cv_text(mnemonic), cv_mod(cv_text(" %s, %s"), cv_pair(dest, src))))

unsafe fn cce_abi_xmm(index: i64) -> i64:
    return cv_mod(cv_text("xmm%d"), cv_i(index))

unsafe fn cce_abi_scratch(width: i64) -> i64:
    if width == 1: return cv_text("r11b")
    if width == 2: return cv_text("r11w")
    if width == 4: return cv_text("r11d")
    return cv_text("r11")

unsafe fn cce_abi_float_mov(width: i64) -> string:
    if width == 4: return "movss"
    return "movsd"

unsafe fn cce_abi_out(emitter: i64, typ: i64, place: CCEAbiLocation, offset: i64):
    let width: i64 = 8
    if cv_truth(cc_is_float(typ)): width = cv_index(cc_type_size(typ))
    for word in 0..cce_abi_words(typ):
        let src: i64 = cce_abi_mem("rbp", offset + word * 8, width)
        if place.kind == CC_ABI_GP:
            cce_abi_mov(emitter, "mov", cv_at(cc_k_int_arg_regs, place.index + word), src)
        elif place.kind == CC_ABI_SSE:
            cce_abi_mov(emitter, cce_abi_float_mov(width), cce_abi_xmm(place.index), src)
        else:
            let scratch: i64 = cce_abi_scratch(width)
            cce_abi_mov(emitter, "mov", scratch, src)
            cce_abi_mov(emitter, "mov", cce_abi_mem("rsp", place.index + word * 8, width), scratch)

unsafe fn cce_abi_in(emitter: i64, typ: i64, place: CCEAbiLocation, offset: i64):
    let width: i64 = 8 # Aggregate parameters keep their internal pointer-passing convention.
    if cv_classes(typ, "TInt") or cv_classes(typ, "TFloat") or cv_classes(typ, "TBool"):
        width = cv_index(cc_type_size(typ))
    for word in 0..cce_abi_words(typ):
        let dest: i64 = cce_abi_mem("rbp", offset + word * 8, width)
        if place.kind == CC_ABI_GP:
            let gp: i64 = cv_at(cc_k_int_arg_regs, place.index + word)
            cce_abi_mov(emitter, "mov", dest, cv_subscript(cv_subscript(cc_k_subreg, gp), cv_i(width)))
        elif place.kind == CC_ABI_SSE:
            cce_abi_mov(emitter, cce_abi_float_mov(width), dest, cce_abi_xmm(place.index))
        else:
            # Only copy the value's actual width; a C caller need not fill in the upper bytes.
            let scratch: i64 = cce_abi_scratch(width)
            cce_abi_mov(emitter, "mov", scratch, cce_abi_mem("rbp", 16 + place.index + word * 8, width))
            cce_abi_mov(emitter, "mov", dest, scratch)

unsafe fn cce_c_record_out(emitter: i64, typ: i64, place: CCEAbiLocation, offset: i64):
    let gp: i64 = place.index % 8
    let sse: i64 = place.index / 8
    let mask: i64 = cv_index(cv_getkey(typ, "c_abi"))
    for word in 0..(cv_index(cc_type_size(typ)) + 7) / 8:
        let src: i64 = cce_abi_mem("rbp", offset + word * 8, 8)
        if place.kind == CC_ABI_STACK:
            cce_abi_mov(emitter, "mov", cv_text("r11"), src)
            cce_abi_mov(emitter, "mov", cce_abi_mem("rsp", place.index + word * 8, 8), cv_text("r11"))
        elif (mask & (1 << word)) != 0:
            cce_abi_mov(emitter, "movsd", cce_abi_xmm(sse), src)
            sse += 1
        else:
            cce_abi_mov(emitter, "mov", cv_at(cc_k_int_arg_regs, gp), src)
            gp += 1

unsafe fn cce_c_record_result(emitter: i64, typ: i64, offset: i64):
    let mask: i64 = cv_index(cv_getkey(typ, "c_abi"))
    let gp: i64 = 0
    let sse: i64 = 0
    for word in 0..(cv_index(cc_type_size(typ)) + 7) / 8:
        let dest: i64 = cce_abi_mem("rbp", offset + word * 8, 8)
        if (mask & (1 << word)) != 0:
            cce_abi_mov(emitter, "movsd", dest, cce_abi_xmm(sse))
            sse += 1
        else:
            let reg: i64 = cv_text("rax")
            if gp != 0: reg = cv_text("rdx")
            cce_abi_mov(emitter, "mov", dest, reg)
            gp += 1

unsafe fn cce_abi_c_result(emitter: i64, result: i64) -> i64:
    # The C ABI leaves the unused high bits of narrow scalar results unspecified.
    if cv_truth(cc_is_bool(result)): cce_e(emitter, cv_text("movzx eax, al"))
    else: cce_narrow(emitter, result)
    return result

unsafe fn cce_call_gen(v_self: i64, v_e: i64, v_args: i64, v_sig_params: i64, v_ret_type: i64, v_label: i64) -> i64:
    let v_base: i64 = 0
    let v_ret_idx: i64 = 0
    let v_s: i64 = 0
    v_base = cv_getkey(v_self, "nt")
    let callee: i64 = cv_getkey(v_e, "indirect_callee")
    let target: i64 = v_label
    if callee != 0:
        # Capture the address before arguments, which can call out or change its slot.
        let index: i64 = cce_talloc(v_self)
        cce_expr_value(v_self, callee, 0)
        cce_e(v_self, cv_text("test rax, rax"))
        cce_trap_on(v_self, cv_text("z"), cv_text("volt: null fnptr call\n"))
        target = cce_abi_mem("rbp", cv_index(cce_toff(v_self, index)), 8)
        cce_abi_mov(v_self, "mov", target, cv_text("rax"))
    let choice_1: i64 = 0
    if cv_classes(v_ret_type, "TWrapper") and cv_getkey(v_e, "temp_slot") == 0:
        choice_1 = cce_talloc(v_self)
    else:
        choice_1 = 0
    v_ret_idx = choice_1
    let v_slice_result: i64 = 0
    if cv_classes(v_ret_type, "TSlice"): v_slice_result = cce_talloc(v_self)
    let c_extern: bool = cv_truth(cv_getkey(v_e, "c_extern"))
    let c_result: bool = c_extern and cv_classes(v_ret_type, "TStruct")
    let c_result_temp: i64 = 0
    let placement: CCEAbiCursor = cce_abi_start(v_ret_type)
    if c_result:
        placement.gp = 0
        c_result_temp = cce_talloc(v_self)
    let count: i64 = cv_len(v_args)
    let args: ptr<CCEAbiArg> = cv_alloc(count * sizeof(CCEAbiArg)) as ptr<CCEAbiArg>
    let sugar: i64 = cv_getkey(v_e, "sugar")
    let swap: bool = sugar != 0 and cv_truth(cv_at(sugar, 1))
    # Place arguments in signature order, but evaluate them in source order.
    for i in 0..count:
        let v_pt: i64 = cv_at(v_sig_params, i)
        # Named signatures store (name, type) pairs; fnptr stores just the types.
        if callee == 0: v_pt = cv_at(v_pt, 1)
        let index: i64 = i
        if swap: index = count - 1 - i
        args[index].typ = v_pt
        if c_extern and cv_classes(v_pt, "TStruct"):
            args[index].place = cce_c_record_next(&placement, v_pt)
        else:
            args[index].place = cce_abi_next(&placement, v_pt)
    for i in 0..count:
        let v_a: i64 = cv_at(v_args, i)
        let v_pt: i64 = args[i].typ
        let v_idx: i64 = cce_talloc(v_self)
        args[i].temp = v_idx
        if c_extern and cv_classes(v_pt, "TStruct"):
            if cv_name(cv_getkey(v_a, "kindt"), "ctor"):
                let src: i64 = cce_soff(v_self, cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_a, "temp_slot")))
                cce_emit_ctor(v_self, v_a, src)
                cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), src))
            else:
                cce_eaddr(v_self, v_a)
            let off: i64 = cce_toff(v_self, v_idx)
            # Snapshot now: later arguments may mutate the source, and it can be shorter than eight bytes.
            cce_e(v_self, cv_mod(cv_text("mov qword ptr [rbp%+d], 0"), off))
            cce_e(v_self, cv_mod(cv_text("mov qword ptr [rbp%+d], 0"), cv_add(off, cv_i(8))))
            cce_copy_from_rax(v_self, off, cc_type_size(v_pt))
            continue
        if cv_classes(v_pt, "TSlice"):
            cce_eaddr(v_self, v_a)
            cce_e(v_self, cv_text("mov rdx, qword ptr [rax]"))
            cce_e(v_self, cv_text("mov rax, qword ptr [rax+8]"))
            let off: i64 = cv_index(cce_toff(v_self, v_idx))
            cce_abi_mov(v_self, "mov", cce_abi_mem("rbp", off, 8), cv_text("rdx"))
            cce_abi_mov(v_self, "mov", cce_abi_mem("rbp", off + 8, 8), cv_text("rax"))
        else:
            if cc_is_tagged_value(v_pt):
                cce_expr_value(v_self, v_a, 0)
                let pieces_14: i64 = cv_list()
                cv_push(pieces_14, cv_text("mov qword ptr [rbp"))
                cv_push(pieces_14, cv_format(cce_toff(v_self, v_idx), "+d"))
                cv_push(pieces_14, cv_text("], rax"))
                cce_e(v_self, cv_join(cv_text(""), pieces_14))
            else:
                if cv_truth(cc_is_struct(v_pt)):
                    if (cv_equal(cv_get(v_a, cv_text("kindt"), 0), cv_text("ctor"))):
                        v_s = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_a, "temp_slot"))
                        cce_emit_ctor(v_self, v_a, cce_soff(v_self, v_s))
                        let pieces_15: i64 = cv_list()
                        cv_push(pieces_15, cv_text("lea rax, [rbp"))
                        cv_push(pieces_15, cv_format(cce_soff(v_self, v_s), "+d"))
                        cv_push(pieces_15, cv_text("]"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_15))
                    else:
                        cce_eaddr(v_self, v_a)
                    let pieces_16: i64 = cv_list()
                    cv_push(pieces_16, cv_text("mov qword ptr [rbp"))
                    cv_push(pieces_16, cv_format(cce_toff(v_self, v_idx), "+d"))
                    cv_push(pieces_16, cv_text("], rax"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_16))
                else:
                    cce_expr_value(v_self, v_a, 0)
                    cce_assign_conv(v_self, cv_getkey(v_a, "type"), v_pt)
                    if cv_truth(cc_is_float(v_pt)):
                        cce_store_scalar(v_self, cce_toff(v_self, v_idx), v_pt, cv_text("float"))
                    else:
                        let pieces_17: i64 = cv_list()
                        cv_push(pieces_17, cv_text("mov qword ptr [rbp"))
                        cv_push(pieces_17, cv_format(cce_toff(v_self, v_idx), "+d"))
                        cv_push(pieces_17, cv_text("], rax"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_17))
    let choice_18: i64 = 0
    if (not (v_ret_idx == 0)):
        choice_18 = 11
    else:
        choice_18 = 3
    cv_field(v_self, "nt", cv_max(cv_getkey(v_self, "nt"), cv_add(v_base, choice_18)))
    # Materialize arguments first so nested calls cannot overwrite the outgoing area.
    # Alignment padding follows the last stack argument, never the first.
    let stack_size: i64 = (placement.stack_bytes + 15) & -16
    if stack_size != 0:
        cce_e(v_self, cv_cat(cv_text("sub rsp, "), cv_str(cv_i(stack_size))))
    if not c_result and cce_abi_has_sret(v_ret_type):
        let result_off: i64 = 0
        if v_ret_idx != 0:
            result_off = cce_toff(v_self, v_ret_idx)
        else:
            result_off = cce_soff(v_self, cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_e, "temp_slot")))
        # Match the seed's sret sequence so its compiler build is already a fixed point.
        cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), result_off))
        cce_e(v_self, cv_text("mov rdi, rax"))
    for i in 0..count:
        let arg: CCEAbiArg = args[i]
        cce_owner_flag(v_self, cv_getkey(cv_at(v_args, i), "owner_transfer"), 0)
        let off: i64 = cv_index(cce_toff(v_self, arg.temp))
        if c_extern and cv_classes(arg.typ, "TStruct"): cce_c_record_out(v_self, arg.typ, arg.place, off)
        else: cce_abi_out(v_self, arg.typ, arg.place, off)
    cce_e(v_self, cv_cat(cv_text("call "), cv_format(target, "")))
    cce_owner_flag(v_self, cv_getkey(v_e, "owner_result"), 1)
    if stack_size != 0:
        cce_e(v_self, cv_cat(cv_text("add rsp, "), cv_str(cv_i(stack_size))))
    if c_result:
        let off: i64 = cce_toff(v_self, c_result_temp)
        let dest: i64 = cce_soff(v_self, cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_e, "temp_slot")))
        cce_c_record_result(v_self, v_ret_type, cv_index(off))
        cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), off))
        cce_copy_from_rax(v_self, dest, cc_type_size(v_ret_type))
        cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), dest))
        cce_trelease(v_self, v_base)
        return v_ret_type
    if v_slice_result != 0:
        # Ordinary VOLT functions return slice address and element count in rax:rdx.
        let v_off: i64 = cce_toff(v_self, v_slice_result)
        cce_abi_mov(v_self, "mov", cce_abi_mem("rbp", cv_index(v_off), 8), cv_text("rax"))
        cce_abi_mov(v_self, "mov", cce_abi_mem("rbp", cv_index(v_off) + 8, 8), cv_text("rdx"))
        cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), v_off))
        cce_trelease(v_self, cv_add(v_slice_result, 11))
        return v_ret_type
    if (not (v_ret_idx == 0)):
        cv_field(v_self, "nt", cv_add(v_ret_idx, 11))
        let pieces_33: i64 = cv_list()
        cv_push(pieces_33, cv_text("lea rax, [rbp"))
        cv_push(pieces_33, cv_format(cce_toff(v_self, v_ret_idx), "+d"))
        cv_push(pieces_33, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_33))
    else:
        if cce_abi_has_sret(v_ret_type):
            let pieces_34: i64 = cv_list()
            cv_push(pieces_34, cv_text("lea rax, [rbp"))
            cv_push(pieces_34, cv_format(cce_soff(v_self, cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_e, "temp_slot"))), "+d"))
            cv_push(pieces_34, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_34))
            if cc_is_tagged_value(v_ret_type): cce_trelease(v_self, v_base)
        else:
            cce_trelease(v_self, v_base)
    return v_ret_type

unsafe fn cce_expr_call(v_self: i64, v_e: i64) -> i64:
    let v_name: i64 = 0
    let v_fn: i64 = 0
    let v_lbl: i64 = 0
    v_name = cv_getkey(v_e, "name")
    let callee: i64 = cv_getkey(v_e, "indirect_callee")
    if callee != 0:
        let signature: i64 = cv_getkey(callee, "type")
        let result: i64 = cce_call_gen(v_self, v_e, cv_getkey(v_e, "args"), cv_getkey(signature, "params"), cv_getkey(signature, "result"), 0)
        return cce_abi_c_result(v_self, result)
    if cv_has(v_e, cv_text("callback_target")):
        v_fn = cv_getkey(v_e, "callback_target")
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("lea rax, [rip+"))
        cv_push(pieces_1, cv_format(cc_function_label(cv_getkey(v_fn, "name"), cv_getkey(v_fn, "file")), ""))
        cv_push(pieces_1, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_1))
        return cv_getkey(v_e, "type")
    if (cv_equal(v_name, cv_text("print"))):
        cc_error(cv_text("print не возвращает значение"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_get(v_e, cv_text("line"), 11))
        return 0
    if (cv_equal(cv_get(v_e, cv_text("kindt"), 0), cv_text("ctor"))):
        cc_error(cv_text("конструктор структуры как значение не поддерживается"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_get(v_e, cv_text("line"), 11))
        return 0
    v_fn = cv_get(cv_getkey(cv_getkey(v_self, "sem"), "fns"), v_name, 0)
    if ((v_fn == 0) and cv_has(v_e, cv_text("generic_fn"))):
        v_fn = cv_getkey(v_e, "generic_fn")
    if v_fn != 0:
        let raw: bool = cv_getkey(v_fn, "native") != 0
        let external: bool = cv_getkey(v_fn, "body") == 0 and not raw
        v_lbl = cv_get(v_fn, cv_text("source_name"), v_name)
        if not external:
            v_lbl = cc_function_label(cv_get(v_fn, cv_text("mangled_name"), cv_getkey(v_fn, "name")), cv_getkey(v_fn, "file"))
        let result: i64 = cce_call_gen(v_self, v_e, cv_getkey(v_e, "args"), cv_getkey(v_fn, "sig_params"), cv_getkey(v_fn, "sig_ret"), v_lbl)
        if (external or raw) and not cv_classes(result, "TStruct"): return cce_abi_c_result(v_self, result)
        return result
    if (cv_contains(cc_k_irtis, v_name)):
        return cce_call_irtis(v_self, v_e, cv_subscript(cc_k_irtis, v_name))
    cc_error(cv_cat(cv_text("неизвестная функция "), cv_format(v_name, "r")), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_get(v_e, cv_text("line"), 11))
    return 0

unsafe fn cce_irtis_pt(v_self: i64, v_k: i64) -> i64:
    if (cv_equal(v_k, cv_text("i"))):
        return cc_int(CV_TRUE, 515)
    if (cv_equal(v_k, cv_text("f"))):
        return cc_TFloat(515)
    if (cv_equal(v_k, cv_text("p"))):
        return cv_getkey(cv_getkey(v_self, "sem"), "_ptr_char")
    cc_error(cv_add(cv_text("внутр: kind "), v_k), 0, 0)
    return 0

unsafe fn cce_call_irtis(v_self: i64, v_e: i64, v_spec: i64) -> i64:
    let v_kinds: i64 = 0
    let v_ret: i64 = 0
    let v_lbl: i64 = 0
    let v_name: i64 = 0
    let v_args: i64 = 0
    let v_rtype: i64 = 0
    let v_fps: i64 = 0
    let v_t: i64 = 0
    let v_t0: i64 = 0
    let v_t1: i64 = 0
    let v_t2: i64 = 0
    let v_L: i64 = 0
    let v_tc: i64 = 0
    let v_i: i64 = 0
    let v_pw: i64 = 0
    let v_ins: i64 = 0
    let v_op: i64 = 0
    let v_sgn: i64 = 0
    let v_cc: i64 = 0
    let unpack_1: i64 = v_spec
    v_kinds = cv_at(unpack_1, 0)
    v_ret = cv_at(unpack_1, 1)
    v_lbl = cv_at(unpack_1, 2)
    v_name = cv_getkey(v_e, "name")
    v_args = cv_getkey(v_e, "args")
    if (cv_equal(v_ret, cv_text("i"))):
        v_rtype = cc_int(CV_TRUE, 515)
    else:
        if (cv_equal(v_ret, cv_text("f"))):
            v_rtype = cc_TFloat(515)
        else:
            if (cv_equal(v_ret, cv_text("p"))):
                v_rtype = cv_getkey(cv_getkey(v_self, "sem"), "_ptr_char")
            else:
                if (cv_equal(v_ret, cv_text("n"))):
                    let choice_2: i64 = cv_getkey(v_e, "common_w")
                    if not cv_truth(choice_2):
                        choice_2 = cv_getkey(cv_subscript(v_args, 3), "type")
                    v_rtype = choice_2
                else:
                    v_rtype = 0
    if (not (v_lbl == 0)):
        let collect_3: i64 = cv_vector(CV_LIST)
        let seq_5: i64 = v_kinds
        for index_4 in 0..cv_len(seq_5):
            let k_6: i64 = cv_at(seq_5, index_4)
            cv_push(collect_3, cv_pair(0, cce_irtis_pt(v_self, k_6)))
        v_fps = collect_3
        return cce_call_gen(v_self, v_e, v_args, v_fps, v_rtype, v_lbl)
    if (cv_equal(v_name, cv_text("len"))):
        let arg: i64 = cv_subscript(v_args, 3)
        v_t = cv_getkey(arg, "type")
        if cv_classes(v_t, "TSlice"):
            cce_eaddr(v_self, arg)
            cce_e(v_self, cv_text("mov rax, qword ptr [rax + 8]"))
        else:
            # The length is constant; evaluating an array expression need not be.
            if not cv_classes(arg, "VarRef"):
                let saved: i64 = cv_getkey(v_self, "nt")
                cce_eaddr(v_self, arg)
                cce_trelease(v_self, saved)
            cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(cv_getkey(v_t, "n"), "")))
        return cc_int(CV_TRUE, 515)
    if ((cv_equal(v_name, cv_text("sin")) or cv_equal(v_name, cv_text("cos")) or cv_equal(v_name, cv_text("tan")) or cv_equal(v_name, cv_text("log2")))):
        cce_expr_value(v_self, cv_subscript(v_args, 3), 0)
        cce_fconv(v_self, cv_getkey(cv_subscript(v_args, 3), "type"), cc_TFloat(515))
        v_t0 = cce_talloc(v_self)
        v_t1 = cce_talloc(v_self)
        let pieces_7: i64 = cv_list()
        cv_push(pieces_7, cv_text("movsd qword ptr [rbp"))
        cv_push(pieces_7, cv_format(cce_toff(v_self, v_t0), "+d"))
        cv_push(pieces_7, cv_text("], xmm0"))
        cce_e(v_self, cv_join(cv_text(""), pieces_7))
        if (cv_equal(v_name, cv_text("log2"))):
            cce_e(v_self, cv_text("fld1"))
            let pieces_8: i64 = cv_list()
            cv_push(pieces_8, cv_text("fld qword ptr [rbp"))
            cv_push(pieces_8, cv_format(cce_toff(v_self, v_t0), "+d"))
            cv_push(pieces_8, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_8))
            cce_e(v_self, cv_text("fyl2x"))
        else:
            let pieces_9: i64 = cv_list()
            cv_push(pieces_9, cv_text("fld qword ptr [rbp"))
            cv_push(pieces_9, cv_format(cce_toff(v_self, v_t0), "+d"))
            cv_push(pieces_9, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_9))
            if (cv_equal(v_name, cv_text("sin"))):
                cce_e(v_self, cv_text("fsin"))
            else:
                if (cv_equal(v_name, cv_text("cos"))):
                    cce_e(v_self, cv_text("fcos"))
                else:
                    cce_e(v_self, cv_text("fptan"))
                    cce_e(v_self, cv_text("fstp st(0)"))
        let pieces_10: i64 = cv_list()
        cv_push(pieces_10, cv_text("fstp qword ptr [rbp"))
        cv_push(pieces_10, cv_format(cce_toff(v_self, v_t1), "+d"))
        cv_push(pieces_10, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_10))
        let pieces_11: i64 = cv_list()
        cv_push(pieces_11, cv_text("movsd xmm0, qword ptr [rbp"))
        cv_push(pieces_11, cv_format(cce_toff(v_self, v_t1), "+d"))
        cv_push(pieces_11, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_11))
        return cc_TFloat(515)
    if (cv_equal(v_name, cv_text("atan2"))):
        cce_expr_value(v_self, cv_subscript(v_args, 3), 0)
        cce_fconv(v_self, cv_getkey(cv_subscript(v_args, 3), "type"), cc_TFloat(515))
        v_t0 = cce_talloc(v_self)
        let pieces_12: i64 = cv_list()
        cv_push(pieces_12, cv_text("movsd qword ptr [rbp"))
        cv_push(pieces_12, cv_format(cce_toff(v_self, v_t0), "+d"))
        cv_push(pieces_12, cv_text("], xmm0"))
        cce_e(v_self, cv_join(cv_text(""), pieces_12))
        cce_expr_value(v_self, cv_subscript(v_args, 11), 0)
        cce_fconv(v_self, cv_getkey(cv_subscript(v_args, 11), "type"), cc_TFloat(515))
        v_t1 = cce_talloc(v_self)
        let pieces_13: i64 = cv_list()
        cv_push(pieces_13, cv_text("movsd qword ptr [rbp"))
        cv_push(pieces_13, cv_format(cce_toff(v_self, v_t1), "+d"))
        cv_push(pieces_13, cv_text("], xmm0"))
        cce_e(v_self, cv_join(cv_text(""), pieces_13))
        v_t2 = cce_talloc(v_self)
        let pieces_14: i64 = cv_list()
        cv_push(pieces_14, cv_text("fld qword ptr [rbp"))
        cv_push(pieces_14, cv_format(cce_toff(v_self, v_t1), "+d"))
        cv_push(pieces_14, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_14))
        let pieces_15: i64 = cv_list()
        cv_push(pieces_15, cv_text("fld qword ptr [rbp"))
        cv_push(pieces_15, cv_format(cce_toff(v_self, v_t0), "+d"))
        cv_push(pieces_15, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_15))
        cce_e(v_self, cv_text("fpatan"))
        let pieces_16: i64 = cv_list()
        cv_push(pieces_16, cv_text("fstp qword ptr [rbp"))
        cv_push(pieces_16, cv_format(cce_toff(v_self, v_t2), "+d"))
        cv_push(pieces_16, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_16))
        let pieces_17: i64 = cv_list()
        cv_push(pieces_17, cv_text("movsd xmm0, qword ptr [rbp"))
        cv_push(pieces_17, cv_format(cce_toff(v_self, v_t2), "+d"))
        cv_push(pieces_17, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_17))
        return cc_TFloat(515)
    if (cv_equal(v_name, cv_text("sqrt"))):
        cce_expr_value(v_self, cv_subscript(v_args, 3), 0)
        cce_fconv(v_self, cv_getkey(cv_subscript(v_args, 3), "type"), cc_TFloat(515))
        cce_e(v_self, cv_text("sqrtsd xmm0, xmm0"))
        return cc_TFloat(515)
    if (cv_equal(v_name, cv_text("abs"))):
        v_t0 = cv_getkey(cv_subscript(v_args, 3), "type")
        cce_expr_value(v_self, cv_subscript(v_args, 3), 0)
        if cv_truth(cc_is_float(v_t0)):
            let pieces_18: i64 = cv_list()
            cv_push(pieces_18, cv_text("andpd xmm0, xmmword ptr [rip+"))
            cv_push(pieces_18, cv_format(cce_float_sign_mask(v_self, cv_getkey(v_t0, "bits"), false), ""))
            cv_push(pieces_18, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_18))
            if ((not (v_rtype == 0)) and (not (cv_equal(cv_getkey(v_rtype, "bits"), cv_getkey(v_t0, "bits"))))):
                let choice_19: i64 = 0
                if (cv_equal(cv_getkey(v_rtype, "bits"), 515)):
                    choice_19 = cc_TFloat(515)
                else:
                    choice_19 = cc_TFloat(259)
                cce_fconv(v_self, choice_19, v_rtype)
        else:
            if (cv_truth(cc_is_int(v_t0)) and cv_truth(cv_getkey(v_t0, "signed"))):
                v_L = cce_lbl(v_self)
                cce_e(v_self, cv_text("test rax, rax"))
                cce_e(v_self, cv_cat(cv_text("jns "), cv_format(v_L, "")))
                cce_e(v_self, cv_text("neg rax"))
                cce_check_neg_overflow(v_self, v_t0)
                cce_narrow(v_self, v_t0)
                cce_label(v_self, v_L, 0)
        return v_rtype
    if ((cv_equal(v_name, cv_text("min")) or cv_equal(v_name, cv_text("max")))):
        let choice_20: i64 = cv_getkey(v_e, "common_w")
        if not cv_truth(choice_20):
            choice_20 = cv_getkey(cv_subscript(v_args, 3), "type")
        v_tc = choice_20
        v_i = cce_talloc(v_self)
        cce_expr_value(v_self, cv_subscript(v_args, 3), 0)
        if cv_truth(cc_is_float(v_tc)):
            cce_fconv(v_self, cv_getkey(cv_subscript(v_args, 3), "type"), v_tc)
            cce_store_scalar(v_self, cce_toff(v_self, v_i), v_tc, cv_text("float"))
            cce_expr_value(v_self, cv_subscript(v_args, 11), 0)
            cce_fconv(v_self, cv_getkey(cv_subscript(v_args, 11), "type"), v_tc)
            let choice_21: i64 = 0
            if (cv_equal(cv_getkey(v_tc, "bits"), 515)):
                choice_21 = cv_text("qword")
            else:
                choice_21 = cv_text("dword")
            v_pw = choice_21
            let choice_22: i64 = 0
            if (cv_equal(cv_getkey(v_tc, "bits"), 515)):
                choice_22 = cv_text("movsd xmm1")
            else:
                choice_22 = cv_text("movss xmm1")
            v_ins = choice_22
            let pieces_23: i64 = cv_list()
            cv_push(pieces_23, cv_format(v_ins, ""))
            cv_push(pieces_23, cv_text(", "))
            cv_push(pieces_23, cv_format(v_pw, ""))
            cv_push(pieces_23, cv_text(" ptr [rbp"))
            cv_push(pieces_23, cv_format(cce_toff(v_self, v_i), "+d"))
            cv_push(pieces_23, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_23))
            let choice_24: i64 = 0
            if (cv_equal(v_name, cv_text("min"))):
                choice_24 = cv_text("min")
            else:
                choice_24 = cv_text("max")
            let choice_25: i64 = 0
            if (cv_equal(cv_getkey(v_tc, "bits"), 515)):
                choice_25 = cv_text("sd")
            else:
                choice_25 = cv_text("ss")
            v_op = cv_add(choice_24, choice_25)
            cce_e(v_self, cv_cat(cv_format(v_op, ""), cv_text(" xmm0, xmm1")))
            if (cv_truth(cc_is_float(cv_getkey(cv_subscript(v_args, 3), "type"))) and (not (cv_equal(cv_getkey(cv_getkey(cv_subscript(v_args, 3), "type"), "bits"), cv_getkey(v_tc, "bits"))))):
                cce_fconv(v_self, v_tc, cv_getkey(cv_subscript(v_args, 3), "type"))
            return cv_getkey(cv_subscript(v_args, 3), "type")
        cce_store_scalar(v_self, cce_toff(v_self, v_i), v_tc, cv_text("int"))
        cce_expr_value(v_self, cv_subscript(v_args, 11), 0)
        cce_e(v_self, cv_text("mov rcx, rax"))
        cce_load_from_slot(v_self, cce_toff(v_self, v_i), v_tc)
        cce_e(v_self, cv_text("cmp rax, rcx"))
        v_sgn = cv_getkey(v_tc, "signed")
        let choice_26: i64 = 0
        if cv_truth(v_sgn):
            let choice_27: i64 = 0
            if (cv_equal(v_name, cv_text("min"))):
                choice_27 = cv_text("ge")
            else:
                choice_27 = cv_text("l")
            choice_26 = choice_27
        else:
            let choice_28: i64 = 0
            if (cv_equal(v_name, cv_text("min"))):
                choice_28 = cv_text("ae")
            else:
                choice_28 = cv_text("b")
            choice_26 = choice_28
        v_cc = choice_26
        let pieces_29: i64 = cv_list()
        cv_push(pieces_29, cv_text("cmov"))
        cv_push(pieces_29, cv_format(v_cc, ""))
        cv_push(pieces_29, cv_text(" rax, rcx"))
        cce_e(v_self, cv_join(cv_text(""), pieces_29))
        if (cv_truth(cc_is_int(cv_getkey(cv_subscript(v_args, 3), "type"))) and (not (cv_equal(cv_getkey(cv_getkey(cv_subscript(v_args, 3), "type"), "bits"), cv_getkey(v_tc, "bits"))))):
            cce_check_int_conversion(v_self, v_tc, cv_getkey(cv_subscript(v_args, 3), "type"))
        return cv_getkey(cv_subscript(v_args, 3), "type")
    cc_error(cv_add(cv_text("внутр: неизвестный intrinsic "), v_name), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_get(v_e, cv_text("line"), 11))
    return 0

unsafe fn cce_slot_of(v_self: i64, v_e: i64) -> i64:
    let v_s: i64 = 0
    v_s = cv_get(v_e, cv_text("slot"), 0)
    if cv_classes(v_s, "SlotK"):
        return v_s
    if (cv_classes(v_s, "int") and (cv_le(3, v_s)) and (cv_less(v_s, cv_length(cv_getkey(v_self, "slots"))))):
        return cv_subscript(cv_getkey(v_self, "slots"), v_s)
    return 0

unsafe fn cce_assign_conv(v_self: i64, v_vt: i64, v_pt: i64) -> i64:
    if ((v_pt == 0) or (v_vt == 0) or (cv_equal(v_vt, v_pt))):
        return 0
    if cv_truth(cc_is_ptr(v_pt)):
        return 0
    if cv_truth(cc_is_float(v_pt)):
        if (cv_truth(cc_is_int(v_vt)) or cv_truth(cc_is_bool(v_vt))):
            cce_int_to_float(v_self, v_vt, v_pt)
        else:
            if cv_truth(cc_is_float(v_vt)):
                cce_fconv(v_self, v_vt, v_pt)
        return 0
    if cv_truth(cc_is_int(v_pt)):
        if cv_truth(cc_is_float(v_vt)):
            cce_float_to_int(v_self, v_vt, v_pt)
        else:
            if cv_truth(cc_is_int(v_vt)):
                cce_check_int_conversion(v_self, v_vt, v_pt)
        return 0
    return 0

unsafe fn cce_store_at_mem(v_self: i64, v_t: i64, v_areg: i64, v_kind: i64) -> i64:
    let v_w: i64 = 0
    let v_m: i64 = 0
    let v_r: i64 = 0
    if ((cv_equal(v_kind, cv_text("float"))) or cv_truth(cc_is_float(v_t))):
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            let pieces_1: i64 = cv_list()
            cv_push(pieces_1, cv_text("movsd qword ptr ["))
            cv_push(pieces_1, cv_format(v_areg, ""))
            cv_push(pieces_1, cv_text("], xmm0"))
            cce_e(v_self, cv_join(cv_text(""), pieces_1))
        else:
            let pieces_2: i64 = cv_list()
            cv_push(pieces_2, cv_text("movss dword ptr ["))
            cv_push(pieces_2, cv_format(v_areg, ""))
            cv_push(pieces_2, cv_text("], xmm0"))
            cce_e(v_self, cv_join(cv_text(""), pieces_2))
        return 0
    if (cv_truth(cc_is_bool(v_t)) or (cv_truth(cc_is_int(v_t)) and (cv_equal(cv_getkey(v_t, "bits"), 67)) and not (cv_truth(cv_getkey(v_t, "signed"))))):
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("mov byte ptr ["))
        cv_push(pieces_3, cv_format(v_areg, ""))
        cv_push(pieces_3, cv_text("], al"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        return 0
    v_w = cce_int_width(v_self, v_t)
    let dict_4: i64 = cv_dict()
    cv_set(dict_4, 11, cv_text("byte"))
    cv_set(dict_4, 19, cv_text("word"))
    cv_set(dict_4, 35, cv_text("dword"))
    cv_set(dict_4, 67, cv_text("qword"))
    v_m = cv_subscript(dict_4, v_w)
    let dict_5: i64 = cv_dict()
    cv_set(dict_5, 11, cv_text("al"))
    cv_set(dict_5, 19, cv_text("ax"))
    cv_set(dict_5, 35, cv_text("eax"))
    cv_set(dict_5, 67, cv_text("rax"))
    v_r = cv_subscript(dict_5, v_w)
    let pieces_6: i64 = cv_list()
    cv_push(pieces_6, cv_text("mov "))
    cv_push(pieces_6, cv_format(v_m, ""))
    cv_push(pieces_6, cv_text(" ptr ["))
    cv_push(pieces_6, cv_format(v_areg, ""))
    cv_push(pieces_6, cv_text("], "))
    cv_push(pieces_6, cv_format(v_r, ""))
    cce_e(v_self, cv_join(cv_text(""), pieces_6))
    return 0

unsafe fn cce_reload_into(v_self: i64, v_reg: i64, v_ti: i64, v_t: i64) -> i64:
    if cv_truth(cc_is_float(v_t)):
        cce_reload_tmp(v_self, v_ti, v_t)
        return 0
    let pieces_1: i64 = cv_list()
    cv_push(pieces_1, cv_text("mov "))
    cv_push(pieces_1, cv_format(v_reg, ""))
    cv_push(pieces_1, cv_text(", qword ptr [rbp"))
    cv_push(pieces_1, cv_format(cce_toff(v_self, v_ti), "+d"))
    cv_push(pieces_1, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_1))
    return 0

unsafe fn cce_reload_tmp(v_self: i64, v_ti: i64, v_t: i64) -> i64:
    let v_pw: i64 = 0
    let v_ins: i64 = 0
    if cv_truth(cc_is_float(v_t)):
        let choice_1: i64 = 0
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            choice_1 = cv_text("qword")
        else:
            choice_1 = cv_text("dword")
        v_pw = choice_1
        let choice_2: i64 = 0
        if (cv_equal(cv_getkey(v_t, "bits"), 515)):
            choice_2 = cv_text("movsd xmm0")
        else:
            choice_2 = cv_text("movss xmm0")
        v_ins = choice_2
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_format(v_ins, ""))
        cv_push(pieces_3, cv_text(", "))
        cv_push(pieces_3, cv_format(v_pw, ""))
        cv_push(pieces_3, cv_text(" ptr [rbp"))
        cv_push(pieces_3, cv_format(cce_toff(v_self, v_ti), "+d"))
        cv_push(pieces_3, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        return 0
    let pieces_4: i64 = cv_list()
    cv_push(pieces_4, cv_text("mov rax, qword ptr [rbp"))
    cv_push(pieces_4, cv_format(cce_toff(v_self, v_ti), "+d"))
    cv_push(pieces_4, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_4))
    return 0

unsafe fn cce_save_val(v_self: i64, v_ti: i64, v_t: i64, v_kind: i64) -> i64:
    if ((cv_equal(v_kind, cv_text("float"))) or cv_truth(cc_is_float(v_t))):
        cce_store_scalar(v_self, cce_toff(v_self, v_ti), v_t, cv_text("float"))
        return 0
    let pieces_1: i64 = cv_list()
    cv_push(pieces_1, cv_text("mov qword ptr [rbp"))
    cv_push(pieces_1, cv_format(cce_toff(v_self, v_ti), "+d"))
    cv_push(pieces_1, cv_text("], rax"))
    cce_e(v_self, cv_join(cv_text(""), pieces_1))
    return 0

unsafe fn cce_zero_range(v_self: i64, v_soff_val: i64, v_size: i64) -> i64:
    let v_off: i64 = 0
    let v_rem: i64 = 0
    if (cv_le(v_size, 3)):
        return 0
    if (cv_le(v_size, 259)):
        v_off = v_soff_val
        v_rem = v_size
        while (cv_less(3, v_rem)):
            if (cv_le(67, v_rem)):
                let pieces_1: i64 = cv_list()
                cv_push(pieces_1, cv_text("mov qword ptr [rbp"))
                cv_push(pieces_1, cv_format(v_off, "+d"))
                cv_push(pieces_1, cv_text("], 0"))
                cce_e(v_self, cv_join(cv_text(""), pieces_1))
                v_rem = cv_sub(v_rem, 67)
                v_off = cv_add(v_off, 67)
            else:
                if (cv_le(35, v_rem)):
                    let pieces_2: i64 = cv_list()
                    cv_push(pieces_2, cv_text("mov dword ptr [rbp"))
                    cv_push(pieces_2, cv_format(v_off, "+d"))
                    cv_push(pieces_2, cv_text("], 0"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_2))
                    v_rem = cv_sub(v_rem, 35)
                    v_off = cv_add(v_off, 35)
                else:
                    if (cv_le(19, v_rem)):
                        let pieces_3: i64 = cv_list()
                        cv_push(pieces_3, cv_text("mov word ptr [rbp"))
                        cv_push(pieces_3, cv_format(v_off, "+d"))
                        cv_push(pieces_3, cv_text("], 0"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_3))
                        v_rem = cv_sub(v_rem, 19)
                        v_off = cv_add(v_off, 19)
                    else:
                        let pieces_4: i64 = cv_list()
                        cv_push(pieces_4, cv_text("mov byte ptr [rbp"))
                        cv_push(pieces_4, cv_format(v_off, "+d"))
                        cv_push(pieces_4, cv_text("], 0"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_4))
                        v_rem = cv_sub(v_rem, 11)
                        v_off = cv_add(v_off, 11)
        return 0
    let pieces_5: i64 = cv_list()
    cv_push(pieces_5, cv_text("lea rdi, [rbp"))
    cv_push(pieces_5, cv_format(v_soff_val, "+d"))
    cv_push(pieces_5, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_5))
    cce_e(v_self, cv_cat(cv_text("mov ecx, "), cv_format(v_size, "")))
    cce_e(v_self, cv_text("xor eax, eax"))
    cce_e(v_self, cv_text("cld"))
    cce_e(v_self, cv_text("rep stosb"))
    return 0

unsafe fn cce_copy_bytes(v_self: i64, v_size: i64) -> i64:
    if (cv_le(v_size, 3)):
        return 0
    cce_e(v_self, cv_cat(cv_text("mov ecx, "), cv_format(v_size, "")))
    cce_e(v_self, cv_text("cld"))
    cce_e(v_self, cv_text("rep movsb"))
    return 0

unsafe fn cce_copy_from_rax(v_self: i64, off: i64, size: i64):
    cce_e(v_self, cv_text("mov rsi, rax"))
    cce_e(v_self, cv_mod(cv_text("lea rdi, [rbp%+d]"), off))
    cce_copy_bytes(v_self, size)

unsafe fn cce_memcopy(v_self: i64, v_dst_lea: i64, v_src_addr_e: i64, v_size: i64) -> i64:
    let v_t: i64 = 0
    if (cv_le(v_size, 3)):
        return 0
    v_t = cce_talloc(v_self)
    cce_eaddr(v_self, v_src_addr_e)
    let pieces_1: i64 = cv_list()
    cv_push(pieces_1, cv_text("mov qword ptr [rbp"))
    cv_push(pieces_1, cv_format(cce_toff(v_self, v_t), "+d"))
    cv_push(pieces_1, cv_text("], rax"))
    cce_e(v_self, cv_join(cv_text(""), pieces_1))
    let pieces_2: i64 = cv_list()
    cv_push(pieces_2, cv_text("lea rdi, ["))
    cv_push(pieces_2, cv_format(v_dst_lea, ""))
    cv_push(pieces_2, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_2))
    let pieces_3: i64 = cv_list()
    cv_push(pieces_3, cv_text("mov rsi, qword ptr [rbp"))
    cv_push(pieces_3, cv_format(cce_toff(v_self, v_t), "+d"))
    cv_push(pieces_3, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_3))
    cce_copy_bytes(v_self, v_size)
    return 0

unsafe fn cce_emit_slice(v_self: i64, v_expr: i64) -> i64:
    let v_base: i64 = cv_getkey(v_expr, "base")
    let v_typ: i64 = cv_getkey(v_base, "type")
    let v_pair: i64 = cce_talloc(v_self)
    let v_offset: i64 = cv_index(cce_toff(v_self, v_pair))
    let v_address: i64 = cce_abi_mem("rbp", v_offset, 8)
    let v_length: i64 = cce_abi_mem("rbp", v_offset + 8, 8)
    cce_eaddr(v_self, v_base)
    if cv_classes(v_typ, "TSlice"):
        cce_e(v_self, cv_text("mov rdx, qword ptr [rax+8]"))
        cce_e(v_self, cv_text("mov rax, qword ptr [rax]"))
    else:
        cce_e(v_self, cv_cat(cv_text("mov rdx, "), cv_format(cv_getkey(v_typ, "n"), "")))
    cce_abi_mov(v_self, "mov", v_address, cv_text("rax"))
    cce_abi_mov(v_self, "mov", v_length, cv_text("rdx"))
    let v_bound: i64 = cce_talloc(v_self)
    let v_lo: i64 = cce_abi_mem("rbp", cv_index(cce_toff(v_self, v_bound)), 8)
    cce_expr_value(v_self, cv_getkey(v_expr, "start"), 0)
    cce_abi_mov(v_self, "mov", v_lo, cv_text("rax"))
    cce_expr_value(v_self, cv_getkey(v_expr, "end"), 0)
    cce_abi_mov(v_self, "mov", cv_text("rcx"), v_lo)
    let v_bad: i64 = cce_lbl(v_self)
    let v_valid: i64 = cce_lbl(v_self)
    # rax = end, rcx = start. After 0 <= start <= end, end is also non-negative.
    cce_e(v_self, cv_text("test rcx, rcx"))
    cce_e(v_self, cv_cat(cv_text("js "), cv_format(v_bad, "")))
    cce_e(v_self, cv_text("cmp rcx, rax"))
    cce_e(v_self, cv_cat(cv_text("jg "), cv_format(v_bad, "")))
    cce_abi_mov(v_self, "cmp", cv_text("rax"), v_length)
    cce_e(v_self, cv_cat(cv_text("jg "), cv_format(v_bad, "")))
    cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_valid, "")))
    cce_label(v_self, v_bad, 0)
    cce_emit_panic(v_self, cv_text("volt: invalid slice range\n"))
    cce_label(v_self, v_valid, 0)
    cce_e(v_self, cv_text("sub rax, rcx"))
    cce_abi_mov(v_self, "mov", v_length, cv_text("rax"))
    cce_e(v_self, cv_cat(cv_text("imul rcx, rcx, "), cv_format(cc_type_size(cv_getkey(v_typ, "elem")), "")))
    cce_abi_mov(v_self, "add", v_address, cv_text("rcx"))
    cce_e(v_self, cv_mod(cv_text("lea rax, [rbp%+d]"), cce_toff(v_self, v_pair)))
    cce_trelease(v_self, cv_add(v_pair, 11))
    return 0

unsafe fn cce_begin_stmt(v_self: i64) -> i64:
    cv_field(v_self, "nt", cv_getkey(v_self, "for_floor"))
    return 0

unsafe fn cce_emit_stmts(v_self: i64, v_stmts: i64) -> i64:
    let v_frame: i64 = 0
    let v_st: i64 = 0
    let v_flag: i64 = 0
    let items_1: i64 = cv_vector(CV_LIST)
    v_frame = items_1
    let scopes: i64 = cv_getkey(cv_getkey(v_self, "cur"), "owner_scopes")
    let owners: i64 = cv_get(scopes, cv_i(v_stmts), 0)
    cv_push(cv_getkey(v_self, "defer_frames"), cv_pair(v_frame, owners))
    for i in 0..cv_len(owners):
        let slot: i64 = cv_at(owners, i)
        let live: i64 = 0
        if cv_name(cv_getkey(slot, "kind"), "param") or cv_truth(cv_getkey(slot, "owner_at_entry")): live = 1
        cce_owner_flag(v_self, slot, live)
    let seq_3: i64 = v_stmts
    for index_2 in 0..cv_len(seq_3):
        v_st = cv_at(seq_3, index_2)
        if cv_classes(v_st, "DeferStmt"):
            v_flag = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_st, "flag_slot"))
            let pieces_4: i64 = cv_list()
            cv_push(pieces_4, cv_text("mov qword ptr [rbp"))
            cv_push(pieces_4, cv_format(cce_soff(v_self, v_flag), "+d"))
            cv_push(pieces_4, cv_text("], 0"))
            cce_e(v_self, cv_join(cv_text(""), pieces_4))
    let seq_6: i64 = v_stmts
    for index_5 in 0..cv_len(seq_6):
        v_st = cv_at(seq_6, index_5)
        if cv_classes(v_st, "DeferStmt"):
            cv_push(v_frame, v_st)
            v_flag = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_st, "flag_slot"))
            let pieces_7: i64 = cv_list()
            cv_push(pieces_7, cv_text("mov qword ptr [rbp"))
            cv_push(pieces_7, cv_format(cce_soff(v_self, v_flag), "+d"))
            cv_push(pieces_7, cv_text("], 1"))
            cce_e(v_self, cv_join(cv_text(""), pieces_7))
        else:
            cce_emit_stmt(v_self, v_st)
    cce_emit_defer_frame(v_self, v_frame)
    cce_drop_owners(v_self, owners)
    cv_pop(cv_getkey(v_self, "defer_frames"))
    return 0

unsafe fn cce_owner_flag_addr(emitter: i64, slot: i64) -> i64:
    let flag: i64 = cv_getkey(slot, "owner_flag")
    if flag == 0: return 0
    return cce_soff(emitter, cv_subscript(cv_getkey(emitter, "slots"), flag))

unsafe fn cce_owner_flag(emitter: i64, slot: i64, live: i64):
    let off: i64 = cce_owner_flag_addr(emitter, slot)
    if off != 0: cce_e(emitter, cv_mod(cv_text("mov qword ptr [rbp%+d], %d"), cv_pair(off, cv_i(live))))

unsafe fn cce_drop_owner(emitter: i64, slot: i64):
    let off: i64 = cce_owner_flag_addr(emitter, slot)
    let skip: i64 = cce_lbl(emitter)
    let file: i64 = cv_getkey(cv_getkey(emitter, "sem"), "owned_buffer_file")
    cce_e(emitter, cv_mod(cv_text("cmp qword ptr [rbp%+d], 0"), off))
    cce_e(emitter, cv_cat(cv_text("je "), skip))
    cce_owner_flag(emitter, slot, 0)
    let storage: i64 = cce_soff(emitter, slot)
    let typ: i64 = cv_getkey(slot, "typ")
    if cc_is_owned_result(typ):
        cce_e(emitter, cv_mod(cv_text("cmp qword ptr [rbp%+d], 0"), storage))
        cce_e(emitter, cv_cat(cv_text("jne "), skip))
        storage = cv_add(storage, cv_getkey(typ, "payload_off"))
    cce_e(emitter, cv_mod(cv_text("lea rdi, [rbp%+d]"), storage))
    cce_e(emitter, cv_cat(cv_text("call "), cc_function_label(cv_text("__volt_owned_buffer_drop"), file)))
    cce_label(emitter, skip, 0)

unsafe fn cce_drop_owners(emitter: i64, owners: i64):
    for i in 0..cv_len(owners): cce_drop_owner(emitter, cv_at(owners, -1 - i))

unsafe fn cce_emit_defer_frame(v_self: i64, v_frame: i64) -> i64:
    let v_st: i64 = 0
    let v_flag: i64 = 0
    let v_skip: i64 = 0
    let seq_2: i64 = cv_reverse(v_frame)
    for index_1 in 0..cv_len(seq_2):
        v_st = cv_at(seq_2, index_1)
        v_flag = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_st, "flag_slot"))
        v_skip = cce_lbl(v_self)
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("cmp qword ptr [rbp"))
        cv_push(pieces_3, cv_format(cce_soff(v_self, v_flag), "+d"))
        cv_push(pieces_3, cv_text("], 0"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        cce_e(v_self, cv_cat(cv_text("je "), cv_format(v_skip, "")))
        let pieces_4: i64 = cv_list()
        cv_push(pieces_4, cv_text("mov qword ptr [rbp"))
        cv_push(pieces_4, cv_format(cce_soff(v_self, v_flag), "+d"))
        cv_push(pieces_4, cv_text("], 0"))
        cce_e(v_self, cv_join(cv_text(""), pieces_4))
        cce_emit_stmt(v_self, cv_getkey(v_st, "action"))
        cce_label(v_self, v_skip, 0)
    return 0

unsafe fn cce_emit_cleanup_scopes(v_self: i64, v_count: i64) -> i64:
    let v_frame: i64 = 0
    let choice_3: i64 = 0
    if cv_truth(v_count):
        choice_3 = cv_slice(cv_getkey(v_self, "defer_frames"), cv_neg(v_count), 0)
    else:
        let items_4: i64 = cv_vector(CV_LIST)
        choice_3 = items_4
    let seq_2: i64 = cv_reverse(choice_3)
    for index_1 in 0..cv_len(seq_2):
        v_frame = cv_at(seq_2, index_1)
        cce_emit_defer_frame(v_self, cv_at(v_frame, 0))
        cce_drop_owners(v_self, cv_at(v_frame, 1))
    return 0

unsafe fn cce_emit_stmt(v_self: i64, v_st: i64) -> i64:
    cce_begin_stmt(v_self)
    if cv_classes(v_st, "LetStmt"):
        cce_st_let(v_self, v_st)
        let slot: i64 = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_st, "slot"))
        cce_owner_flag(v_self, cv_getkey(cv_getkey(v_st, "init"), "owner_transfer"), 0)
        cce_owner_flag(v_self, slot, 1)
    else:
        if cv_classes(v_st, "AssignStmt"):
            cce_st_assign(v_self, v_st)
        else:
            if cv_classes(v_st, "ExprStmt"):
                cce_st_expr(v_self, v_st)
            else:
                if cv_classes(v_st, "IfStmt"):
                    cce_st_if(v_self, v_st)
                else:
                    if cv_classes(v_st, "WhileStmt"):
                        cce_st_while(v_self, v_st)
                    else:
                        if cv_classes(v_st, "ForStmt"):
                            cce_st_for(v_self, v_st)
                        else:
                            if cv_classes(v_st, "BreakStmt"):
                                if not (cv_truth(cv_getkey(v_self, "loop"))):
                                    cc_error(cv_text("break вне цикла"), cv_get(cv_getkey(v_self, "cur"), cv_text("file"), 0), cv_getkey(v_st, "line"))
                                    return 0
                                cce_emit_cleanup_scopes(v_self, cv_getkey(v_st, "cleanup_scopes"))
                                cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(cv_subscript(cv_subscript(cv_getkey(v_self, "loop"), cv_neg(11)), 3), "")))
                            else:
                                if cv_classes(v_st, "ContinueStmt"):
                                    if not (cv_truth(cv_getkey(v_self, "loop"))):
                                        cc_error(cv_text("continue вне цикла"), cv_get(cv_getkey(v_self, "cur"), cv_text("file"), 0), cv_getkey(v_st, "line"))
                                        return 0
                                    cce_emit_cleanup_scopes(v_self, cv_getkey(v_st, "cleanup_scopes"))
                                    cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(cv_subscript(cv_subscript(cv_getkey(v_self, "loop"), cv_neg(11)), 11), "")))
                                else:
                                    if cv_classes(v_st, "ReturnStmt"):
                                        cce_st_return(v_self, v_st)
                                    else:
                                        if cv_classes(v_st, "MatchStmt"):
                                            cce_emit_match(v_self, v_st)
                                        else:
                                            if cv_classes(v_st, "ConstStmt"):
                                                0
                                            else:
                                                if cv_classes(v_st, "UnsafeStmt"):
                                                    cce_emit_stmts(v_self, cv_getkey(v_st, "body"))
                                                else:
                                                    cc_error(cv_add(cv_text("кодоген: неизвестный стейтмент "), cv_typename(v_st)), cv_get(cv_getkey(v_self, "cur"), cv_text("file"), 0), cv_getkey(v_st, "line"))
                                                    return 0
    return 0

unsafe fn cce_emit_match(v_self: i64, v_st: i64) -> i64:
    let v_t: i64 = 0
    let v_source: i64 = 0
    let v_done: i64 = 0
    let v_arm: i64 = 0
    let v_nxt: i64 = 0
    let v_tag: i64 = 0
    let v_off: i64 = 0
    let value: i64 = cv_getkey(v_st, "value")
    v_t = cv_getkey(value, "type")
    v_source = cce_talloc(v_self)
    cce_expr_value(v_self, value, 0)
    let pieces_1: i64 = cv_list()
    cv_push(pieces_1, cv_text("mov qword ptr [rbp"))
    cv_push(pieces_1, cv_format(cce_toff(v_self, v_source), "+d"))
    cv_push(pieces_1, cv_text("], rax"))
    cce_e(v_self, cv_join(cv_text(""), pieces_1))
    v_done = cce_lbl(v_self)
    let seq_3: i64 = cv_getkey(v_st, "arms")
    for index_2 in 0..cv_len(seq_3):
        v_arm = cv_at(seq_3, index_2)
        v_nxt = cce_lbl(v_self)
        let choice_4: i64 = 0
        if (cv_equal(cv_getkey(v_arm, "pattern"), cv_text("_"))):
            choice_4 = 0
        else:
            choice_4 = cv_getkey(v_arm, "tag")
        v_tag = choice_4
        cce_e(v_self, cv_mod(cv_text("mov rax, qword ptr [rbp%+d]"), cce_toff(v_self, v_source)))
        if cc_is_tagged_value(v_t): cce_e(v_self, cv_text("mov rax, qword ptr [rax]"))
        if (not (v_tag == 0)):
            if cc_tag_imm32(v_tag):
                cce_e(v_self, cv_cat(cv_text("cmp rax, "), cv_format(v_tag, "")))
            else:
                cce_e(v_self, cv_cat(cv_text("mov rdx, "), cv_format(v_tag, "")))
                cce_e(v_self, cv_text("cmp rax, rdx"))
            cce_e(v_self, cv_cat(cv_text("jne "), cv_format(v_nxt, "")))
        if cv_truth(cv_getkey(v_arm, "binding")):
            v_off = cv_getkey(v_t, "payload_off")
            let pieces_7: i64 = cv_list()
            cv_push(pieces_7, cv_text("mov rsi, qword ptr [rbp"))
            cv_push(pieces_7, cv_format(cce_toff(v_self, v_source), "+d"))
            cv_push(pieces_7, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_7))
            cce_e(v_self, cv_cat(cv_text("add rsi, "), cv_format(v_off, "")))
            let pieces_8: i64 = cv_list()
            cv_push(pieces_8, cv_text("lea rdi, [rbp"))
            cv_push(pieces_8, cv_format(cce_soff(v_self, cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_arm, "binding_slot"))), "+d"))
            cv_push(pieces_8, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_8))
            cce_copy_bytes(v_self, cc_type_size(cv_getkey(cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_arm, "binding_slot")), "typ")))
        let discard: i64 = cv_getkey(v_arm, "owner_discard")
        if discard != 0:
            cce_e(v_self, cv_mod(cv_text("mov rax, qword ptr [rbp%+d]"), cce_toff(v_self, v_source)))
            cce_copy_from_rax(v_self, cce_soff(v_self, discard), cc_type_size(v_t))
        cce_owner_flag(v_self, cv_getkey(value, "owner_transfer"), 0)
        cce_emit_stmts(v_self, cv_getkey(v_arm, "body"))
        cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_done, "")))
        cce_label(v_self, v_nxt, 0)
    cce_label(v_self, v_done, 0)
    return 0

unsafe fn cce_st_let(v_self: i64, v_st: i64) -> i64:
    let v_s: i64 = 0
    let v_init: i64 = 0
    let v_tmp: i64 = 0
    let v_items: i64 = 0
    let v_elem: i64 = 0
    let v_esz: i64 = 0
    let v_i: i64 = 0
    let v_item: i64 = 0
    let v_at: i64 = 0
    let v_t: i64 = 0
    v_s = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_st, "slot"))
    v_init = cv_getkey(v_st, "init")
    if cc_is_sum_ctor(v_init):
        cce_emit_sum_ctor(v_self, v_init, cce_soff(v_self, v_s))
        return 0
    if cc_is_tagged_value(cv_getkey(v_s, "typ")) and v_init != 0:
        cce_expr_value(v_self, v_init, 0)
        v_tmp = cce_talloc(v_self)
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("mov qword ptr [rbp"))
        cv_push(pieces_1, cv_format(cce_toff(v_self, v_tmp), "+d"))
        cv_push(pieces_1, cv_text("], rax"))
        cce_e(v_self, cv_join(cv_text(""), pieces_1))
        let pieces_2: i64 = cv_list()
        cv_push(pieces_2, cv_text("mov rsi, qword ptr [rbp"))
        cv_push(pieces_2, cv_format(cce_toff(v_self, v_tmp), "+d"))
        cv_push(pieces_2, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_2))
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("lea rdi, [rbp"))
        cv_push(pieces_3, cv_format(cce_soff(v_self, v_s), "+d"))
        cv_push(pieces_3, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_3))
        cce_e(v_self, cv_cat(cv_text("mov ecx, "), cv_format(cv_getkey(v_s, "size"), "")))
        cce_e(v_self, cv_text("cld"))
        cce_e(v_self, cv_text("rep movsb"))
        return 0
    if cv_classes(cv_getkey(v_s, "typ"), "TSlice"):
        cce_eaddr(v_self, v_init)
        cce_e(v_self, cv_text("mov rsi, rax"))
        let pieces_6: i64 = cv_list()
        cv_push(pieces_6, cv_text("lea rdi, [rbp"))
        cv_push(pieces_6, cv_format(cce_soff(v_self, v_s), "+d"))
        cv_push(pieces_6, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_6))
        cce_copy_bytes(v_self, cv_getkey(v_s, "size"))
        return 0
    if ((not (v_init == 0)) and (cv_equal(cv_get(v_init, cv_text("kindt"), 0), cv_text("ctor")))):
        cce_emit_ctor(v_self, v_init, cce_soff(v_self, v_s))
        return 0
    if (not (cv_get(v_st, cv_text("aitems"), 0) == 0)):
        v_items = cv_getkey(v_st, "aitems")
        let choice_7: i64 = 0
        if (not (cv_get(v_st, cv_text("init_elem"), 0) == 0)):
            choice_7 = cv_getkey(v_st, "init_elem")
        else:
            choice_7 = cv_getkey(cv_getkey(v_s, "typ"), "elem")
        v_elem = choice_7
        v_esz = cc_type_size(v_elem)
        cce_zero_range(v_self, cce_soff(v_self, v_s), cv_getkey(v_s, "size"))
        let seq_9: i64 = cv_enumerate(v_items)
        for index_8 in 0..cv_len(seq_9):
            let unpack_10: i64 = cv_at(seq_9, index_8)
            v_i = cv_at(unpack_10, 0)
            v_item = cv_at(unpack_10, 1)
            v_at = cv_add(cce_soff(v_self, v_s), cv_mul(v_i, v_esz))
            if cv_truth(cc_is_struct(v_elem)):
                if (cv_equal(cv_get(v_item, cv_text("kindt"), 0), cv_text("ctor"))):
                    v_tmp = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_item, "temp_slot"))
                    cce_emit_ctor(v_self, v_item, cce_soff(v_self, v_tmp))
                    let pieces_11: i64 = cv_list()
                    cv_push(pieces_11, cv_text("lea rsi, [rbp"))
                    cv_push(pieces_11, cv_format(cce_soff(v_self, v_tmp), "+d"))
                    cv_push(pieces_11, cv_text("]"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_11))
                    let pieces_12: i64 = cv_list()
                    cv_push(pieces_12, cv_text("lea rdi, [rbp"))
                    cv_push(pieces_12, cv_format(v_at, "+d"))
                    cv_push(pieces_12, cv_text("]"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_12))
                    cce_copy_bytes(v_self, v_esz)
                else:
                    cce_memcopy(v_self, cv_cat(cv_text("rbp"), cv_format(v_at, "+d")), v_item, v_esz)
                continue
            cce_expr_value(v_self, v_item, 0)
            cce_assign_conv(v_self, cv_getkey(v_item, "type"), v_elem)
            if cv_truth(cc_is_float(v_elem)):
                cce_store_scalar(v_self, v_at, v_elem, cv_text("float"))
            else:
                if cv_truth(cc_is_bool(v_elem)):
                    let pieces_13: i64 = cv_list()
                    cv_push(pieces_13, cv_text("mov byte ptr [rbp"))
                    cv_push(pieces_13, cv_format(v_at, "+d"))
                    cv_push(pieces_13, cv_text("], al"))
                    cce_e(v_self, cv_join(cv_text(""), pieces_13))
                else:
                    cce_store_scalar(v_self, v_at, v_elem, cv_text("int"))
        return 0
    if (v_init == 0):
        if cv_classes(cv_getkey(v_s, "typ"), "TWrapper"):
            cc_error(cv_text("Option/Result нельзя обнулять автоматически; используйте None/Ok/Err"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_st, "line"))
            return 0
        cce_zero_range(v_self, cce_soff(v_self, v_s), cv_getkey(v_s, "size"))
        return 0
    if cv_truth(cc_is_array(cv_getkey(v_s, "typ"))):
        cce_memcopy(v_self, cv_cat(cv_text("rbp"), cv_format(cce_soff(v_self, v_s), "+d")), v_init, cv_getkey(v_s, "size"))
        return 0
    if cv_truth(cc_is_struct(cv_getkey(v_s, "typ"))):
        cce_memcopy(v_self, cv_cat(cv_text("rbp"), cv_format(cce_soff(v_self, v_s), "+d")), v_init, cv_getkey(v_s, "size"))
        return 0
    v_t = cce_expr_value(v_self, v_init, 0)
    cce_assign_conv(v_self, v_t, cv_getkey(v_s, "typ"))
    let choice_14: i64 = 0
    if cv_truth(cc_is_float(cv_getkey(v_s, "typ"))):
        choice_14 = cv_text("float")
    else:
        choice_14 = cv_text("int")
    cce_store_scalar(v_self, cce_soff(v_self, v_s), cv_getkey(v_s, "typ"), choice_14)
    return 0

unsafe fn cc_tag_imm32(tag: i64) -> bool:
    return not cv_less(tag, cv_i(-2147483648)) and not cv_less(cv_i(2147483647), tag)

unsafe fn cce_emit_sum_ctor(v_self: i64, v_ctor: i64, v_base_soff: i64) -> i64:
    let v_typ: i64 = 0
    let v_arg: i64 = 0
    let v_pt: i64 = 0
    let v_at: i64 = 0
    v_typ = cv_getkey(v_ctor, "type")
    cce_zero_range(v_self, v_base_soff, cv_getkey(v_typ, "size"))
    let tag: i64 = cv_getkey(v_ctor, "variant")
    if cc_tag_imm32(tag):
        cce_e(v_self, cv_mod(cv_text("mov qword ptr [rbp%+d], %d"), cv_pair(v_base_soff, tag)))
    else:
        cce_e(v_self, cv_cat(cv_text("mov rax, "), cv_format(tag, "")))
        cce_e(v_self, cv_mod(cv_text("mov qword ptr [rbp%+d], rax"), v_base_soff))
    if cv_len(cv_getkey(v_ctor, "args")) != 0:
        v_arg = cv_subscript(cv_getkey(v_ctor, "args"), 3)
        v_pt = cv_getkey(v_arg, "type")
        v_at = cv_add(v_base_soff, cv_getkey(v_typ, "payload_off"))
        if cv_classes(v_pt, "TStruct"):
            if cv_name(cv_getkey(v_arg, "kindt"), "ctor"):
                cce_emit_ctor(v_self, v_arg, v_at)
            else:
                cce_eaddr(v_self, v_arg)
                cce_copy_from_rax(v_self, v_at, cc_type_size(v_pt))
            cce_owner_flag(v_self, cv_getkey(v_arg, "owner_transfer"), 0)
            return 0
        cce_expr_value(v_self, v_arg, 0)
        if cc_is_tagged_value(v_pt):
            cce_copy_from_rax(v_self, v_at, cc_type_size(v_pt))
            return 0
        let choice_4: i64 = 0
        if cv_truth(cc_is_float(v_pt)):
            choice_4 = cv_text("float")
        else:
            choice_4 = cv_text("int")
        cce_store_scalar(v_self, v_at, v_pt, choice_4)
    return 0

unsafe fn cce_emit_ctor(v_self: i64, v_ctor: i64, v_base_soff: i64) -> i64:
    let v_styp: i64 = 0
    let v_fname: i64 = 0
    let v_ft: i64 = 0
    let v_off: i64 = 0
    let v_fsz: i64 = 0
    let v_val: i64 = 0
    let v_at: i64 = 0
    v_styp = cv_getkey(v_ctor, "type")
    cce_zero_range(v_self, v_base_soff, cv_getkey(v_styp, "size"))
    let seq_2: i64 = cv_zip(cv_getkey(v_styp, "fields"), cv_getkey(v_ctor, "args"))
    for index_1 in 0..cv_len(seq_2):
        let unpack_3: i64 = cv_at(seq_2, index_1)
        let unpack_4: i64 = cv_at(unpack_3, 0)
        v_fname = cv_at(unpack_4, 0)
        v_ft = cv_at(unpack_4, 1)
        v_off = cv_at(unpack_4, 2)
        v_fsz = cv_at(unpack_4, 3)
        v_val = cv_at(unpack_3, 1)
        v_at = cv_add(v_base_soff, v_off)
        if (cv_truth(cc_is_struct(v_ft)) or cv_truth(cc_is_array(v_ft))):
            if (cv_equal(cv_get(v_val, cv_text("kindt"), 0), cv_text("ctor"))):
                cce_emit_ctor(v_self, v_val, v_at)
            else:
                cce_memcopy(v_self, cv_mod(cv_text("rbp%+d"), v_at), v_val, v_fsz)
            continue
        cce_expr_value(v_self, v_val, 0)
        cce_assign_conv(v_self, cv_getkey(v_val, "type"), v_ft)
        if cv_truth(cc_is_float(v_ft)):
            cce_store_scalar(v_self, v_at, v_ft, cv_text("float"))
        else:
            if cv_truth(cc_is_bool(v_ft)):
                let pieces_5: i64 = cv_list()
                cv_push(pieces_5, cv_text("mov byte ptr [rbp"))
                cv_push(pieces_5, cv_format(v_at, "+d"))
                cv_push(pieces_5, cv_text("], al"))
                cce_e(v_self, cv_join(cv_text(""), pieces_5))
            else:
                cce_store_scalar(v_self, v_at, v_ft, cv_text("int"))
    return 0

unsafe fn cce_st_assign(v_self: i64, v_st: i64) -> i64:
    let v_tg: i64 = 0
    let v_tt: i64 = 0
    let v_val: i64 = 0
    let v_slot: i64 = 0
    let v_tmp: i64 = 0
    let v_s: i64 = 0
    let v_tv: i64 = 0
    let v_compound: i64 = 0
    let v_t: i64 = 0
    v_tg = cv_getkey(v_st, "target")
    v_tt = cv_getkey(v_tg, "type")
    v_val = cv_getkey(v_st, "value")
    if cc_is_tagged_value(v_tt):
        if (not (cv_equal(cv_getkey(v_st, "op"), cv_text("=")))):
            cc_error(cv_text("Option/Result поддерживает только присваивание '='"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_st, "line"))
            return 0
        v_slot = cce_slot_of(v_self, v_tg)
        let logic_2: bool = (v_slot == 0)
        if not logic_2:
            let subject_1: i64 = cv_getkey(v_slot, "kind")
            logic_2 = (not ((cv_equal(subject_1, cv_text("local")) or cv_equal(subject_1, cv_text("param")))))
        if (logic_2):
            cc_error(cv_text("Option/Result присваивание поддерживается только для локальных переменных и параметров"), cv_getkey(cv_getkey(v_self, "cur"), "file"), cv_getkey(v_st, "line"))
            return 0
        let scratch: i64 = cv_getkey(v_self, "nt")
        cce_expr_value(v_self, v_val, 0)
        # RHS is materialized before writing; copying a slot to itself is safe.
        cce_copy_from_rax(v_self, cce_soff(v_self, v_slot), cc_type_size(v_tt))
        cce_trelease(v_self, scratch)
        return 0
    if (cv_classes(v_val, "Call") and (cv_equal(cv_get(v_val, cv_text("kindt"), 0), cv_text("ctor")))):
        v_tmp = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_val, "temp_slot"))
        cce_emit_ctor(v_self, v_val, cce_soff(v_self, v_tmp))
        cce_eaddr(v_self, v_tg)
        cce_e(v_self, cv_text("mov rdi, rax"))
        let pieces_8: i64 = cv_list()
        cv_push(pieces_8, cv_text("lea rsi, [rbp"))
        cv_push(pieces_8, cv_format(cce_soff(v_self, v_tmp), "+d"))
        cv_push(pieces_8, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_8))
        cce_copy_bytes(v_self, cc_type_size(v_tt))
        return 0
    if (cv_truth(cc_is_struct(v_tt)) or cv_truth(cc_is_array(v_tt))):
        v_s = cce_slot_of(v_self, v_tg)
        if (not (v_s == 0)):
            cce_memcopy(v_self, cv_cat(cv_text("rbp"), cv_format(cce_soff(v_self, v_s), "+d")), v_val, cc_type_size(v_tt))
        else:
            v_tv = cce_talloc(v_self)
            cce_eaddr(v_self, v_val)
            let pieces_9: i64 = cv_list()
            cv_push(pieces_9, cv_text("mov qword ptr [rbp"))
            cv_push(pieces_9, cv_format(cce_toff(v_self, v_tv), "+d"))
            cv_push(pieces_9, cv_text("], rax"))
            cce_e(v_self, cv_join(cv_text(""), pieces_9))
            cce_eaddr(v_self, v_tg)
            cce_e(v_self, cv_text("mov rdi, rax"))
            let pieces_10: i64 = cv_list()
            cv_push(pieces_10, cv_text("mov rsi, qword ptr [rbp"))
            cv_push(pieces_10, cv_format(cce_toff(v_self, v_tv), "+d"))
            cv_push(pieces_10, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_10))
            cce_copy_bytes(v_self, cc_type_size(v_tt))
            cce_trelease(v_self, v_tv)
        return 0
    v_compound = cv_bool((not (cv_equal(cv_getkey(v_st, "op"), cv_text("=")))))
    if ((not (cce_slot_of(v_self, v_tg) == 0)) and not (cv_truth(v_compound))):
        v_slot = cce_slot_of(v_self, v_tg)
        v_t = cce_expr_value(v_self, v_val, 0)
        cce_assign_conv(v_self, v_t, v_tt)
        let choice_11: i64 = 0
        if cv_truth(cc_is_float(v_tt)):
            choice_11 = cv_text("float")
        else:
            choice_11 = cv_text("int")
        cce_store_scalar(v_self, cce_soff(v_self, v_slot), v_tt, choice_11)
        return 0
    cce_st_assign_mem(v_self, v_st, v_tg, v_tt, v_compound)
    return 0

unsafe fn cce_synop(v_self: i64, v_op: i64, v_line: i64) -> i64:
    let v_b: i64 = 0
    v_b = cc_Binary(v_op, 0, 0, v_line)
    return v_b

unsafe fn cce_st_assign_mem(v_self: i64, v_st: i64, v_tg: i64, v_tt: i64, v_compound: i64) -> i64:
    let v_tval: i64 = 0
    let v_tc: i64 = 0
    let v_taddr: i64 = 0
    let v_told: i64 = 0
    let v_pw: i64 = 0
    let v_ins: i64 = 0
    let v_syn: i64 = 0
    let v_tres: i64 = 0
    if not (cv_truth(v_compound)):
        v_tval = cce_talloc(v_self)
        cce_expr_value(v_self, cv_getkey(v_st, "value"), 0)
        cce_assign_conv(v_self, cv_getkey(cv_getkey(v_st, "value"), "type"), v_tt)
        cce_save_val(v_self, v_tval, v_tt, 0)
        cce_eaddr(v_self, v_tg)
        cce_e(v_self, cv_text("mov rdi, rax"))
        cce_reload_tmp(v_self, v_tval, v_tt)
        cce_store_at_mem(v_self, v_tt, cv_text("rdi"), 0)
        return 0
    v_tc = cv_get(v_st, cv_text("compound_type"), v_tt)
    v_taddr = cce_talloc(v_self)
    cce_eaddr(v_self, v_tg)
    let pieces_1: i64 = cv_list()
    cv_push(pieces_1, cv_text("mov qword ptr [rbp"))
    cv_push(pieces_1, cv_format(cce_toff(v_self, v_taddr), "+d"))
    cv_push(pieces_1, cv_text("], rax"))
    cce_e(v_self, cv_join(cv_text(""), pieces_1))
    v_told = cce_talloc(v_self)
    let pieces_2: i64 = cv_list()
    cv_push(pieces_2, cv_text("mov rax, qword ptr [rbp"))
    cv_push(pieces_2, cv_format(cce_toff(v_self, v_taddr), "+d"))
    cv_push(pieces_2, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_2))
    cce_load_from_mem(v_self, v_tt)
    if cv_truth(cc_is_float(v_tc)):
        cce_fconv(v_self, v_tt, v_tc)
    else:
        let logic_4: bool = cv_truth(cc_is_int(v_tc))
        if logic_4:
            let subject_3: i64 = cv_getkey(v_st, "op")
            logic_4 = (not ((cv_equal(subject_3, cv_text("<<")) or cv_equal(subject_3, cv_text(">>")))))
        if (logic_4):
            cce_narrow(v_self, v_tc)
    cce_save_val(v_self, v_told, v_tc, 0)
    v_tval = cce_talloc(v_self)
    cce_expr_value(v_self, cv_getkey(v_st, "value"), 0)
    if cv_truth(cc_is_float(v_tc)):
        cce_fconv(v_self, cv_getkey(cv_getkey(v_st, "value"), "type"), v_tc)
    else:
        let logic_6: bool = cv_truth(cc_is_int(v_tc))
        if logic_6:
            let subject_5: i64 = cv_getkey(v_st, "op")
            logic_6 = (not ((cv_equal(subject_5, cv_text("<<")) or cv_equal(subject_5, cv_text(">>")))))
        if (logic_6):
            cce_narrow(v_self, v_tc)
    let choice_7: i64 = 0
    let subject_8: i64 = cv_getkey(v_st, "op")
    if ((cv_equal(subject_8, cv_text("<<")) or cv_equal(subject_8, cv_text(">>")))):
        choice_7 = cv_getkey(cv_getkey(v_st, "value"), "type")
    else:
        choice_7 = v_tc
    cce_save_val(v_self, v_tval, choice_7, 0)
    if cv_truth(cc_is_float(v_tc)):
        let choice_9: i64 = 0
        if (cv_equal(cv_getkey(v_tc, "bits"), 515)):
            choice_9 = cv_text("qword")
        else:
            choice_9 = cv_text("dword")
        v_pw = choice_9
        let choice_10: i64 = 0
        if (cv_equal(cv_getkey(v_tc, "bits"), 515)):
            choice_10 = cv_text("movsd xmm1")
        else:
            choice_10 = cv_text("movss xmm1")
        v_ins = choice_10
        let pieces_11: i64 = cv_list()
        cv_push(pieces_11, cv_format(v_ins, ""))
        cv_push(pieces_11, cv_text(", "))
        cv_push(pieces_11, cv_format(v_pw, ""))
        cv_push(pieces_11, cv_text(" ptr [rbp"))
        cv_push(pieces_11, cv_format(cce_toff(v_self, v_told), "+d"))
        cv_push(pieces_11, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_11))
        cce_reload_tmp(v_self, v_tval, v_tc)
        cce_float_op(v_self, cce_synop(v_self, cv_getkey(v_st, "op"), cv_getkey(v_st, "line")), v_tc)
    else:
        let pieces_12: i64 = cv_list()
        cv_push(pieces_12, cv_text("mov rcx, qword ptr [rbp"))
        cv_push(pieces_12, cv_format(cce_toff(v_self, v_tval), "+d"))
        cv_push(pieces_12, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_12))
        cce_reload_tmp(v_self, v_told, v_tc)
        v_syn = cce_synop(v_self, cv_getkey(v_st, "op"), cv_getkey(v_st, "line"))
        let subject_13: i64 = cv_getkey(v_st, "op")
        if ((cv_equal(subject_13, cv_text("<<")) or cv_equal(subject_13, cv_text(">>")))):
            cv_field(v_syn, "shift_type", cv_getkey(cv_getkey(v_st, "value"), "type"))
        cce_int_op(v_self, v_syn, v_tc)
    v_tres = cce_talloc(v_self)
    cce_save_val(v_self, v_tres, v_tc, 0)
    let pieces_14: i64 = cv_list()
    cv_push(pieces_14, cv_text("mov rax, qword ptr [rbp"))
    cv_push(pieces_14, cv_format(cce_toff(v_self, v_taddr), "+d"))
    cv_push(pieces_14, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_14))
    cce_e(v_self, cv_text("mov rdi, rax"))
    cce_reload_tmp(v_self, v_tres, v_tc)
    if cv_truth(cc_is_float(v_tc)):
        cce_fconv(v_self, v_tc, v_tt)
    else:
        if cv_truth(cc_is_int(v_tt)):
            cce_check_int_conversion(v_self, v_tc, v_tt)
    cce_store_at_mem(v_self, v_tt, cv_text("rdi"), 0)
    return 0

unsafe fn cce_st_expr(v_self: i64, v_st: i64) -> i64:
    let v_e: i64 = 0
    v_e = cv_getkey(v_st, "expr")
    if (cv_classes(v_e, "Call") and (cv_equal(cv_getkey(v_e, "name"), cv_text("print")))):
        cce_emit_print(v_self, cv_getkey(v_e, "args"), cv_getkey(v_e, "line"))
        return 0
    cce_expr_value(v_self, v_e, 0)
    let owner: i64 = cv_getkey(v_e, "owner_transfer")
    if owner != 0: cce_drop_owner(v_self, owner)
    return 0

unsafe fn cce_emit_print(v_self: i64, v_args: i64, v_line: i64) -> i64:
    let v_n: i64 = 0
    let v_i: i64 = 0
    let v_a: i64 = 0
    let v_t: i64 = 0
    v_n = cv_length(v_args)
    let seq_2: i64 = cv_enumerate(v_args)
    for index_1 in 0..cv_len(seq_2):
        let unpack_3: i64 = cv_at(seq_2, index_1)
        v_i = cv_at(unpack_3, 0)
        v_a = cv_at(unpack_3, 1)
        v_t = cce_expr_value(v_self, v_a, 0)
        if (cv_truth(cc_is_string(v_t)) or (cv_truth(cc_is_ptr(v_t)) and cv_classes(cv_getkey(v_t, "elem"), "TInt") and (cv_equal(cv_getkey(cv_getkey(v_t, "elem"), "bits"), 67)))):
            cce_e(v_self, cv_text("mov rdi, rax"))
            cce_e(v_self, cv_text("call VOLT_f_io_put_str"))
        else:
            if cv_truth(cc_is_bool(v_t)):
                cce_e(v_self, cv_text("mov rdi, rax"))
                cce_e(v_self, cv_text("call VOLT_f_io_put_bool"))
            else:
                if cv_truth(cc_is_float(v_t)):
                    if (cv_equal(cv_getkey(v_t, "bits"), 259)):
                        cce_e(v_self, cv_text("cvtss2sd xmm0, xmm0"))
                    cce_e(v_self, cv_text("call VOLT_f_io_put_float"))
                else:
                    if (cv_truth(cc_is_int(v_t)) and (cv_equal(cv_getkey(v_t, "alias"), cv_text("char")))):
                        cce_e(v_self, cv_text("mov rdi, rax"))
                        cce_e(v_self, cv_text("call VOLT_f_io_put_char"))
                    else:
                        if (cv_truth(cc_is_int(v_t)) and not (cv_truth(cv_getkey(v_t, "signed")))):
                            cce_e(v_self, cv_text("mov rdi, rax"))
                            cce_e(v_self, cv_text("call VOLT_f_io_put_uint"))
                        else:
                            cce_e(v_self, cv_text("mov rdi, rax"))
                            cce_e(v_self, cv_text("call VOLT_f_io_put_int"))
        if (cv_less(v_i, cv_sub(v_n, 11))):
            cce_e(v_self, cv_text("mov edi, 32"))
            cce_e(v_self, cv_text("call VOLT_f_io_put_char"))
    cce_e(v_self, cv_text("mov edi, 10"))
    cce_e(v_self, cv_text("call VOLT_f_io_put_char"))
    cv_field(v_self, "nt", cv_getkey(v_self, "for_floor"))
    return 0

unsafe fn cce_st_if(v_self: i64, v_st: i64) -> i64:
    let v_lend: i64 = 0
    let v_k: i64 = 0
    let v_cond: i64 = 0
    let v_body: i64 = 0
    let v_lnext: i64 = 0
    v_lend = cce_lbl(v_self)
    let seq_2: i64 = cv_enumerate(cv_getkey(v_st, "conds"))
    for index_1 in 0..cv_len(seq_2):
        let unpack_3: i64 = cv_at(seq_2, index_1)
        v_k = cv_at(unpack_3, 0)
        let unpack_4: i64 = cv_at(unpack_3, 1)
        v_cond = cv_at(unpack_4, 0)
        v_body = cv_at(unpack_4, 1)
        v_lnext = cce_lbl(v_self)
        cce_expr_truthy(v_self, v_cond)
        cce_e(v_self, cv_text("test rax, rax"))
        cce_e(v_self, cv_cat(cv_text("jz "), cv_format(v_lnext, "")))
        cce_emit_stmts(v_self, v_body)
        cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_lend, "")))
        cce_label(v_self, v_lnext, 0)
    if cv_truth(cv_getkey(v_st, "els")):
        cce_emit_stmts(v_self, cv_getkey(v_st, "els"))
    cce_label(v_self, v_lend, 0)
    return 0

unsafe fn cce_st_while(v_self: i64, v_st: i64) -> i64:
    let v_lhead: i64 = 0
    let v_lend: i64 = 0
    v_lhead = cce_lbl(v_self)
    v_lend = cce_lbl(v_self)
    cce_label(v_self, v_lhead, 0)
    cce_expr_truthy(v_self, cv_getkey(v_st, "cond"))
    cce_e(v_self, cv_text("test rax, rax"))
    cce_e(v_self, cv_cat(cv_text("jz "), cv_format(v_lend, "")))
    cv_push(cv_getkey(v_self, "loop"), cv_pair(v_lend, v_lhead))
    cce_emit_stmts(v_self, cv_getkey(v_st, "body"))
    cv_pop(cv_getkey(v_self, "loop"))
    cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_lhead, "")))
    cce_label(v_self, v_lend, 0)
    return 0

unsafe fn cce_st_for(v_self: i64, v_st: i64) -> i64:
    let v_d: i64 = 0
    let v_i_slot: i64 = 0
    let v_tstart: i64 = 0
    let v_tstop: i64 = 0
    let v_linc: i64 = 0
    let v_lhead: i64 = 0
    let v_lend: i64 = 0
    let v_old_floor: i64 = 0
    v_d = cv_getkey(v_self, "for_floor")
    v_i_slot = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_st, "var_slot"))
    v_tstart = cce_talloc(v_self)
    v_tstop = cce_talloc(v_self)
    cce_expr_value(v_self, cv_getkey(v_st, "start"), 0)
    cce_assign_conv(v_self, cv_getkey(cv_getkey(v_st, "start"), "type"), cc_int(CV_TRUE, 515))
    let pieces_1: i64 = cv_list()
    cv_push(pieces_1, cv_text("mov qword ptr [rbp"))
    cv_push(pieces_1, cv_format(cce_toff(v_self, v_tstart), "+d"))
    cv_push(pieces_1, cv_text("], rax"))
    cce_e(v_self, cv_join(cv_text(""), pieces_1))
    cce_expr_value(v_self, cv_getkey(v_st, "stop"), 0)
    cce_assign_conv(v_self, cv_getkey(cv_getkey(v_st, "stop"), "type"), cc_int(CV_TRUE, 515))
    let pieces_2: i64 = cv_list()
    cv_push(pieces_2, cv_text("mov qword ptr [rbp"))
    cv_push(pieces_2, cv_format(cce_toff(v_self, v_tstop), "+d"))
    cv_push(pieces_2, cv_text("], rax"))
    cce_e(v_self, cv_join(cv_text(""), pieces_2))
    v_linc = cce_lbl(v_self)
    v_lhead = cce_lbl(v_self)
    v_lend = cce_lbl(v_self)
    cce_load_from_slot(v_self, cce_toff(v_self, v_tstart), cc_int(CV_TRUE, 515))
    cce_store_scalar(v_self, cce_soff(v_self, v_i_slot), cc_int(CV_TRUE, 515), cv_text("int"))
    cce_label(v_self, v_lhead, 0)
    cce_load_from_slot(v_self, cce_soff(v_self, v_i_slot), cc_int(CV_TRUE, 515))
    let pieces_3: i64 = cv_list()
    cv_push(pieces_3, cv_text("mov rcx, qword ptr [rbp"))
    cv_push(pieces_3, cv_format(cce_toff(v_self, v_tstop), "+d"))
    cv_push(pieces_3, cv_text("]"))
    cce_e(v_self, cv_join(cv_text(""), pieces_3))
    cce_e(v_self, cv_text("cmp rax, rcx"))
    let choice_4: i64 = 0
    if cv_truth(cv_getkey(v_st, "inclusive")):
        choice_4 = cv_text("jg ")
    else:
        choice_4 = cv_text("jge ")
    cce_e(v_self, cv_add(choice_4, v_lend))
    v_old_floor = cv_getkey(v_self, "for_floor")
    cv_field(v_self, "for_floor", cv_add(v_d, 19))
    cv_push(cv_getkey(v_self, "loop"), cv_pair(v_lend, v_linc))
    cce_emit_stmts(v_self, cv_getkey(v_st, "body"))
    cv_pop(cv_getkey(v_self, "loop"))
    cv_field(v_self, "for_floor", v_old_floor)
    cce_label(v_self, v_linc, 0)
    cce_load_from_slot(v_self, cce_soff(v_self, v_i_slot), cc_int(CV_TRUE, 515))
    if cv_truth(cv_getkey(v_st, "inclusive")):
        let pieces_5: i64 = cv_list()
        cv_push(pieces_5, cv_text("cmp rax, qword ptr [rbp"))
        cv_push(pieces_5, cv_format(cce_toff(v_self, v_tstop), "+d"))
        cv_push(pieces_5, cv_text("]"))
        cce_e(v_self, cv_join(cv_text(""), pieces_5))
        cce_e(v_self, cv_cat(cv_text("jge "), cv_format(v_lend, "")))
    cce_e(v_self, cv_text("add rax, 1"))
    cce_trap_on(v_self, cv_text("o"), cv_text("volt: integer overflow\n"))
    cce_store_scalar(v_self, cce_soff(v_self, v_i_slot), cc_int(CV_TRUE, 515), cv_text("int"))
    cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(v_lhead, "")))
    cce_label(v_self, v_lend, 0)
    return 0

unsafe fn cce_st_return(v_self: i64, v_st: i64) -> i64:
    let v_ret_type: i64 = 0
    let v_size: i64 = 0
    let v_snapshot: i64 = 0
    let v_snapshot_off: i64 = 0
    let v_sret: i64 = 0
    let v_t: i64 = 0
    v_ret_type = cv_getkey(cv_getkey(v_self, "cur"), "ret_type")
    if (not (cv_getkey(v_st, "value") == 0)):
        if cce_abi_has_sret(v_ret_type):
            v_size = cc_type_size(v_ret_type)
            v_snapshot = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(cv_getkey(v_self, "cur"), "ret_snapshot_slot"))
            v_snapshot_off = cce_soff(v_self, v_snapshot)
            if (cv_truth(cc_is_struct(v_ret_type)) and cv_classes(cv_getkey(v_st, "value"), "Call") and (cv_equal(cv_get(cv_getkey(v_st, "value"), cv_text("kindt"), 0), cv_text("ctor")))):
                cce_emit_ctor(v_self, cv_getkey(v_st, "value"), v_snapshot_off)
            else:
                if cc_is_sum_ctor(cv_getkey(v_st, "value")):
                    cce_emit_sum_ctor(v_self, cv_getkey(v_st, "value"), v_snapshot_off)
                else:
                    if cv_truth(cc_is_struct(v_ret_type)):
                        cce_eaddr(v_self, cv_getkey(v_st, "value"))
                        cce_e(v_self, cv_text("mov rsi, rax"))
                        let pieces_1: i64 = cv_list()
                        cv_push(pieces_1, cv_text("lea rdi, [rbp"))
                        cv_push(pieces_1, cv_format(v_snapshot_off, "+d"))
                        cv_push(pieces_1, cv_text("]"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_1))
                        cce_copy_bytes(v_self, v_size)
                    else:
                        cce_expr_value(v_self, cv_getkey(v_st, "value"), 0)
                        cce_e(v_self, cv_text("mov rsi, rax"))
                        let pieces_2: i64 = cv_list()
                        cv_push(pieces_2, cv_text("lea rdi, [rbp"))
                        cv_push(pieces_2, cv_format(v_snapshot_off, "+d"))
                        cv_push(pieces_2, cv_text("]"))
                        cce_e(v_self, cv_join(cv_text(""), pieces_2))
                        cce_copy_bytes(v_self, v_size)
            cce_owner_flag(v_self, cv_getkey(cv_getkey(v_st, "value"), "owner_transfer"), 0)
            cce_emit_cleanup_scopes(v_self, cv_getkey(v_st, "cleanup_scopes"))
            v_sret = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(cv_getkey(v_self, "cur"), "sret_slot"))
            let pieces_3: i64 = cv_list()
            cv_push(pieces_3, cv_text("mov rdi, qword ptr [rbp"))
            cv_push(pieces_3, cv_format(cce_soff(v_self, v_sret), "+d"))
            cv_push(pieces_3, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_3))
            let pieces_4: i64 = cv_list()
            cv_push(pieces_4, cv_text("lea rsi, [rbp"))
            cv_push(pieces_4, cv_format(cce_soff(v_self, v_snapshot), "+d"))
            cv_push(pieces_4, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_4))
            cce_copy_bytes(v_self, v_size)
            cv_field(v_self, "nt", cv_getkey(v_self, "for_floor"))
        elif cv_classes(v_ret_type, "TSlice"):
            cce_eaddr(v_self, cv_getkey(v_st, "value"))
            cce_e(v_self, cv_text("sub rsp, 16"))
            cce_e(v_self, cv_text("mov rdx, qword ptr [rax+8]"))
            cce_e(v_self, cv_text("mov rax, qword ptr [rax]"))
            cce_e(v_self, cv_text("mov qword ptr [rsp], rax"))
            cce_e(v_self, cv_text("mov qword ptr [rsp+8], rdx"))
            cce_emit_cleanup_scopes(v_self, cv_getkey(v_st, "cleanup_scopes"))
            cce_e(v_self, cv_text("mov rax, qword ptr [rsp]"))
            cce_e(v_self, cv_text("mov rdx, qword ptr [rsp+8]"))
            cce_e(v_self, cv_text("add rsp, 16"))
        else:
            v_t = cce_expr_value(v_self, cv_getkey(v_st, "value"), 0)
            cce_assign_conv(v_self, v_t, v_ret_type)
            cce_e(v_self, cv_text("sub rsp, 16"))
            if cv_truth(cc_is_float(v_ret_type)):
                cce_e(v_self, cv_text("movsd qword ptr [rsp], xmm0"))
            else:
                cce_e(v_self, cv_text("mov qword ptr [rsp], rax"))
            cce_emit_cleanup_scopes(v_self, cv_getkey(v_st, "cleanup_scopes"))
            if cv_truth(cc_is_float(v_ret_type)):
                cce_e(v_self, cv_text("movsd xmm0, qword ptr [rsp]"))
            else:
                cce_e(v_self, cv_text("mov rax, qword ptr [rsp]"))
            cce_e(v_self, cv_text("add rsp, 16"))
    else:
        cce_emit_cleanup_scopes(v_self, cv_getkey(v_st, "cleanup_scopes"))
    cce_e(v_self, cv_cat(cv_text("jmp "), cv_format(cv_getkey(v_self, "ret_l"), "")))
    return 0

unsafe fn cce_emit_fn(v_self: i64, v_fn: i64, v_name_override: i64) -> i64:
    let v_ret_type: i64 = 0
    let v_label: i64 = 0
    let v_frame_idx: i64 = 0
    let v_raw: i64 = 0
    let v_spills: i64 = 0
    let v_sret: i64 = 0
    let v_i: i64 = 0
    let v_pn: i64 = 0
    let v_pt: i64 = 0
    let v_s: i64 = 0
    let v_so: i64 = 0
    let v_sp: i64 = 0
    let v_sz: i64 = 0
    let v_Lc: i64 = 0
    let v_frame: i64 = 0
    cv_field(v_self, "cur", v_fn)
    cv_field(v_self, "cur_name", cv_getkey(v_fn, "name"))
    let items_1: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "slots", cv_get(v_fn, cv_text("slots"), items_1))
    let collect_2: i64 = cv_vector(CV_LIST)
    let seq_4: i64 = cv_getkey(v_self, "slots")
    for index_3 in 0..cv_len(seq_4):
        let s_5: i64 = cv_at(seq_4, index_3)
        cv_push(collect_2, cv_getkey(s_5, "off"))
    cv_field(v_self, "lsize", cc_base_align(cv_maximum(collect_2, 3), 131))
    if (cv_less(cv_sub(17179869179, 387), cv_getkey(v_self, "lsize"))):
        cc_error(cv_text("размер кадра стека превышает лимит x86-64"), cv_getkey(v_fn, "file"), cv_getkey(v_fn, "line"))
        return 0
    let choice_6: i64 = cv_get(v_fn, cv_text("ret_type"), 0)
    if not cv_truth(choice_6):
        choice_6 = cv_getkey(v_fn, "sig_ret")
    v_ret_type = choice_6
    cv_field(v_fn, "em_ret", v_ret_type)
    let choice_7: i64 = v_name_override
    if not cv_truth(choice_7):
        choice_7 = cc_function_label(cv_getkey(v_fn, "name"), cv_getkey(v_fn, "file"))
    v_label = choice_7
    cv_field(v_self, "ret_l", cce_lbl(v_self))
    cv_field(v_self, "nt", 3)
    cv_field(v_self, "ntpeak", 3)
    cv_push(cv_getkey(v_self, "text"), cv_cat(cv_text(".globl "), cv_format(v_label, "")))
    cce_label(v_self, v_label, 0)
    cce_e(v_self, cv_text("push rbp"))
    cce_e(v_self, cv_text("mov rbp, rsp"))
    v_frame_idx = cv_length(cv_getkey(v_self, "text"))
    cce_e(v_self, cv_cat(cv_text("sub rsp, "), cv_format(cv_add(cv_getkey(v_self, "lsize"), cv_mul(131, cc_k_temp_slots)), "")))
    if (not (cv_getkey(v_fn, "native") == 0)):
        let seq_9: i64 = cv_getkey(v_fn, "body")
        for index_8 in 0..cv_len(seq_9):
            v_raw = cv_at(seq_9, index_8)
            cce_e(v_self, v_raw)
    else:
        let placement: CCEAbiCursor = cce_abi_start(v_ret_type)
        let items_10: i64 = cv_vector(CV_LIST)
        v_spills = items_10
        if cce_abi_has_sret(v_ret_type):
            v_sret = cv_subscript(cv_getkey(v_self, "slots"), cv_getkey(v_fn, "sret_slot"))
            cce_e(v_self, cv_mod(cv_text("mov qword ptr [rbp%+d], rdi"), cce_soff(v_self, v_sret)))
        let seq_13: i64 = cv_enumerate(cv_getkey(v_fn, "sig_params"))
        for index_12 in 0..cv_len(seq_13):
            let unpack_14: i64 = cv_at(seq_13, index_12)
            v_i = cv_at(unpack_14, 0)
            let unpack_15: i64 = cv_at(unpack_14, 1)
            v_pn = cv_at(unpack_15, 0)
            v_pt = cv_at(unpack_15, 1)
            if ((cv_le(cv_length(cv_getkey(v_self, "slots")), v_i)) or (not (cv_equal(cv_getkey(cv_subscript(cv_getkey(v_fn, "slots"), v_i), "kind"), cv_text("param"))))):
                let pieces_16: i64 = cv_list()
                cv_push(pieces_16, cv_text("параметр "))
                cv_push(pieces_16, cv_format(v_pn, ""))
                cv_push(pieces_16, cv_text(": нет слота"))
                cc_error(cv_join(cv_text(""), pieces_16), cv_getkey(v_fn, "file"), cv_getkey(v_fn, "line"))
                return 0
            v_s = cv_subscript(cv_getkey(v_fn, "slots"), v_i)
            v_so = cce_soff(v_self, v_s)
            let place: CCEAbiLocation = cce_abi_next(&placement, v_pt)
            if cce_abi_has_sret(v_pt):
                v_sp = cce_talloc(v_self)
                cce_abi_in(v_self, v_pt, place, cv_index(cce_toff(v_self, v_sp)))
                let items_18: i64 = cv_vector(CV_TUPLE)
                cv_push(items_18, v_sp)
                cv_push(items_18, v_so)
                cv_push(items_18, cc_type_size(v_pt))
                cv_push(v_spills, items_18)
            else:
                cce_abi_in(v_self, v_pt, place, cv_index(v_so))
        # Copy aggregates only after all incoming argument registers have been saved.
        let seq_26: i64 = v_spills
        for index_25 in 0..cv_len(seq_26):
            let unpack_27: i64 = cv_at(seq_26, index_25)
            v_sp = cv_at(unpack_27, 0)
            v_so = cv_at(unpack_27, 1)
            v_sz = cv_at(unpack_27, 2)
            let pieces_28: i64 = cv_list()
            cv_push(pieces_28, cv_text("mov rsi, qword ptr [rbp"))
            cv_push(pieces_28, cv_format(cce_toff(v_self, v_sp), "+d"))
            cv_push(pieces_28, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_28))
            let pieces_29: i64 = cv_list()
            cv_push(pieces_29, cv_text("lea rdi, [rbp"))
            cv_push(pieces_29, cv_format(v_so, "+d"))
            cv_push(pieces_29, cv_text("]"))
            cce_e(v_self, cv_join(cv_text(""), pieces_29))
            cce_e(v_self, cv_cat(cv_text("mov ecx, "), cv_format(v_sz, "")))
            cce_e(v_self, cv_text("cld"))
            v_Lc = cce_lbl(v_self)
            cce_label(v_self, v_Lc, 0)
            cce_e(v_self, cv_text("mov al, byte ptr [rsi]"))
            cce_e(v_self, cv_text("mov byte ptr [rdi], al"))
            cce_e(v_self, cv_text("inc rsi"))
            cce_e(v_self, cv_text("inc rdi"))
            cce_e(v_self, cv_text("dec rcx"))
            cce_e(v_self, cv_cat(cv_text("jnz "), cv_format(v_Lc, "")))
        cv_field(v_self, "nt", 3)
        cce_emit_stmts(v_self, cv_getkey(v_fn, "body"))
    v_frame = cc_base_align(cv_add(cv_add(259, cv_getkey(v_self, "lsize")), cv_mul(131, cv_max(cv_getkey(v_self, "ntpeak"), 11))), 131)
    if (cv_less(17179869179, v_frame)):
        cc_error(cv_text("размер кадра стека превышает лимит x86-64"), cv_getkey(v_fn, "file"), cv_getkey(v_fn, "line"))
        return 0
    cv_set(cv_getkey(v_self, "text"), v_frame_idx, cv_cat(cv_text("    sub rsp, "), cv_format(v_frame, "")))
    cce_label(v_self, cv_getkey(v_self, "ret_l"), 0)
    cce_e(v_self, cv_text("mov rsp, rbp"))
    cce_e(v_self, cv_text("pop rbp"))
    cce_e(v_self, cv_text("ret"))
    return 0

unsafe fn cce_emit_globals(v_self: i64) -> i64:
    let v_g: i64 = 0
    let v_lbl: i64 = 0
    let v_t: i64 = 0
    let v_cv: i64 = 0
    let v_nm: i64 = 0
    let v_b: i64 = 0
    let v_bits: i64 = 0
    let v_sz: i64 = 0
    let v_spec: i64 = 0
    let seq_2: i64 = cv_getkey(cv_getkey(v_self, "sem"), "global_order")
    for index_1 in 0..cv_len(seq_2):
        v_g = cv_at(seq_2, index_1)
        v_lbl = cc_global_label(cv_getkey(v_g, "name"), cv_getkey(v_g, "file"))
        v_t = cv_getkey(v_g, "glob_type")
        v_cv = cv_get(v_g, cv_text("const_val"), 0)
        if cv_classes(v_cv, "str"):
            v_nm = cce_slconst(v_self, v_cv)
            let pieces_3: i64 = cv_list()
            cv_push(pieces_3, cv_format(v_lbl, ""))
            cv_push(pieces_3, cv_text(": .quad "))
            cv_push(pieces_3, cv_format(v_nm, ""))
            cv_push(cv_getkey(v_self, "data"), cv_join(cv_text(""), pieces_3))
            continue
        if cv_truth(cc_is_bool(v_t)):
            let choice_4: i64 = 0
            if cv_truth(v_cv):
                choice_4 = 11
            else:
                choice_4 = 3
            v_b = choice_4
            let pieces_5: i64 = cv_list()
            cv_push(pieces_5, cv_format(v_lbl, ""))
            cv_push(pieces_5, cv_text(": .byte "))
            cv_push(pieces_5, cv_format(v_b, ""))
            cv_push(cv_getkey(v_self, "data"), cv_join(cv_text(""), pieces_5))
            continue
        if cv_truth(cc_is_float(v_t)):
            if (cv_equal(cv_getkey(v_t, "bits"), 259)):
                let choice_6: i64 = v_cv
                if not cv_truth(choice_6):
                    choice_6 = cv_real(0.0)
                v_bits = cv_subscript(cv_single(cv_u(cv_fbits32(cv_real_value(cv_f(choice_6)) as f32))), 3)
                let pieces_7: i64 = cv_list()
                cv_push(pieces_7, cv_format(v_lbl, ""))
                cv_push(pieces_7, cv_text(": .long 0x"))
                cv_push(pieces_7, cv_format(cv_and(v_bits, 34359738363), "x"))
                cv_push(cv_getkey(v_self, "data"), cv_join(cv_text(""), pieces_7))
            else:
                let choice_8: i64 = v_cv
                if not cv_truth(choice_8):
                    choice_8 = cv_real(0.0)
                v_bits = cv_subscript(cv_single(cv_u(cv_fbits(cv_real_value(cv_f(choice_8))))), 3)
                let pieces_9: i64 = cv_list()
                cv_push(pieces_9, cv_format(v_lbl, ""))
                cv_push(pieces_9, cv_text(": .quad 0x"))
                cv_push(pieces_9, cv_format(v_bits, "x"))
                cv_push(cv_getkey(v_self, "data"), cv_join(cv_text(""), pieces_9))
            continue
        v_sz = cc_type_size(v_t)
        let dict_10: i64 = cv_dict()
        cv_set(dict_10, 11, cv_text(".byte"))
        cv_set(dict_10, 19, cv_text(".word"))
        cv_set(dict_10, 35, cv_text(".long"))
        cv_set(dict_10, 67, cv_text(".quad"))
        v_spec = cv_subscript(dict_10, v_sz)
        if cv_classes(v_cv, "int"):
            v_cv = cv_and(v_cv, cv_sub(cv_shl(11, cv_mul(v_sz, 67)), 11))
            let pieces_11: i64 = cv_list()
            cv_push(pieces_11, cv_format(v_lbl, ""))
            cv_push(pieces_11, cv_text(": "))
            cv_push(pieces_11, cv_format(v_spec, ""))
            cv_push(pieces_11, cv_text(" "))
            cv_push(pieces_11, cv_format(v_cv, ""))
            cv_push(cv_getkey(v_self, "data"), cv_join(cv_text(""), pieces_11))
        else:
            let pieces_12: i64 = cv_list()
            cv_push(pieces_12, cv_format(v_lbl, ""))
            cv_push(pieces_12, cv_text(": .space "))
            cv_push(pieces_12, cv_format(v_sz, ""))
            cv_push(cv_getkey(v_self, "bss"), cv_join(cv_text(""), pieces_12))
    return 0

unsafe fn cce_emit_all(v_self: i64) -> i64:
    let v_prog: i64 = 0
    let v_fn: i64 = 0
    let seq_2: i64 = cv_getkey(cv_getkey(v_self, "sem"), "progs")
    for index_1 in 0..cv_len(seq_2):
        v_prog = cv_at(seq_2, index_1)
        let seq_4: i64 = cv_getkey(v_prog, "fns")
        for index_3 in 0..cv_len(seq_4):
            v_fn = cv_at(seq_4, index_3)
            if ((cv_getkey(v_fn, "body") == 0) and (cv_getkey(v_fn, "native") == 0)):
                continue
            if cv_truth(cv_getkey(v_fn, "type_params")):
                continue
            cce_emit_fn(v_self, v_fn, 0)
    let seq_6: i64 = cv_getkey(cv_getkey(v_self, "sem"), "specializations")
    for index_5 in 0..cv_len(seq_6):
        v_fn = cv_at(seq_6, index_5)
        cce_emit_fn(v_self, v_fn, cc_function_label(cv_getkey(v_fn, "mangled_name"), cv_getkey(v_fn, "file")))
    cce_emit_globals(v_self)
    cce_emit_fn(v_self, cv_getkey(cv_getkey(v_self, "sem"), "main_fn"), cv_text("VOLT_f_main"))
    return 0

unsafe fn cc_esc_str(v_s: i64) -> i64:
    let v_out: i64 = 0
    let v_ch: i64 = 0
    let v_b: i64 = 0
    let v_c: i64 = 0
    let items_1: i64 = cv_vector(CV_LIST)
    v_out = items_1
    let seq_3: i64 = cv_encode(v_s)
    for index_2 in 0..cv_len(seq_3):
        v_ch = cv_at(seq_3, index_2)
        v_b = cv_int(v_ch, 83)
        v_c = cv_chr(v_b)
        if (cv_contains(cv_text("\\\""), v_c)):
            cv_push(v_out, cv_add(cv_text("\\"), v_c))
        else:
            if (cv_le(259, v_b)) and (cv_less(v_b, 1019)):
                cv_push(v_out, v_c)
            else:
                cv_push(v_out, cv_mod(cv_text("\\%03o"), v_b))
    return cv_join(cv_text(""), v_out)
