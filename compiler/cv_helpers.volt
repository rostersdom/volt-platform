use cv_text

let cc_k_char_type: i64 = 0
let cc_k_string_type: i64 = 0
let cc_k_int_table: i64 = 0
let cc_k_irtis: i64 = 0
let cc_k_vec_reserved: i64 = 0
let cc_k_int_arg_regs: i64 = 0
let cc_k_subreg: i64 = 0
let cc_k_wmap: i64 = 0
let cc_k_scalar_type_names: i64 = 0
const cc_k_temp_slots: i64 = 32771

unsafe fn cv_single(value: i64) -> i64:
    let tuple: i64 = cv_tuple()
    cv_push(tuple, value)
    return tuple

unsafe fn cc_enum_base(t: i64):
    cv_field(t, "signed", CV_TRUE)
    cv_field(t, "bits", cv_i(64))

unsafe fn cc_intrinsic(names: string, args: string, ret: string, label: string):
    let spec: i64 = cv_tuple()
    cv_push(spec, cv_astuple(cv_split(cv_text(args), 0, 0)))
    let result: i64 = 0
    let target: i64 = 0
    if str_len(ret) != 0: result = cv_text(ret)
    if str_len(label) != 0: target = cv_text(label)
    cv_push(spec, result)
    cv_push(spec, target)
    let keys: i64 = cv_split(cv_text(names), 0, 0)
    for i in 0..cv_len(keys): cv_set(cc_k_irtis, cv_at(keys, i), spec)

unsafe fn cc_constants():
    cc_k_char_type = cc_TInt(CV_FALSE, cv_i(8), cv_text("char"))
    cc_k_string_type = cc_TString()
    cc_k_int_table = cv_dict()
    cc_k_irtis = cv_dict()
    cc_intrinsic("write", "i p i", "i", "VOLT_rt_write")
    cc_intrinsic("write_all", "i p i", "i", "VOLT_rt_write_all")
    cc_intrinsic("panic", "p", "", "VOLT_rt_panic")
    cc_intrinsic("exit", "i", "", "VOLT_rt_exit")
    cc_intrinsic("strlen __volt_strlen", "p", "i", "VOLT_rt_strlen")
    cc_intrinsic("munmap", "p i", "i", "VOLT_rt_munmap")
    cc_intrinsic("mmap", "i", "p", "VOLT_rt_mmap")
    cc_intrinsic("open", "p i i", "i", "VOLT_rt_open")
    cc_intrinsic("close", "i", "i", "VOLT_rt_close")
    cc_intrinsic("read", "i p i", "i", "VOLT_rt_read")
    cc_intrinsic("brk", "i", "p", "VOLT_rt_brk")
    cc_intrinsic("sin cos tan log2 sqrt", "f", "f", "")
    cc_intrinsic("atan2", "f f", "f", "")
    cc_intrinsic("abs", "n", "n", "")
    cc_intrinsic("min max", "n n", "n", "")
    cc_intrinsic("len", "a", "i", "")
    cc_k_vec_reserved = cv_or(cv_keys(cc_k_irtis), cv_asset(cv_split(cv_text("print put_int put_uint put_float put_char put_bool put_str nl str_len str_concat str_repeat"), 0, 0)))
    cc_k_scalar_type_names = cv_asset(cv_split(cv_text("i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 int uint float char bool string"), 0, 0))
    cc_k_int_arg_regs = cv_split(cv_text("rdi rsi rdx rcx r8 r9"), 0, 0)
    cc_k_wmap = cv_dict()
    cv_set(cc_k_wmap, cv_i(1), cv_text("byte"))
    cv_set(cc_k_wmap, cv_i(2), cv_text("word"))
    cv_set(cc_k_wmap, cv_i(4), cv_text("dword"))
    cv_set(cc_k_wmap, cv_i(8), cv_text("qword"))
    cc_k_subreg = cv_dict()
    let spell: i64 = cv_split(cv_text("dil di edi rdi;sil si esi rsi;dl dx edx rdx;cl cx ecx rcx;r8b r8w r8d r8;r9b r9w r9d r9"), cv_text(";"), 0)
    for i in 0..6:
        let row: i64 = cv_split(cv_at(spell, i), 0, 0)
        let sizes: i64 = cv_dict()
        for j in 0..4: cv_set(sizes, cv_i(1 << j), cv_at(row, j))
        cv_set(cc_k_subreg, cv_at(cc_k_int_arg_regs, i), sizes)

unsafe fn cc_display_args(args: i64) -> i64:
    let result: i64 = cv_list()
    for i in 0..cv_len(args): cv_push(result, cc_display(cv_at(args, i)))
    return cv_join(cv_text(", "), result)

unsafe fn cc_bracket(left: string, value: i64, right: string) -> i64:
    return cv_cat(cv_cat(cv_text(left), value), cv_text(right))

unsafe fn cc_display(t: i64) -> i64:
    let kind: i64 = cv_typename(t)
    if t == 0: return cv_text("void")
    if cv_name(kind, "TBool"): return cv_text("bool")
    if cv_name(kind, "TString"): return cv_text("string")
    if cv_name(kind, "TTypeVar") or cv_name(kind, "TEnum") or cv_name(kind, "TTaggedEnum"): return cv_getkey(t, "name")
    if cv_name(kind, "TInt"):
        let name: i64 = cv_getkey(t, "alias")
        if name != 0: return name
        let prefix: i64 = cv_text("u")
        if cv_truth(cv_getkey(t, "signed")): prefix = cv_text("i")
        return cv_cat(prefix, cv_str(cv_getkey(t, "bits")))
    if cv_name(kind, "TFloat"): return cv_cat(cv_text("f"), cv_str(cv_getkey(t, "bits")))
    if cv_name(kind, "TPtr"): return cc_bracket("ptr<", cc_display(cv_getkey(t, "elem")), ">")
    if cv_name(kind, "TSlice"):
        let prefix: i64 = cv_text("[]")
        if cv_truth(cv_getkey(t, "mutable")): prefix = cv_text("[]mut ")
        return cv_cat(prefix, cc_display(cv_getkey(t, "elem")))
    if cv_name(kind, "TArray"):
        return cv_cat(cc_bracket("[", cv_str(cv_getkey(t, "n")), ":"), cv_cat(cc_display(cv_getkey(t, "elem")), cv_text("]")))
    if cv_name(kind, "TFnPtr"):
        let desc: i64 = cc_bracket("fnptr<(", cc_display_args(cv_getkey(t, "params")), ")")
        let result: i64 = cv_getkey(t, "result")
        if result != 0: desc = cv_cat(desc, cv_cat(cv_text(" -> "), cc_display(result)))
        return cv_cat(desc, cv_text(">"))
    if cv_name(kind, "TStruct") or cv_name(kind, "TWrapper"):
        let args: i64 = cv_getkey(t, "args")
        let name: i64 = cv_get(t, cv_text("source_name"), cv_getkey(t, "name"))
        if cv_len(args) == 0: return name
        return cv_cat(name, cc_bracket("<", cc_display_args(args), ">"))
    return kind
