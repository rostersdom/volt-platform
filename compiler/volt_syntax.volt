# VOLT compiler, native self-hosted implementation.
use volt_lex

unsafe fn cc_TExpr(v_kind: i64, v_a: i64, v_line: i64, v_file: i64) -> i64:
    let v_self: i64 = cv_node("TExpr")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "kind", v_kind)
    cv_field(v_self, "a", v_a)
    cv_field(v_self, "file", v_file)
    return v_self

unsafe fn cc_Program(v_file: i64) -> i64:
    let v_self: i64 = cv_node("Program")
    cv_field(v_self, "line", 11)
    cv_field(v_self, "file", v_file)
    let items_1: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "uses", items_1)
    let items_2: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "structs", items_2)
    let items_3: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "enums", items_3)
    let items_4: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "fns", items_4)
    let items_5: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "globals", items_5)
    let items_6: i64 = cv_vector(CV_LIST)
    cv_field(v_self, "main", items_6)
    return v_self

unsafe fn cc_StructDef(v_file: i64, v_name: i64, v_fields: i64, v_line: i64, v_type_params: i64) -> i64:
    let v_self: i64 = cv_node("StructDef")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "file", v_file)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "fields", v_fields)
    cv_field(v_self, "type_params", cv_astuple(v_type_params))
    return v_self

unsafe fn cc_EnumDef(v_file: i64, v_name: i64, v_variants: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("EnumDef")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "file", v_file)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "variants", v_variants)
    return v_self

unsafe fn cc_FnDef(v_file: i64, v_name: i64, v_params: i64, v_ret: i64, v_body: i64, v_packed: i64) -> i64:
    let v_native: i64 = cv_at(v_packed, 0)
    let v_line: i64 = cv_at(v_packed, 1)
    let v_is_unsafe: i64 = cv_at(v_packed, 2)
    let v_type_params: i64 = cv_at(v_packed, 3)
    let v_self: i64 = cv_node("FnDef")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "file", v_file)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "params", v_params)
    cv_field(v_self, "ret", v_ret)
    cv_field(v_self, "body", v_body)
    cv_field(v_self, "native", v_native)
    let choice_1: i64 = v_is_unsafe
    if not cv_truth(choice_1):
        choice_1 = cv_bool((not (v_native == 0)))
    cv_field(v_self, "is_unsafe", choice_1)
    let choice_2: i64 = v_type_params
    if not cv_truth(choice_2):
        let items_3: i64 = cv_vector(CV_TUPLE)
        choice_2 = items_3
    cv_field(v_self, "type_params", cv_astuple(choice_2))
    return v_self

unsafe fn cc_GlobalVar(v_file: i64, v_name: i64, v_typ: i64, v_init: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("GlobalVar")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "file", v_file)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "typ", v_typ)
    cv_field(v_self, "init", v_init)
    return v_self

unsafe fn cc_LetStmt(v_name: i64, v_typ: i64, v_init: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("LetStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "typ", v_typ)
    cv_field(v_self, "init", v_init)
    cv_field(v_self, "slot", 0)
    cv_field(v_self, "slot_type", 0)
    cv_field(v_self, "has_cls", CV_FALSE)
    return v_self

unsafe fn cc_ConstStmt(v_name: i64, v_typ: i64, v_init: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("ConstStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "typ", v_typ)
    cv_field(v_self, "init", v_init)
    return v_self

unsafe fn cc_DeferStmt(v_action: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("DeferStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "action", v_action)
    return v_self

unsafe fn cc_AssignStmt(v_target: i64, v_op: i64, v_value: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("AssignStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "target", v_target)
    cv_field(v_self, "op", v_op)
    cv_field(v_self, "value", v_value)
    return v_self

unsafe fn cc_ExprStmt(v_expr: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("ExprStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "expr", v_expr)
    return v_self

unsafe fn cc_IfStmt(v_conds: i64, v_els: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("IfStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "conds", v_conds)
    cv_field(v_self, "els", v_els)
    return v_self

unsafe fn cc_WhileStmt(v_cond: i64, v_body: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("WhileStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "cond", v_cond)
    cv_field(v_self, "body", v_body)
    return v_self

unsafe fn cc_ForStmt(v_var: i64, v_start: i64, v_stop: i64, v_body: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("ForStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "var", v_var)
    cv_field(v_self, "start", v_start)
    cv_field(v_self, "stop", v_stop)
    cv_field(v_self, "body", v_body)
    return v_self

unsafe fn cc_BreakStmt(v_line: i64) -> i64:
    let v_self: i64 = cv_node("BreakStmt")
    cv_field(v_self, "line", v_line)
    return v_self

unsafe fn cc_ContinueStmt(v_line: i64) -> i64:
    let v_self: i64 = cv_node("ContinueStmt")
    cv_field(v_self, "line", v_line)
    return v_self

unsafe fn cc_ReturnStmt(v_value: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("ReturnStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "value", v_value)
    return v_self

unsafe fn cc_UnsafeStmt(v_body: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("UnsafeStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "body", v_body)
    return v_self

unsafe fn cc_NativeStmt(v_lines: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("NativeStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "lines", v_lines)
    return v_self

unsafe fn cc_MatchStmt(v_value: i64, v_arms: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("MatchStmt")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "value", v_value)
    cv_field(v_self, "arms", v_arms)
    return v_self

unsafe fn cc_MatchArm(v_pattern: i64, v_binding: i64, v_body: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("MatchArm")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "pattern", v_pattern)
    cv_field(v_self, "binding", v_binding)
    cv_field(v_self, "body", v_body)
    return v_self

unsafe fn cc_SizeAlignExpr(v_op: i64, v_typ: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("SizeAlignExpr")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "op", v_op)
    cv_field(v_self, "texpr", v_typ)
    return v_self

unsafe fn cc_IntLit(v_val: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("IntLit")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "val", v_val)
    return v_self

unsafe fn cc_FloatLit(v_val: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("FloatLit")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "val", v_val)
    return v_self

unsafe fn cc_StrLit(v_val: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("StrLit")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "val", v_val)
    return v_self

unsafe fn cc_CharLit(v_val: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("CharLit")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "val", v_val)
    return v_self

unsafe fn cc_BoolLit(v_val: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("BoolLit")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "val", v_val)
    return v_self

unsafe fn cc_VarRef(v_name: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("VarRef")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "name", v_name)
    return v_self

unsafe fn cc_Unary(v_op: i64, v_x: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("Unary")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "op", v_op)
    cv_field(v_self, "x", v_x)
    return v_self

unsafe fn cc_Binary(v_op: i64, v_l: i64, v_r: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("Binary")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "op", v_op)
    cv_field(v_self, "l", v_l)
    cv_field(v_self, "r", v_r)
    return v_self

unsafe fn cc_Call(v_name: i64, v_args: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("Call")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "args", v_args)
    return v_self

unsafe fn cc_Index(v_base: i64, v_idx: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("Index")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "base", v_base)
    cv_field(v_self, "idx", v_idx)
    return v_self

unsafe fn cc_SliceExpr(v_base: i64, v_start: i64, v_end: i64, v_mutable: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("SliceExpr")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "base", v_base)
    cv_field(v_self, "start", v_start)
    cv_field(v_self, "end", v_end)
    cv_field(v_self, "mutable", v_mutable)
    return v_self

unsafe fn cc_Member(v_base: i64, v_field: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("Member")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "base", v_base)
    cv_field(v_self, "field", v_field)
    return v_self

unsafe fn cc_Cast(v_x: i64, v_texpr: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("Cast")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "x", v_x)
    cv_field(v_self, "texpr", v_texpr)
    return v_self

unsafe fn cc_Deref(v_x: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("Deref")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "x", v_x)
    return v_self

unsafe fn cc_AddrOf(v_x: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("AddrOf")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "x", v_x)
    return v_self

unsafe fn cc_ArrayLit(v_items: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("ArrayLit")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "items", v_items)
    return v_self

unsafe fn cc_StructLit(v_name: i64, v_items: i64, v_line: i64) -> i64:
    let v_self: i64 = cv_node("StructLit")
    cv_field(v_self, "line", v_line)
    cv_field(v_self, "name", v_name)
    cv_field(v_self, "items", v_items)
    return v_self

unsafe fn ccp_new(v_src: i64, v_file: i64) -> i64:
    let v_self: i64 = cv_node("Parser")
    cv_field(v_self, "file", v_file)
    cv_field(v_self, "toks", cc_lex(v_src, v_file))
    cv_field(v_self, "i", 3)
    cv_field(v_self, "depth", 3)
    cv_field(v_self, "expr_depth", 3)
    return v_self

unsafe fn ccp_peek(v_self: i64) -> i64:
    let v_j: i64 = 0
    v_j = cv_getkey(v_self, "i")
    if (cv_less(3, cv_getkey(v_self, "depth"))):
        while ((cv_less(v_j, cv_length(cv_getkey(v_self, "toks")))) and (cv_equal(cv_subscript(cv_subscript(cv_getkey(v_self, "toks"), v_j), cv_text("k")), cv_text("nl")))):
            v_j = cv_add(v_j, 11)
    if (cv_le(cv_length(cv_getkey(v_self, "toks")), v_j)):
        let dict_1: i64 = cv_dict()
        cv_set(dict_1, cv_text("k"), cv_text("eof"))
        cv_set(dict_1, cv_text("t"), cv_text(""))
        let choice_2: i64 = 0
        if cv_truth(cv_getkey(v_self, "toks")):
            choice_2 = cv_subscript(cv_subscript(cv_getkey(v_self, "toks"), cv_neg(11)), cv_text("line"))
        else:
            choice_2 = 11
        cv_set(dict_1, cv_text("line"), choice_2)
        cv_set(dict_1, cv_text("ind"), cv_neg(11))
        return dict_1
    return cv_subscript(cv_getkey(v_self, "toks"), v_j)

unsafe fn ccp_at(v_self: i64, v_kw: i64) -> i64:
    let choice_1: i64 = cv_bool((cv_equal(cv_subscript(ccp_peek(v_self), cv_text("k")), cv_text("kw"))))
    if cv_truth(choice_1):
        choice_1 = cv_bool((cv_equal(cv_subscript(ccp_peek(v_self), cv_text("t")), v_kw)))
    return choice_1

unsafe fn ccp_atp(v_self: i64, v_p: i64) -> i64:
    let choice_1: i64 = cv_bool((cv_equal(cv_subscript(ccp_peek(v_self), cv_text("k")), cv_text("punct"))))
    if cv_truth(choice_1):
        choice_1 = cv_bool((cv_equal(cv_subscript(ccp_peek(v_self), cv_text("t")), v_p)))
    return choice_1

unsafe fn ccp_next(v_self: i64) -> i64:
    let v_t: i64 = 0
    if (cv_less(3, cv_getkey(v_self, "depth"))):
        while ((cv_less(cv_getkey(v_self, "i"), cv_length(cv_getkey(v_self, "toks")))) and (cv_equal(cv_subscript(cv_subscript(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i")), cv_text("k")), cv_text("nl")))):
            cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
    if (cv_le(cv_length(cv_getkey(v_self, "toks")), cv_getkey(v_self, "i"))):
        let dict_1: i64 = cv_dict()
        cv_set(dict_1, cv_text("k"), cv_text("eof"))
        cv_set(dict_1, cv_text("t"), cv_text(""))
        let choice_2: i64 = 0
        if cv_truth(cv_getkey(v_self, "toks")):
            choice_2 = cv_subscript(cv_subscript(cv_getkey(v_self, "toks"), cv_neg(11)), cv_text("line"))
        else:
            choice_2 = 11
        cv_set(dict_1, cv_text("line"), choice_2)
        cv_set(dict_1, cv_text("ind"), cv_neg(11))
        return dict_1
    v_t = cv_subscript(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i"))
    cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
    return v_t

# Parser diagnostic with the token's 1-based byte column when the lexer
# recorded one (indent == token start); falls back to line-only otherwise.
unsafe fn ccp_error(v_self: i64, v_msg: i64, v_tok: i64):
    let v_column: i64 = 0
    let v_ind: i64 = cv_subscript(v_tok, cv_text("ind"))
    if not cv_less(v_ind, 3): v_column = cv_index(v_ind) + 1
    cc_error_at(v_msg, cv_getkey(v_self, "file"), cv_subscript(v_tok, cv_text("line")), v_column)

unsafe fn ccp_expect(v_self: i64, v_kind: i64, v_txt: i64) -> i64:
    let v_t: i64 = 0
    let v_want: i64 = 0
    v_t = ccp_next(v_self)
    if ((not (cv_equal(cv_subscript(v_t, cv_text("k")), v_kind))) or ((not (v_txt == 0)) and (not (cv_equal(cv_subscript(v_t, cv_text("t")), v_txt))))):
        let choice_1: i64 = 0
        if cv_truth(v_txt):
            choice_1 = v_txt
        else:
            choice_1 = v_kind
        v_want = choice_1
        let pieces_2: i64 = cv_list()
        cv_push(pieces_2, cv_text("ожидалось "))
        cv_push(pieces_2, cv_format(v_want, "r"))
        cv_push(pieces_2, cv_text(", найдено "))
        cv_push(pieces_2, cv_format(cv_subscript(v_t, cv_text("t")), "r"))
        ccp_error(v_self, cv_join(cv_text(""), pieces_2), v_t)
        return 0
    return v_t

unsafe fn ccp_line_end(v_self: i64) -> i64:
    let v_t: i64 = 0
    v_t = ccp_peek(v_self)
    let subject_1: i64 = cv_subscript(v_t, cv_text("k"))
    if (not ((cv_equal(subject_1, cv_text("nl")) or cv_equal(subject_1, cv_text("eof"))))):
        ccp_error(v_self, cv_cat(cv_text("лишний текст после оператора: "), cv_format(cv_subscript(v_t, cv_text("t")), "r")), v_t)
        return 0
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("nl"))):
        cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
    return 0

unsafe fn ccp_parse_program(v_self: i64) -> i64:
    let file: i64 = cv_getkey(v_self, "file")
    let v_prog: i64 = cc_Program(file)
    ccp_skip_nl(v_self)
    if ccp_at_id(v_self, "module") and cv_name(cv_getkey(ccp_peek_next(v_self), "k"), "id"):
        ccp_next(v_self)
        cv_field(v_prog, "module", cv_getkey(ccp_next(v_self), "t"))
        ccp_line_end(v_self)
    while true:
        ccp_skip_nl(v_self)
        if cv_name(cv_getkey(ccp_peek(v_self), "k"), "eof"): break
        let public: bool = ccp_at_id(v_self, "pub") and cv_name(cv_getkey(ccp_peek_next(v_self), "k"), "kw")
        let line: i64 = cv_getkey(ccp_peek(v_self), "line")
        let indent: i64 = cv_getkey(ccp_peek(v_self), "ind")
        if public:
            if cv_getkey(v_prog, "module") == 0: cc_error(cv_text("pub требует заголовок module"), file, line)
            ccp_next(v_self)
        if cv_truth(ccp_at(v_self, cv_text("use"))):
            if public: cc_error(cv_text("pub use не поддерживается"), file, line)
            ccp_next(v_self)
            while true:
                let item: i64 = cv_getkey(ccp_expect(v_self, cv_text("id"), 0), "t")
                let uses: i64 = cv_getkey(v_prog, "uses")
                if cv_truth(ccp_at(v_self, cv_text("as"))):
                    ccp_next(v_self)
                    let aliases: i64 = cv_getkey(v_prog, "use_aliases")
                    if aliases == 0:
                        aliases = cv_dict()
                        cv_field(v_prog, "use_aliases", aliases)
                    cv_set(aliases, cv_length(uses), cv_getkey(ccp_expect(v_self, cv_text("id"), 0), "t"))
                cv_push(uses, item)
                if not cv_truth(ccp_atp(v_self, cv_text(","))): break
                ccp_next(v_self)
            ccp_line_end(v_self)
        elif cv_truth(ccp_at(v_self, cv_text("link"))):
            if public: cc_error(cv_text("pub link не поддерживается"), file, line)
            ccp_next(v_self)
            let t: i64 = ccp_expect(v_self, cv_text("str"), 0)
            cv_push(cv_getkey(v_prog, "uses"), cv_cat(cv_text("__link__:"), cv_getkey(t, "t")))
            ccp_line_end(v_self)
        else:
            let next: i64 = cv_getkey(ccp_peek_next(v_self), "t")
            let c_layout: bool = cv_truth(ccp_at(v_self, cv_text("extern"))) and cv_name(next, "struct")
            let def: i64 = 0
            if c_layout or cv_truth(ccp_at(v_self, cv_text("struct"))):
                if c_layout: ccp_next(v_self)
                def = ccp_parse_struct(v_self)
                if c_layout: cv_field(def, "c_layout", CV_TRUE)
                cv_push(cv_getkey(v_prog, "structs"), def)
            elif cv_truth(ccp_at(v_self, cv_text("enum"))):
                def = ccp_parse_enum(v_self, indent)
                cv_push(cv_getkey(v_prog, "enums"), def)
            elif cv_truth(ccp_at(v_self, cv_text("fn"))) or cv_truth(ccp_at(v_self, cv_text("extern"))) or cv_truth(ccp_at(v_self, cv_text("native"))) or (cv_truth(ccp_at(v_self, cv_text("unsafe"))) and (cv_name(next, "fn") or cv_name(next, "extern") or cv_name(next, "native"))):
                def = ccp_parse_fn(v_self, indent)
                cv_push(cv_getkey(v_prog, "fns"), def)
            else:
                if public and not cv_truth(ccp_at(v_self, cv_text("const"))):
                    cc_error(cv_text("pub допустим для fn, struct, enum и const"), file, line)
                def = ccp_parse_stmt(v_self)
                cv_push(cv_getkey(v_prog, "main"), def)
            if public: cv_field(def, "pub", CV_TRUE)
    return v_prog

unsafe fn ccp_peek_next(parser: i64) -> i64:
    let index: i64 = cv_index(cv_getkey(parser, "i")) + 1
    let tokens: i64 = cv_getkey(parser, "toks")
    if index < cv_len(tokens): return cv_at(tokens, index)
    return 0

unsafe fn ccp_at_id(parser: i64, name: string) -> bool:
    let tok: i64 = ccp_peek(parser)
    return cv_name(cv_getkey(tok, "k"), "id") and cv_name(cv_getkey(tok, "t"), name)

unsafe fn ccp_parse_struct(v_self: i64) -> i64:
    let v_kw: i64 = 0
    let v_name: i64 = 0
    let v_type_params: i64 = 0
    let v_pe: i64 = 0
    let v_base: i64 = 0
    let v_fields: i64 = 0
    let v_t: i64 = 0
    let v_fname: i64 = 0
    let v_ftype: i64 = 0
    v_kw = ccp_next(v_self)
    v_name = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
    v_type_params = ccp_parse_type_params(v_self, 0)
    ccp_expect(v_self, cv_text("punct"), cv_text(":"))
    ccp_line_end(v_self)
    v_pe = ccp_peek(v_self)
    if ((cv_equal(cv_subscript(v_pe, cv_text("k")), cv_text("eof"))) or (cv_equal(cv_subscript(v_pe, cv_text("ind")), 3))):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("struct "))
        cv_push(pieces_1, cv_format(v_name, ""))
        cv_push(pieces_1, cv_text(": ожидается поле с отступом"))
        ccp_error(v_self, cv_join(cv_text(""), pieces_1), v_kw)
        return 0
    v_base = cv_subscript(v_pe, cv_text("ind"))
    let items_2: i64 = cv_vector(CV_LIST)
    v_fields = items_2
    while cv_truth(CV_TRUE):
        v_t = ccp_peek(v_self)
        if ((cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("eof"))) or (cv_less(cv_subscript(v_t, cv_text("ind")), v_base)) or (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("kw")))):
            break
        v_fname = cv_subscript(ccp_next(v_self), cv_text("t"))
        ccp_expect(v_self, cv_text("punct"), cv_text(":"))
        v_ftype = ccp_parse_type(v_self, CV_FALSE, 3)
        ccp_line_end(v_self)
        cv_push(v_fields, cv_pair(v_fname, v_ftype))
    if not (cv_truth(v_fields)):
        let pieces_3: i64 = cv_list()
        cv_push(pieces_3, cv_text("struct "))
        cv_push(pieces_3, cv_format(v_name, ""))
        cv_push(pieces_3, cv_text(": нет полей"))
        ccp_error(v_self, cv_join(cv_text(""), pieces_3), v_kw)
        return 0
    return cc_StructDef(cv_getkey(v_self, "file"), v_name, v_fields, cv_subscript(v_kw, cv_text("line")), v_type_params)

unsafe fn ccp_parse_type_params(v_self: i64, v_eq_params: i64) -> i64:
    let v_params: i64 = 0
    let v_param: i64 = 0
    let items_1: i64 = cv_vector(CV_LIST)
    v_params = items_1
    if cv_truth(ccp_atp(v_self, cv_text("<"))):
        ccp_next(v_self)
        while cv_truth(CV_TRUE):
            v_param = ccp_expect(v_self, cv_text("id"), 0)
            let v_name: i64 = cv_getkey(v_param, "t")
            if cv_contains(v_params, v_name):
                let pieces_2: i64 = cv_list()
                cv_push(pieces_2, cv_text("параметр типа "))
                cv_push(pieces_2, cv_format(v_name, ""))
                cv_push(pieces_2, cv_text(" указан дважды"))
                ccp_error(v_self, cv_join(cv_text(""), pieces_2), v_param)
                return 0
            cv_push(v_params, v_name)
            if cv_truth(ccp_atp(v_self, cv_text(":"))):
                let v_colon: i64 = ccp_next(v_self)
                if v_eq_params == 0:
                    cc_error(cv_text("ограничения параметров типа разрешены только у функций"), cv_getkey(v_self, "file"), cv_getkey(v_colon, "line"))
                    return 0
                let v_bound: i64 = ccp_expect(v_self, cv_text("id"), 0)
                let v_bound_name: i64 = cv_getkey(v_bound, "t")
                if not cv_name(v_bound_name, "Eq"):
                    cc_error(cv_cat(cv_text("неизвестное ограничение параметра типа: "), v_bound_name), cv_getkey(v_self, "file"), cv_getkey(v_bound, "line"))
                    return 0
                cv_push(v_eq_params, v_name)
            if not (cv_truth(ccp_atp(v_self, cv_text(",")))):
                break
            ccp_next(v_self)
        ccp_expect_gt(v_self)
    return v_params

unsafe fn ccp_parse_enum(v_self: i64, v_header: i64) -> i64:
    let v_kw: i64 = 0
    let v_name: i64 = 0
    let v_pe: i64 = 0
    let v_base: i64 = 0
    let v_variants: i64 = 0
    let v_names: i64 = 0
    let v_next_value: i64 = 0
    let v_t: i64 = 0
    let v_variant: i64 = 0
    let v_variant_name: i64 = 0
    let v_value: i64 = 0
    let v_negative: i64 = 0
    let v_value_tok: i64 = 0
    let v_text: i64 = 0
    v_kw = ccp_next(v_self)
    v_name = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
    ccp_expect(v_self, cv_text("punct"), cv_text(":"))
    ccp_line_end(v_self)
    v_pe = ccp_peek(v_self)
    if ((cv_equal(cv_subscript(v_pe, cv_text("k")), cv_text("eof"))) or (cv_le(cv_subscript(v_pe, cv_text("ind")), v_header))):
        let pieces_1: i64 = cv_list()
        cv_push(pieces_1, cv_text("enum "))
        cv_push(pieces_1, cv_format(v_name, ""))
        cv_push(pieces_1, cv_text(": ожидается вариант с отступом"))
        ccp_error(v_self, cv_join(cv_text(""), pieces_1), v_kw)
        return 0
    v_base = cv_subscript(v_pe, cv_text("ind"))
    let items_2: i64 = cv_vector(CV_LIST)
    v_variants = items_2
    v_names = cv_vector(CV_SET)
    v_next_value = 3
    while cv_truth(CV_TRUE):
        v_t = ccp_peek(v_self)
        if ((cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("eof"))) or (cv_less(cv_subscript(v_t, cv_text("ind")), v_base))):
            break
        if ((not (cv_equal(cv_subscript(v_t, cv_text("ind")), v_base))) or (not (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("id"))))):
            let pieces_3: i64 = cv_list()
            cv_push(pieces_3, cv_text("enum "))
            cv_push(pieces_3, cv_format(v_name, ""))
            cv_push(pieces_3, cv_text(": ожидается имя варианта"))
            ccp_error(v_self, cv_join(cv_text(""), pieces_3), v_t)
            return 0
        v_variant = ccp_next(v_self)
        v_variant_name = cv_subscript(v_variant, cv_text("t"))
        if (cv_contains(v_names, v_variant_name)):
            let pieces_4: i64 = cv_list()
            cv_push(pieces_4, cv_text("enum "))
            cv_push(pieces_4, cv_format(v_name, ""))
            cv_push(pieces_4, cv_text(": вариант "))
            cv_push(pieces_4, cv_format(v_variant_name, ""))
            cv_push(pieces_4, cv_text(" определён дважды"))
            ccp_error(v_self, cv_join(cv_text(""), pieces_4), v_variant)
            return 0
        cv_add_set(v_names, v_variant_name)
        let payload: i64 = 0
        if cv_truth(ccp_atp(v_self, cv_text("("))):
            ccp_next(v_self)
            payload = ccp_parse_type(v_self, CV_FALSE, cv_i(0))
            ccp_expect(v_self, cv_text("punct"), cv_text(")"))
        v_value = v_next_value
        if cv_truth(ccp_atp(v_self, cv_text("="))):
            ccp_next(v_self)
            v_negative = CV_FALSE
            if cv_truth(ccp_atp(v_self, cv_text("-"))):
                ccp_next(v_self)
                v_negative = CV_TRUE
            v_value_tok = ccp_expect(v_self, cv_text("num"), 0)
            if cv_truth(cv_get(v_value_tok, cv_text("f"), 0)):
                let pieces_5: i64 = cv_list()
                cv_push(pieces_5, cv_text("enum "))
                cv_push(pieces_5, cv_format(v_name, ""))
                cv_push(pieces_5, cv_text(": значение варианта должно быть целым"))
                ccp_error(v_self, cv_join(cv_text(""), pieces_5), v_value_tok)
                return 0
            v_text = cv_subscript(v_value_tok, cv_text("t"))
            if cv_truth(cv_bool(cv_starts(v_text, cv_pair(cv_text("0x"), cv_text("0X"))))):
                v_value = cv_int(v_text, 131)
            else:
                if cv_truth(cv_bool(cv_starts(v_text, cv_pair(cv_text("0b"), cv_text("0B"))))):
                    v_value = cv_int(v_text, 19)
                else:
                    v_value = cv_int(v_text, 83)
            if cv_truth(v_negative):
                v_value = cv_neg(v_value)
        if ((cv_less(v_value, cv_neg(cv_shl(11, 507)))) or (cv_less(cv_sub(cv_shl(11, 507), 11), v_value))):
            let pieces_6: i64 = cv_list()
            cv_push(pieces_6, cv_text("enum "))
            cv_push(pieces_6, cv_format(v_name, ""))
            cv_push(pieces_6, cv_text(": значение вне диапазона i64"))
            ccp_error(v_self, cv_join(cv_text(""), pieces_6), v_variant)
            return 0
        ccp_line_end(v_self)
        let variant: i64 = cv_pair(v_variant_name, v_value)
        cv_push(variant, payload)
        cv_push(v_variants, variant)
        v_next_value = cv_add(v_value, 11)
    if not (cv_truth(v_variants)):
        let pieces_7: i64 = cv_list()
        cv_push(pieces_7, cv_text("enum "))
        cv_push(pieces_7, cv_format(v_name, ""))
        cv_push(pieces_7, cv_text(": нет вариантов"))
        ccp_error(v_self, cv_join(cv_text(""), pieces_7), v_kw)
        return 0
    return cc_EnumDef(cv_getkey(v_self, "file"), v_name, v_variants, cv_subscript(v_kw, cv_text("line")))

unsafe fn ccp_parse_fn(v_self: i64, v_head_ind: i64) -> i64:
    let v_is_unsafe: i64 = 0
    let v_native: i64 = 0
    let v_kw: i64 = 0
    let v_is_extern: i64 = 0
    let v_name: i64 = 0
    let v_type_params: i64 = 0
    let v_params: i64 = 0
    let v_pn: i64 = 0
    let v_pt: i64 = 0
    let v_ret: i64 = 0
    let v_body: i64 = 0
    let v_raw: i64 = 0
    let v_parts: i64 = 0
    v_is_unsafe = CV_FALSE
    if cv_truth(ccp_at(v_self, cv_text("unsafe"))):
        ccp_next(v_self)
        v_is_unsafe = CV_TRUE
    v_native = CV_FALSE
    v_kw = ccp_next(v_self)
    v_is_extern = cv_bool((cv_equal(cv_subscript(v_kw, cv_text("t")), cv_text("extern"))))
    if (cv_equal(cv_subscript(v_kw, cv_text("t")), cv_text("native"))):
        v_native = CV_TRUE
        ccp_expect(v_self, cv_text("kw"), cv_text("fn"))
    else:
        if cv_truth(v_is_extern):
            if cv_truth(ccp_at(v_self, cv_text("fn"))):
                ccp_next(v_self)
        else:
            if (cv_equal(cv_subscript(v_kw, cv_text("t")), cv_text("fn"))):
                if cv_truth(ccp_at(v_self, cv_text("native"))):
                    ccp_next(v_self)
                    v_native = CV_TRUE
    v_name = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
    let v_eq_params: i64 = cv_list()
    v_type_params = ccp_parse_type_params(v_self, v_eq_params)
    ccp_expect(v_self, cv_text("punct"), cv_text("("))
    let items_1: i64 = cv_vector(CV_LIST)
    v_params = items_1
    if not (cv_truth(ccp_atp(v_self, cv_text(")")))):
        while cv_truth(CV_TRUE):
            v_pn = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
            ccp_expect(v_self, cv_text("punct"), cv_text(":"))
            v_pt = ccp_parse_type(v_self, CV_FALSE, 3)
            cv_push(v_params, cv_pair(v_pn, v_pt))
            if cv_truth(ccp_atp(v_self, cv_text(","))):
                ccp_next(v_self)
                continue
            break
    ccp_expect(v_self, cv_text("punct"), cv_text(")"))
    v_ret = 0
    if cv_truth(ccp_atp(v_self, cv_text("->"))):
        ccp_next(v_self)
        v_ret = ccp_parse_type(v_self, CV_FALSE, 3)
    let v_source: i64 = 0
    let v_next: i64 = ccp_peek(v_self)
    if cv_name(cv_getkey(v_next, "k"), "id") and cv_name(cv_getkey(v_next, "t"), "from"):
        ccp_next(v_self)
        v_source = cv_getkey(ccp_expect(v_self, cv_text("id"), 0), "t")
    if cv_truth(v_native):
        v_body = ccp_parse_native_body(v_self)
        let seq_3: i64 = v_body
        for index_2 in 0..cv_len(seq_3):
            v_raw = cv_at(seq_3, index_2)
            v_parts = cv_split(cv_strip(v_raw), 0, 11)
            let logic_5: bool = cv_truth(v_parts)
            if logic_5:
                let subject_4: i64 = cv_lower(cv_subscript(v_parts, 3))
                logic_5 = ((cv_equal(subject_4, cv_text("ret")) or cv_equal(subject_4, cv_text("retw")) or cv_equal(subject_4, cv_text("retl")) or cv_equal(subject_4, cv_text("retq")) or cv_equal(subject_4, cv_text("retn")) or cv_equal(subject_4, cv_text("retf")) or cv_equal(subject_4, cv_text("lret")) or cv_equal(subject_4, cv_text("lretw")) or cv_equal(subject_4, cv_text("lretl")) or cv_equal(subject_4, cv_text("lretq")) or cv_equal(subject_4, cv_text("iret")) or cv_equal(subject_4, cv_text("iretw")) or cv_equal(subject_4, cv_text("iretd")) or cv_equal(subject_4, cv_text("iretq"))))
            if (logic_5):
                ccp_error(v_self, cv_text("native-тело не должно содержать ret: эпилог добавляет компилятор"), v_kw)
                return 0
        if cv_truth(v_type_params):
            ccp_error(v_self, cv_text("generic-функции пока не поддерживают native/extern ABI"), v_kw)
            return 0
        let extra_6: i64 = cv_tuple()
        cv_push(extra_6, CV_TRUE)
        cv_push(extra_6, cv_subscript(v_kw, cv_text("line")))
        cv_push(extra_6, CV_TRUE)
        cv_push(extra_6, 0)
        let v_fn: i64 = cc_FnDef(cv_getkey(v_self, "file"), v_name, v_params, v_ret, v_body, extra_6)
        if v_source != 0: cv_field(v_fn, "ret_source", v_source)
        return v_fn
    if cv_truth(v_is_extern):
        if cv_truth(v_type_params):
            ccp_error(v_self, cv_text("generic-функции пока не поддерживают native/extern ABI"), v_kw)
            return 0
        ccp_line_end(v_self)
        let extra_7: i64 = cv_tuple()
        cv_push(extra_7, 0)
        cv_push(extra_7, cv_subscript(v_kw, cv_text("line")))
        cv_push(extra_7, v_is_unsafe)
        cv_push(extra_7, 0)
        let v_fn: i64 = cc_FnDef(cv_getkey(v_self, "file"), v_name, v_params, v_ret, 0, extra_7)
        if v_source != 0: cv_field(v_fn, "ret_source", v_source)
        return v_fn
    ccp_expect(v_self, cv_text("punct"), cv_text(":"))
    ccp_line_end(v_self)
    v_body = ccp_parse_block(v_self, v_head_ind)
    let extra_9: i64 = cv_tuple()
    cv_push(extra_9, 0)
    cv_push(extra_9, cv_subscript(v_kw, cv_text("line")))
    cv_push(extra_9, v_is_unsafe)
    cv_push(extra_9, v_type_params)
    let v_fn: i64 = cc_FnDef(cv_getkey(v_self, "file"), v_name, v_params, v_ret, v_body, extra_9)
    if v_source != 0: cv_field(v_fn, "ret_source", v_source)
    if cv_truth(v_eq_params): cv_field(v_fn, "eq_params", v_eq_params)
    return v_fn

unsafe fn ccp_parse_native_body(v_self: i64) -> i64:
    let v_lines: i64 = 0
    let v_t: i64 = 0
    let v_buf: i64 = 0
    let v_tok: i64 = 0
    if cv_truth(ccp_atp(v_self, cv_text(":"))):
        ccp_next(v_self)
    ccp_skip_nl(v_self)
    ccp_expect(v_self, cv_text("punct"), cv_text("{"))
    let items_1: i64 = cv_vector(CV_LIST)
    v_lines = items_1
    while cv_truth(CV_TRUE):
        while ((cv_less(cv_getkey(v_self, "i"), cv_length(cv_getkey(v_self, "toks")))) and (cv_equal(cv_subscript(cv_subscript(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i")), cv_text("k")), cv_text("nl")))):
            cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
        if (cv_le(cv_length(cv_getkey(v_self, "toks")), cv_getkey(v_self, "i"))):
            cc_error(cv_text("незакрытый native-блок {"), cv_getkey(v_self, "file"), 11)
            return 0
        v_t = cv_subscript(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i"))
        if ((cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("punct"))) and (cv_equal(cv_subscript(v_t, cv_text("t")), cv_text("}")))):
            cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
            break
        let items_2: i64 = cv_vector(CV_LIST)
        v_buf = items_2
        while ((cv_less(cv_getkey(v_self, "i"), cv_length(cv_getkey(v_self, "toks")))) and (not (cv_equal(cv_subscript(cv_subscript(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i")), cv_text("k")), cv_text("nl"))))):
            v_tok = cv_subscript(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i"))
            if ((cv_equal(cv_subscript(v_tok, cv_text("k")), cv_text("punct"))) and (cv_equal(cv_subscript(v_tok, cv_text("t")), cv_text("}")))):
                break
            if (cv_equal(cv_subscript(v_tok, cv_text("k")), cv_text("str"))):
                cv_push(v_buf, cv_mod(cv_text("\"%s\""), cv_replace(cv_replace(cv_subscript(v_tok, cv_text("t")), cv_text("\\"), cv_text("\\\\")), cv_text("\""), cv_text("\\\""))))
            else:
                if (cv_equal(cv_subscript(v_tok, cv_text("k")), cv_text("char"))):
                    cv_push(v_buf, cv_mod(cv_text("'%s'"), cv_subscript(v_tok, cv_text("t"))))
                else:
                    cv_push(v_buf, cv_subscript(v_tok, cv_text("t")))
            cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
        cv_push(v_lines, cv_join(cv_text(" "), v_buf))
    return v_lines

unsafe fn ccp_skip_nl(v_self: i64) -> i64:
    while ((cv_less(cv_getkey(v_self, "i"), cv_length(cv_getkey(v_self, "toks")))) and (cv_equal(cv_subscript(cv_subscript(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i")), cv_text("k")), cv_text("nl")))):
        cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
    return 0

unsafe fn ccp_block_or_inline(v_self: i64, v_head_line: i64, v_head_ind: i64) -> i64:
    let v_t: i64 = 0
    let v_st: i64 = 0
    v_t = ccp_peek(v_self)
    if ((not (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("nl")))) and (not (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("eof")))) and (cv_equal(cv_subscript(v_t, cv_text("line")), v_head_line))):
        v_st = ccp_parse_stmt(v_self)
        let items_1: i64 = cv_vector(CV_LIST)
        cv_push(items_1, v_st)
        return items_1
    ccp_skip_nl(v_self)
    return ccp_parse_block(v_self, v_head_ind)

unsafe fn ccp_parse_block(v_self: i64, v_parent_ind: i64) -> i64:
    let v_t: i64 = 0
    let v_base: i64 = 0
    let v_stmts: i64 = 0
    ccp_skip_nl(v_self)
    v_t = ccp_peek(v_self)
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("eof"))):
        let items_1: i64 = cv_vector(CV_LIST)
        return items_1
    v_base = cv_subscript(v_t, cv_text("ind"))
    if (cv_le(v_base, v_parent_ind)):
        ccp_error(v_self, cv_text("тело блока должно иметь отступ больше заголовка"), v_t)
        return 0
    let items_2: i64 = cv_vector(CV_LIST)
    v_stmts = items_2
    while cv_truth(CV_TRUE):
        v_t = ccp_peek(v_self)
        if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("eof"))):
            break
        if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("nl"))):
            cv_field(v_self, "i", cv_add(cv_getkey(v_self, "i"), 11))
            continue
        if (cv_less(cv_subscript(v_t, cv_text("ind")), v_base)):
            break
        if (cv_less(v_base, cv_subscript(v_t, cv_text("ind")))):
            ccp_error(v_self, cv_text("несогласованный отступ в блоке"), v_t)
            return 0
        cv_push(v_stmts, ccp_parse_stmt(v_self))
    return v_stmts

unsafe fn ccp_parse_stmt(v_self: i64) -> i64:
    let v_t: i64 = 0
    let v_kw: i64 = 0
    let v_action: i64 = 0
    let v_e: i64 = 0
    let v_body: i64 = 0
    let v_op: i64 = 0
    let v_rhs: i64 = 0
    let v_real: i64 = 0
    v_t = ccp_peek(v_self)
    if cv_truth(ccp_at(v_self, cv_text("match"))):
        return ccp_parse_match(v_self)
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("kw"))):
        v_kw = cv_subscript(v_t, cv_text("t"))
        if (cv_equal(v_kw, cv_text("let"))):
            return ccp_parse_let(v_self)
        if (cv_equal(v_kw, cv_text("const"))):
            return ccp_parse_const(v_self)
        if (cv_equal(v_kw, cv_text("defer"))):
            ccp_next(v_self)
            v_action = ccp_parse_stmt(v_self)
            if cv_classes(v_action, "DeferStmt") or cv_classes(v_action, "ReturnStmt") or cv_classes(v_action, "BreakStmt") or cv_classes(v_action, "ContinueStmt") or cv_classes(v_action, "IfStmt") or cv_classes(v_action, "WhileStmt") or cv_classes(v_action, "ForStmt") or cv_classes(v_action, "UnsafeStmt") or cv_classes(v_action, "LetStmt") or cv_classes(v_action, "ConstStmt"):
                ccp_error(v_self, cv_text("defer допускает только простой оператор без flow-control или вложенного defer"), v_t)
                return 0
            return cc_DeferStmt(v_action, cv_subscript(v_t, cv_text("line")))
        if (cv_equal(v_kw, cv_text("return"))):
            ccp_next(v_self)
            v_e = 0
            let subject_1: i64 = cv_subscript(ccp_peek(v_self), cv_text("k"))
            if (not ((cv_equal(subject_1, cv_text("nl")) or cv_equal(subject_1, cv_text("eof"))))):
                v_e = ccp_parse_expr(v_self)
            ccp_line_end(v_self)
            return cc_ReturnStmt(v_e, cv_subscript(v_t, cv_text("line")))
        if (cv_equal(v_kw, cv_text("break"))):
            ccp_next(v_self)
            ccp_line_end(v_self)
            return cc_BreakStmt(cv_subscript(v_t, cv_text("line")))
        if (cv_equal(v_kw, cv_text("continue"))):
            ccp_next(v_self)
            ccp_line_end(v_self)
            return cc_ContinueStmt(cv_subscript(v_t, cv_text("line")))
        if (cv_equal(v_kw, cv_text("if"))):
            return ccp_parse_if(v_self)
        if (cv_equal(v_kw, cv_text("while"))):
            return ccp_parse_while(v_self)
        if (cv_equal(v_kw, cv_text("for"))):
            return ccp_parse_for(v_self)
        if (cv_equal(v_kw, cv_text("unsafe"))):
            ccp_next(v_self)
            ccp_expect(v_self, cv_text("punct"), cv_text(":"))
            v_body = ccp_block_or_inline(v_self, cv_subscript(v_t, cv_text("line")), cv_subscript(v_t, cv_text("ind")))
            if not (cv_truth(v_body)):
                ccp_error(v_self, cv_text("пустой unsafe-блок"), v_t)
                return 0
            return cc_UnsafeStmt(v_body, cv_subscript(v_t, cv_text("line")))
    v_e = ccp_parse_expr(v_self)
    let items_4: i64 = cv_vector(CV_TUPLE)
    cv_push(items_4, cv_text("="))
    cv_push(items_4, cv_text("+="))
    cv_push(items_4, cv_text("-="))
    cv_push(items_4, cv_text("*="))
    cv_push(items_4, cv_text("/="))
    cv_push(items_4, cv_text("%="))
    cv_push(items_4, cv_text("&="))
    cv_push(items_4, cv_text("|="))
    cv_push(items_4, cv_text("^="))
    cv_push(items_4, cv_text("<<="))
    cv_push(items_4, cv_text(">>="))
    let seq_3: i64 = items_4
    for index_2 in 0..cv_len(seq_3):
        v_op = cv_at(seq_3, index_2)
        if cv_truth(ccp_atp(v_self, v_op)):
            ccp_next(v_self)
            v_rhs = ccp_parse_expr(v_self)
            ccp_line_end(v_self)
            let choice_5: i64 = 0
            if (cv_equal(v_op, cv_text("="))):
                choice_5 = cv_text("=")
            else:
                choice_5 = cv_slice(v_op, 0, cv_neg(11))
            v_real = choice_5
            return cc_AssignStmt(v_e, v_real, v_rhs, cv_subscript(v_t, cv_text("line")))
    ccp_line_end(v_self)
    return cc_ExprStmt(v_e, cv_subscript(v_t, cv_text("line")))

unsafe fn ccp_parse_const(v_self: i64) -> i64:
    let v_t: i64 = 0
    let v_name: i64 = 0
    let v_typ: i64 = 0
    let v_init: i64 = 0
    v_t = ccp_next(v_self)
    v_name = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
    v_typ = ccp_parse_type_opt(v_self)
    ccp_expect(v_self, cv_text("punct"), cv_text("="))
    v_init = ccp_parse_expr(v_self)
    ccp_line_end(v_self)
    return cc_ConstStmt(v_name, v_typ, v_init, cv_subscript(v_t, cv_text("line")))

unsafe fn ccp_parse_let(v_self: i64) -> i64:
    let v_t: i64 = 0
    let v_name: i64 = 0
    let v_typ: i64 = 0
    let v_init: i64 = 0
    v_t = ccp_next(v_self)
    v_name = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
    v_typ = ccp_parse_type_opt(v_self)
    v_init = 0
    if cv_truth(ccp_atp(v_self, cv_text("="))):
        ccp_next(v_self)
        v_init = ccp_parse_expr(v_self)
    ccp_line_end(v_self)
    return cc_LetStmt(v_name, v_typ, v_init, cv_subscript(v_t, cv_text("line")))

unsafe fn ccp_parse_match(v_self: i64) -> i64:
    let v_kw: i64 = 0
    let v_value: i64 = 0
    let v_base: i64 = 0
    let v_arms: i64 = 0
    let v_p: i64 = 0
    let v_pattern: i64 = 0
    let v_binding: i64 = 0
    let v_body: i64 = 0
    v_kw = ccp_next(v_self)
    v_value = ccp_parse_expr(v_self)
    ccp_expect(v_self, cv_text("punct"), cv_text(":"))
    ccp_line_end(v_self)
    ccp_skip_nl(v_self)
    v_base = cv_subscript(ccp_peek(v_self), cv_text("ind"))
    let items_1: i64 = cv_vector(CV_LIST)
    v_arms = items_1
    while true:
        let subject_2: i64 = cv_subscript(ccp_peek(v_self), cv_text("k"))
        if not (((not ((cv_equal(subject_2, cv_text("eof")) or cv_equal(subject_2, cv_text("nl"))))) and (cv_equal(cv_subscript(ccp_peek(v_self), cv_text("ind")), v_base)))): break
        v_p = ccp_next(v_self)
        let subject_3: i64 = cv_subscript(v_p, cv_text("k"))
        if (not ((cv_equal(subject_3, cv_text("id")) or cv_equal(subject_3, cv_text("kw"))))):
            ccp_error(v_self, cv_cat(cv_text("ожидался вариант, Some(x)/Ok(x)/Err(x) или _, найдено "), cv_format(cv_subscript(v_p, cv_text("t")), "r")), v_p)
            return 0
        v_pattern = cv_subscript(v_p, cv_text("t"))
        v_binding = 0
        let binding_required: bool = cv_name(v_pattern, "Some") or cv_name(v_pattern, "Ok") or cv_name(v_pattern, "Err")
        let qualified: bool = cv_truth(ccp_atp(v_self, cv_text(".")))
        while cv_truth(ccp_atp(v_self, cv_text("."))):
            ccp_next(v_self)
            v_pattern = cc_qualified_variant(v_pattern, cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t")))
        if (not qualified and binding_required) or (qualified and cv_truth(ccp_atp(v_self, cv_text("(")))):
            ccp_expect(v_self, cv_text("punct"), cv_text("("))
            v_binding = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
            ccp_expect(v_self, cv_text("punct"), cv_text(")"))
        ccp_expect(v_self, cv_text("punct"), cv_text(":"))
        v_body = ccp_block_or_inline(v_self, cv_subscript(v_p, cv_text("line")), cv_subscript(v_p, cv_text("ind")))
        cv_push(v_arms, cc_MatchArm(v_pattern, v_binding, v_body, cv_subscript(v_p, cv_text("line"))))
        ccp_skip_nl(v_self)
    if not (cv_truth(v_arms)):
        ccp_error(v_self, cv_text("match требует хотя бы один arm"), v_kw)
        return 0
    return cc_MatchStmt(v_value, v_arms, cv_subscript(v_kw, cv_text("line")))

unsafe fn ccp_parse_if(v_self: i64) -> i64:
    let v_first: i64 = 0
    let v_kw: i64 = 0
    let v_header_ind: i64 = 0
    let v_conds: i64 = 0
    let v_els: i64 = 0
    let v_cond: i64 = 0
    let v_body: i64 = 0
    let v_ekw: i64 = 0
    v_first = ccp_next(v_self)
    v_kw = v_first
    v_header_ind = cv_subscript(v_first, cv_text("ind"))
    let items_1: i64 = cv_vector(CV_LIST)
    v_conds = items_1
    v_els = 0
    while cv_truth(CV_TRUE):
        v_cond = ccp_parse_expr(v_self)
        ccp_expect(v_self, cv_text("punct"), cv_text(":"))
        v_body = ccp_block_or_inline(v_self, cv_subscript(v_kw, cv_text("line")), cv_subscript(v_kw, cv_text("ind")))
        if not (cv_truth(v_body)):
            cc_error(cv_text("пустой блок"), cv_getkey(v_self, "file"), cv_getkey(v_cond, "line"))
            return 0
        cv_push(v_conds, cv_pair(v_cond, v_body))
        if (cv_truth(ccp_at(v_self, cv_text("elif"))) and (cv_equal(cv_subscript(ccp_peek(v_self), cv_text("ind")), v_header_ind))):
            v_kw = ccp_next(v_self)
            continue
        break
    if (cv_truth(ccp_at(v_self, cv_text("else"))) and (cv_equal(cv_subscript(ccp_peek(v_self), cv_text("ind")), v_header_ind))):
        v_ekw = ccp_next(v_self)
        ccp_expect(v_self, cv_text("punct"), cv_text(":"))
        v_els = ccp_block_or_inline(v_self, cv_subscript(v_ekw, cv_text("line")), cv_subscript(v_ekw, cv_text("ind")))
    return cc_IfStmt(v_conds, v_els, cv_subscript(v_first, cv_text("line")))

unsafe fn ccp_parse_while(v_self: i64) -> i64:
    let v_kw: i64 = 0
    let v_cond: i64 = 0
    let v_body: i64 = 0
    v_kw = ccp_next(v_self)
    v_cond = ccp_parse_expr(v_self)
    ccp_expect(v_self, cv_text("punct"), cv_text(":"))
    v_body = ccp_block_or_inline(v_self, cv_subscript(v_kw, cv_text("line")), cv_subscript(v_kw, cv_text("ind")))
    return cc_WhileStmt(v_cond, v_body, cv_subscript(v_kw, cv_text("line")))

unsafe fn ccp_parse_for(v_self: i64) -> i64:
    let v_kw: i64 = 0
    let v_var: i64 = 0
    let v_a: i64 = 0
    let v_inclusive: i64 = 0
    let v_b: i64 = 0
    let v_body: i64 = 0
    let v_st: i64 = 0
    v_kw = ccp_next(v_self)
    v_var = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
    ccp_expect(v_self, cv_text("kw"), cv_text("in"))
    v_a = ccp_parse_expr(v_self)
    v_inclusive = ccp_atp(v_self, cv_text("..="))
    let choice_1: i64 = 0
    if cv_truth(v_inclusive):
        choice_1 = cv_text("..=")
    else:
        choice_1 = cv_text("..")
    ccp_expect(v_self, cv_text("punct"), choice_1)
    v_b = ccp_parse_expr(v_self)
    ccp_expect(v_self, cv_text("punct"), cv_text(":"))
    v_body = ccp_block_or_inline(v_self, cv_subscript(v_kw, cv_text("line")), cv_subscript(v_kw, cv_text("ind")))
    v_st = cc_ForStmt(v_var, v_a, v_b, v_body, cv_subscript(v_kw, cv_text("line")))
    cv_field(v_st, "inclusive", v_inclusive)
    return v_st

unsafe fn ccp_parse_type_opt(v_self: i64) -> i64:
    if cv_truth(ccp_atp(v_self, cv_text(":"))):
        ccp_next(v_self)
        return ccp_parse_type(v_self, CV_FALSE, 3)
    return 0

unsafe fn ccp_parse_type(v_self: i64, v_in_cast: i64, v_nesting: i64) -> i64:
    let v_t: i64 = 0
    let v_mutable: i64 = 0
    let v_elem: i64 = 0
    let v_size: i64 = 0
    let v_size_n: i64 = 0
    let v_name: i64 = 0
    let v_e: i64 = 0
    let v_params: i64 = 0
    let v_result: i64 = 0
    let v_args: i64 = 0
    v_t = ccp_peek(v_self)
    if (cv_le(515, v_nesting)):
        ccp_error(v_self, cv_text("превышена глубина вложенности типов"), v_t)
        return 0
    if cv_truth(ccp_atp(v_self, cv_text("["))):
        ccp_next(v_self)
        if cv_truth(ccp_atp(v_self, cv_text("]"))):
            ccp_next(v_self)
            v_mutable = CV_FALSE
            if cv_truth(ccp_at(v_self, cv_text("mut"))):
                ccp_next(v_self)
                v_mutable = CV_TRUE
            v_elem = ccp_parse_type(v_self, v_in_cast, cv_add(v_nesting, 11))
            let items_1: i64 = cv_vector(CV_TUPLE)
            cv_push(items_1, v_elem)
            let choice_2: i64 = 0
            if cv_truth(v_mutable):
                choice_2 = cv_text("slice_mut")
            else:
                choice_2 = cv_text("slice")
            return cc_TExpr(choice_2, items_1, cv_subscript(v_t, cv_text("line")), cv_getkey(v_self, "file"))
        v_size = ccp_expect(v_self, cv_text("num"), 0)
        v_size_n = cv_int(cv_subscript(v_size, cv_text("t")), 83)
        ccp_expect(v_self, cv_text("punct"), cv_text("]"))
        v_elem = ccp_parse_type(v_self, v_in_cast, cv_add(v_nesting, 11))
        return cc_TExpr(cv_text("array"), cv_pair(v_elem, v_size_n), cv_subscript(v_t, cv_text("line")), cv_getkey(v_self, "file"))
    v_name = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
    if cv_truth(ccp_atp(v_self, cv_text("."))) and (not cv_truth(v_in_cast) or not cv_contains(cc_k_scalar_type_names, v_name)):
        ccp_next(v_self)
        v_name = cc_qualified_variant(v_name, cv_getkey(ccp_expect(v_self, cv_text("id"), 0), "t"))
    if (cv_equal(v_name, cv_text("ptr"))):
        ccp_expect(v_self, cv_text("punct"), cv_text("<"))
        v_e = ccp_parse_type(v_self, CV_FALSE, cv_add(v_nesting, 11))
        ccp_expect_gt(v_self)
        let items_3: i64 = cv_vector(CV_TUPLE)
        cv_push(items_3, v_e)
        return cc_TExpr(cv_text("ptr"), items_3, cv_subscript(v_t, cv_text("line")), cv_getkey(v_self, "file"))
    if (cv_equal(v_name, cv_text("fnptr"))):
        ccp_expect(v_self, cv_text("punct"), cv_text("<"))
        ccp_expect(v_self, cv_text("punct"), cv_text("("))
        let items_4: i64 = cv_vector(CV_LIST)
        v_params = items_4
        if not (cv_truth(ccp_atp(v_self, cv_text(")")))):
            while cv_truth(CV_TRUE):
                cv_push(v_params, ccp_parse_type(v_self, CV_FALSE, cv_add(v_nesting, 11)))
                if not (cv_truth(ccp_atp(v_self, cv_text(",")))):
                    break
                ccp_next(v_self)
        ccp_expect(v_self, cv_text("punct"), cv_text(")"))
        v_result = 0
        if cv_truth(ccp_atp(v_self, cv_text("->"))):
            ccp_next(v_self)
            v_result = ccp_parse_type(v_self, CV_FALSE, cv_add(v_nesting, 11))
        ccp_expect_gt(v_self)
        return cc_TExpr(cv_text("fnptr"), cv_pair(cv_astuple(v_params), v_result), cv_subscript(v_t, cv_text("line")), cv_getkey(v_self, "file"))
    if ((cv_equal(v_name, cv_text("Option")) or cv_equal(v_name, cv_text("Result")))):
        ccp_expect(v_self, cv_text("punct"), cv_text("<"))
        let items_5: i64 = cv_vector(CV_LIST)
        cv_push(items_5, ccp_parse_type(v_self, CV_FALSE, cv_add(v_nesting, 11)))
        v_args = items_5
        if (cv_equal(v_name, cv_text("Result"))):
            ccp_expect(v_self, cv_text("punct"), cv_text(","))
            cv_push(v_args, ccp_parse_type(v_self, CV_FALSE, cv_add(v_nesting, 11)))
        ccp_expect_gt(v_self)
        let items_6: i64 = cv_vector(CV_TUPLE)
        cv_extend(items_6, v_args)
        return cc_TExpr(cv_lower(v_name), items_6, cv_subscript(v_t, cv_text("line")), cv_getkey(v_self, "file"))
    if (cv_truth(ccp_atp(v_self, cv_text("<"))) and not (cv_truth(v_in_cast))):
        ccp_next(v_self)
        let items_7: i64 = cv_vector(CV_LIST)
        cv_push(items_7, ccp_parse_type(v_self, CV_FALSE, cv_add(v_nesting, 11)))
        v_args = items_7
        while cv_truth(ccp_atp(v_self, cv_text(","))):
            ccp_next(v_self)
            cv_push(v_args, ccp_parse_type(v_self, CV_FALSE, cv_add(v_nesting, 11)))
        ccp_expect_gt(v_self)
        let items_8: i64 = cv_vector(CV_TUPLE)
        cv_push(items_8, v_name)
        cv_extend(items_8, v_args)
        return cc_TExpr(cv_text("struct_type"), items_8, cv_subscript(v_t, cv_text("line")), cv_getkey(v_self, "file"))
    let items_9: i64 = cv_vector(CV_TUPLE)
    cv_push(items_9, v_name)
    return cc_TExpr(cv_text("name"), items_9, cv_subscript(v_t, cv_text("line")), cv_getkey(v_self, "file"))

unsafe fn ccp_expect_gt(v_self: i64) -> i64:
    let v_t: i64 = 0
    v_t = ccp_next(v_self)
    if ((cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("punct"))) and (cv_equal(cv_subscript(v_t, cv_text("t")), cv_text(">")))):
        return 0
    let logic_2: bool = (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("punct")))
    if logic_2:
        let subject_1: i64 = cv_subscript(v_t, cv_text("t"))
        logic_2 = ((cv_equal(subject_1, cv_text(">>")) or cv_equal(subject_1, cv_text(">=")) or cv_equal(subject_1, cv_text(">>="))))
    if (logic_2):
        cv_field(v_self, "i", cv_sub(cv_getkey(v_self, "i"), 11))
        let dict_3: i64 = cv_dict()
        cv_update(dict_3, v_t)
        cv_set(dict_3, cv_text("t"), cv_slice(cv_subscript(v_t, cv_text("t")), 11, 0))
        cv_set(dict_3, cv_text("ind"), cv_add(cv_subscript(v_t, cv_text("ind")), 11))
        cv_set(cv_getkey(v_self, "toks"), cv_getkey(v_self, "i"), dict_3)
        return 0
    ccp_error(v_self, cv_cat(cv_text("ожидалось '>', найдено "), cv_format(cv_subscript(v_t, cv_text("t")), "r")), v_t)
    return 0

unsafe fn ccp_parse_expr(v_self: i64) -> i64:
    return ccp_parse_or(v_self)

unsafe fn ccp_parse_or(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_and(v_self)
    while cv_truth(ccp_at(v_self, cv_text("or"))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_and(v_self)
        v_e = cc_Binary(cv_text("or"), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_and(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_not(v_self)
    while cv_truth(ccp_at(v_self, cv_text("and"))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_not(v_self)
        v_e = cc_Binary(cv_text("and"), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_not(v_self: i64) -> i64:
    let v_t: i64 = 0
    let v_x: i64 = 0
    if cv_truth(ccp_at(v_self, cv_text("not"))):
        v_t = ccp_next(v_self)
        v_x = ccp_parse_not(v_self)
        return cc_Unary(cv_text("not"), v_x, cv_subscript(v_t, cv_text("line")))
    return ccp_parse_cmp(v_self)

unsafe fn ccp_parse_cmp(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_op: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_bitor(v_self)
    if (cv_truth(ccp_atp(v_self, cv_text("=="))) or cv_truth(ccp_atp(v_self, cv_text("!="))) or cv_truth(ccp_atp(v_self, cv_text("<"))) or cv_truth(ccp_atp(v_self, cv_text("<="))) or cv_truth(ccp_atp(v_self, cv_text(">"))) or cv_truth(ccp_atp(v_self, cv_text(">=")))):
        v_op = cv_subscript(ccp_next(v_self), cv_text("t"))
        v_r = ccp_parse_bitor(v_self)
        return cc_Binary(v_op, v_e, v_r, cv_getkey(v_e, "line"))
    return v_e

unsafe fn ccp_parse_bitor(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_bitxor(v_self)
    while cv_truth(ccp_atp(v_self, cv_text("|"))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_bitxor(v_self)
        v_e = cc_Binary(cv_text("|"), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_bitxor(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_bitand(v_self)
    while cv_truth(ccp_atp(v_self, cv_text("^"))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_bitand(v_self)
        v_e = cc_Binary(cv_text("^"), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_bitand(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_shift(v_self)
    while cv_truth(ccp_atp(v_self, cv_text("&"))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_shift(v_self)
        v_e = cc_Binary(cv_text("&"), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_shift(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_add(v_self)
    while (cv_truth(ccp_atp(v_self, cv_text("<<"))) or cv_truth(ccp_atp(v_self, cv_text(">>")))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_add(v_self)
        v_e = cc_Binary(cv_subscript(v_t, cv_text("t")), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_add(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_mul(v_self)
    while (cv_truth(ccp_atp(v_self, cv_text("+"))) or cv_truth(ccp_atp(v_self, cv_text("-")))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_mul(v_self)
        v_e = cc_Binary(cv_subscript(v_t, cv_text("t")), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_mul(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_r: i64 = 0
    v_e = ccp_parse_unary(v_self)
    while (cv_truth(ccp_atp(v_self, cv_text("*"))) or cv_truth(ccp_atp(v_self, cv_text("/"))) or cv_truth(ccp_atp(v_self, cv_text("%")))):
        v_t = ccp_next(v_self)
        v_r = ccp_parse_unary(v_self)
        v_e = cc_Binary(cv_subscript(v_t, cv_text("t")), v_e, v_r, cv_subscript(v_t, cv_text("line")))
    return v_e

unsafe fn ccp_parse_unary(v_self: i64) -> i64:
    # Every nesting level (parentheses, call arguments, unary operators) passes
    # through here; bound the recursion so a hostile source cannot overflow
    # the compiler stack.
    if cv_less(cv_i(512), cv_getkey(v_self, "expr_depth")):
        ccp_error(v_self, cv_text("слишком глубокая вложенность выражения"), ccp_peek(v_self))
    cv_field(v_self, "expr_depth", cv_add(cv_getkey(v_self, "expr_depth"), 11))
    defer cv_field(v_self, "expr_depth", cv_sub(cv_getkey(v_self, "expr_depth"), 11))
    let v_t: i64 = 0
    let v_x: i64 = 0
    if cv_truth(ccp_atp(v_self, cv_text("-"))):
        v_t = ccp_next(v_self)
        v_x = ccp_parse_unary(v_self)
        if cv_classes(v_x, "IntLit"):
            return cc_IntLit(cv_neg(cv_getkey(v_x, "val")), cv_subscript(v_t, cv_text("line")))
        if cv_classes(v_x, "FloatLit"):
            return cc_FloatLit(cv_neg(cv_getkey(v_x, "val")), cv_subscript(v_t, cv_text("line")))
        return cc_Unary(cv_text("-"), v_x, cv_subscript(v_t, cv_text("line")))
    if cv_truth(ccp_atp(v_self, cv_text("*"))):
        v_t = ccp_next(v_self)
        return cc_Deref(ccp_parse_unary(v_self), cv_subscript(v_t, cv_text("line")))
    if cv_truth(ccp_atp(v_self, cv_text("&"))):
        v_t = ccp_next(v_self)
        return cc_AddrOf(ccp_parse_unary(v_self), cv_subscript(v_t, cv_text("line")))
    return ccp_parse_postfix(v_self)

unsafe fn cc_qualified_variant(name: i64, variant: i64) -> i64:
    return cv_cat(cv_cat(name, cv_text(".")), variant)

unsafe fn cc_member_path(expr: i64) -> i64:
    if cv_classes(expr, "VarRef"): return cv_getkey(expr, "name")
    if cv_classes(expr, "Member") and cv_classes(cv_getkey(expr, "base"), "VarRef"):
        return cc_qualified_variant(cv_getkey(cv_getkey(expr, "base"), "name"), cv_getkey(expr, "field"))
    return 0

unsafe fn ccp_parse_call_args(v_self: i64) -> i64:
    ccp_expect(v_self, cv_text("punct"), cv_text("("))
    cv_field(v_self, "depth", cv_add(cv_getkey(v_self, "depth"), 11))
    let args: i64 = cv_list()
    if not cv_truth(ccp_atp(v_self, cv_text(")"))):
        while true:
            cv_push(args, ccp_parse_expr(v_self))
            if not cv_truth(ccp_atp(v_self, cv_text(","))): break
            ccp_next(v_self)
    ccp_expect(v_self, cv_text("punct"), cv_text(")"))
    cv_field(v_self, "depth", cv_sub(cv_getkey(v_self, "depth"), 11))
    return args

unsafe fn ccp_parse_postfix(v_self: i64) -> i64:
    let v_e: i64 = 0
    let v_t: i64 = 0
    let v_f: i64 = 0
    let v_idx: i64 = 0
    let v_end: i64 = 0
    let v_ty: i64 = 0
    let v_mutable: i64 = CV_FALSE
    if cv_truth(ccp_at(v_self, cv_text("mut"))):
        ccp_next(v_self)
        v_mutable = CV_TRUE
    v_e = ccp_parse_primary(v_self)
    while cv_truth(CV_TRUE):
        if cv_truth(ccp_atp(v_self, cv_text("?"))):
            v_t = ccp_next(v_self)
            v_e = cc_Unary(cv_text("?"), v_e, cv_subscript(v_t, cv_text("line")))
            continue
        if cv_truth(ccp_atp(v_self, cv_text("."))):
            v_t = ccp_next(v_self)
            v_f = cv_subscript(ccp_expect(v_self, cv_text("id"), 0), cv_text("t"))
            let name: i64 = 0
            if cv_truth(ccp_atp(v_self, cv_text("("))): name = cc_member_path(v_e)
            if name != 0:
                v_e = cc_Call(cc_qualified_variant(name, v_f), ccp_parse_call_args(v_self), cv_getkey(v_t, "line"))
                cv_field(v_e, "call_qualifier", name)
                cv_field(v_e, "call_member", v_f)
                cv_field(v_e, "file", cv_getkey(v_self, "file"))
            else:
                v_e = cc_Member(v_e, v_f, cv_subscript(v_t, cv_text("line")))
            continue
        if cv_truth(ccp_atp(v_self, cv_text("["))):
            cv_field(v_self, "depth", cv_add(cv_getkey(v_self, "depth"), 11))
            v_t = ccp_next(v_self)
            v_idx = ccp_parse_expr(v_self)
            if cv_truth(ccp_atp(v_self, cv_text(".."))):
                ccp_next(v_self)
                v_end = ccp_parse_expr(v_self)
                ccp_expect(v_self, cv_text("punct"), cv_text("]"))
                cv_field(v_self, "depth", cv_sub(cv_getkey(v_self, "depth"), 11))
                v_e = cc_SliceExpr(v_e, v_idx, v_end, v_mutable, cv_subscript(v_t, cv_text("line")))
                v_mutable = CV_FALSE
                continue
            ccp_expect(v_self, cv_text("punct"), cv_text("]"))
            cv_field(v_self, "depth", cv_sub(cv_getkey(v_self, "depth"), 11))
            v_e = cc_Index(v_e, v_idx, cv_subscript(v_t, cv_text("line")))
            continue
        if cv_truth(ccp_at(v_self, cv_text("as"))):
            v_t = ccp_next(v_self)
            v_ty = ccp_parse_type(v_self, CV_TRUE, 3)
            v_e = cc_Cast(v_e, v_ty, cv_subscript(v_t, cv_text("line")))
            continue
        break
    if cv_truth(v_mutable):
        cc_error(cv_text("mut требует диапазон slice"), cv_getkey(v_self, "file"), cv_getkey(v_e, "line"))
    return v_e

unsafe fn ccp_parse_primary(v_self: i64) -> i64:
    let v_t: i64 = 0
    let v_base: i64 = 0
    let v_typ: i64 = 0
    let v_e: i64 = 0
    let v_items: i64 = 0
    v_t = ccp_next(v_self)
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("num"))):
        if cv_truth(cv_get(v_t, cv_text("f"), 0)):
            return cc_FloatLit(cv_f(cv_subscript(v_t, cv_text("t"))), cv_subscript(v_t, cv_text("line")))
        v_base = cv_subscript(v_t, cv_text("t"))
        if (cv_truth(cv_bool(cv_starts(v_base, cv_text("0x")))) or cv_truth(cv_bool(cv_starts(v_base, cv_text("0X"))))):
            return cc_IntLit(cv_int(v_base, 131), cv_subscript(v_t, cv_text("line")))
        if (cv_truth(cv_bool(cv_starts(v_base, cv_text("0b")))) or cv_truth(cv_bool(cv_starts(v_base, cv_text("0B"))))):
            return cc_IntLit(cv_int(v_base, 19), cv_subscript(v_t, cv_text("line")))
        return cc_IntLit(cv_int(v_base, 83), cv_subscript(v_t, cv_text("line")))
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("str"))):
        return cc_StrLit(cv_subscript(v_t, cv_text("t")), cv_subscript(v_t, cv_text("line")))
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("char"))):
        return cc_CharLit(cv_subscript(v_t, cv_text("t")), cv_subscript(v_t, cv_text("line")))
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("kw"))):
        if (cv_equal(cv_subscript(v_t, cv_text("t")), cv_text("true"))):
            return cc_BoolLit(CV_TRUE, cv_subscript(v_t, cv_text("line")))
        if (cv_equal(cv_subscript(v_t, cv_text("t")), cv_text("false"))):
            return cc_BoolLit(CV_FALSE, cv_subscript(v_t, cv_text("line")))
        let subject_1: i64 = cv_subscript(v_t, cv_text("t"))
        if ((cv_equal(subject_1, cv_text("sizeof")) or cv_equal(subject_1, cv_text("alignof")))):
            ccp_expect(v_self, cv_text("punct"), cv_text("("))
            cv_field(v_self, "depth", cv_add(cv_getkey(v_self, "depth"), 11))
            v_typ = ccp_parse_type(v_self, CV_FALSE, 3)
            ccp_expect(v_self, cv_text("punct"), cv_text(")"))
            cv_field(v_self, "depth", cv_sub(cv_getkey(v_self, "depth"), 11))
            return cc_SizeAlignExpr(cv_subscript(v_t, cv_text("t")), v_typ, cv_subscript(v_t, cv_text("line")))
        ccp_error(v_self, cv_cat(cv_text("неожиданное ключевое слово "), cv_format(cv_subscript(v_t, cv_text("t")), "r")), v_t)
        return 0
    if (cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("id"))):
        if (cv_equal(cv_subscript(v_t, cv_text("t")), cv_text("None"))):
            let items_2: i64 = cv_vector(CV_LIST)
            return cc_Call(cv_text("None"), items_2, cv_subscript(v_t, cv_text("line")))
        if cv_truth(ccp_atp(v_self, cv_text("("))):
            let v_call: i64 = cc_Call(cv_getkey(v_t, "t"), ccp_parse_call_args(v_self), cv_getkey(v_t, "line"))
            cv_field(v_call, "file", cv_getkey(v_self, "file"))
            return v_call
        return cc_VarRef(cv_subscript(v_t, cv_text("t")), cv_subscript(v_t, cv_text("line")))
    if ((cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("punct"))) and (cv_equal(cv_subscript(v_t, cv_text("t")), cv_text("(")))):
        cv_field(v_self, "depth", cv_add(cv_getkey(v_self, "depth"), 11))
        v_e = ccp_parse_expr(v_self)
        ccp_expect(v_self, cv_text("punct"), cv_text(")"))
        cv_field(v_self, "depth", cv_sub(cv_getkey(v_self, "depth"), 11))
        return v_e
    if ((cv_equal(cv_subscript(v_t, cv_text("k")), cv_text("punct"))) and (cv_equal(cv_subscript(v_t, cv_text("t")), cv_text("[")))):
        cv_field(v_self, "depth", cv_add(cv_getkey(v_self, "depth"), 11))
        let items_4: i64 = cv_vector(CV_LIST)
        v_items = items_4
        if not (cv_truth(ccp_atp(v_self, cv_text("]")))):
            while cv_truth(CV_TRUE):
                cv_push(v_items, ccp_parse_expr(v_self))
                if cv_truth(ccp_atp(v_self, cv_text(","))):
                    ccp_next(v_self)
                    continue
                break
        ccp_expect(v_self, cv_text("punct"), cv_text("]"))
        cv_field(v_self, "depth", cv_sub(cv_getkey(v_self, "depth"), 11))
        return cc_ArrayLit(v_items, cv_subscript(v_t, cv_text("line")))
    ccp_error(v_self, cv_cat(cv_text("неожиданный токен "), cv_format(cv_subscript(v_t, cv_text("t")), "r")), v_t)
    return 0
