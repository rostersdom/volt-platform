use volt_types

unsafe fn cc_is_owned(typ: i64) -> bool:
    return cv_truth(cv_getkey(typ, "owned_buffer"))

unsafe fn cc_is_owned_ptr(typ: i64) -> bool:
    return cv_classes(typ, "TPtr") and cc_is_owned(cv_getkey(typ, "elem"))

# shortcut: only the vstd OwnedBuffer has drop; user-defined and partially moved owners need a general place model.
unsafe fn ccs_check_ownership(sem: i64, fn_def: i64):
    if not cv_truth(cv_getkey(sem, "has_owned_buffer")): return
    let flow: i64 = cv_node("Ownership")
    cv_field(flow, "sem", sem)
    cv_field(flow, "file", cv_getkey(fn_def, "file"))
    cv_field(flow, "trusted", cv_bool(cv_equal(cv_getkey(fn_def, "file"), cv_getkey(sem, "owned_buffer_file"))))
    cv_field(flow, "frames", cv_list())
    cv_field(flow, "loops", cv_list())
    cv_field(flow, "pinned", cv_vector(CV_SET))
    let scopes: i64 = cv_dict()
    cv_field(flow, "scopes", scopes)
    cv_field(fn_def, "owner_scopes", scopes)
    cc_owned_block(flow, cv_getkey(fn_def, "body"), cv_vector(CV_SET))

unsafe fn cc_owned_error(flow: i64, node: i64, message: string):
    cc_error(cv_text(message), cv_getkey(flow, "file"), cv_getkey(node, "line"))

unsafe fn cc_owned_slot(flow: i64, slot: i64):
    let sem: i64 = cv_getkey(flow, "sem")
    let frames: i64 = cv_getkey(flow, "frames")
    let flag: i64 = ccs_declare_temp(sem, cc_int(CV_FALSE, cv_i(64)), cv_getkey(slot, "line"))
    cv_field(slot, "owner_flag", flag)
    cv_field(slot, "owner_depth", cv_length(frames))
    cv_push(cv_at(frames, -1), slot)

const CC_OWNER_VALUE: i64 = 0
const CC_OWNER_MOVE: i64 = 1

unsafe fn cc_owned_expr(flow: i64, moved: i64, expr: i64, use_kind: i64):
    if expr == 0: return
    let typ: i64 = cv_getkey(expr, "type")
    let slot: i64 = cv_getkey(expr, "slot")
    let deferred: bool = cv_truth(cv_getkey(flow, "deferred"))
    if cc_is_owned(typ):
        if use_kind == CC_OWNER_VALUE: cc_owned_error(flow, expr, "OwnedBuffer нельзя копировать или использовать здесь")
        if deferred: cc_owned_error(flow, expr, "defer не может переносить или создавать OwnedBuffer")
        if cv_classes(expr, "VarRef"):
            if slot == 0 or cv_contains(moved, cv_i(slot)): cc_owned_error(flow, expr, "OwnedBuffer использован после переноса")
            if cv_contains(cv_getkey(flow, "pinned"), cv_i(slot)) or cv_contains(cv_getkey(flow, "call_reads"), cv_i(slot)):
                cc_owned_error(flow, expr, "OwnedBuffer нельзя перенести, пока он заимствован вызовом или defer")
            cv_add_set(moved, cv_i(slot))
            cv_field(expr, "owner_transfer", slot)
            return
        if not cv_classes(expr, "Call"): cc_owned_error(flow, expr, "OwnedBuffer можно перенести только целиком")
    if cc_is_owned_ptr(typ) and not cv_truth(cv_getkey(flow, "trusted")):
        cc_owned_error(flow, expr, "адрес OwnedBuffer допустим только как аргумент owned_buffer_len/get")
    if cv_classes(expr, "Call"):
        if cv_has(expr, cv_text("callback_target")): return
        let name: i64 = cv_getkey(expr, "name")
        let sem: i64 = cv_getkey(flow, "sem")
        let target: i64 = cv_get(cv_getkey(sem, "fns"), name, 0)
        let reader: bool = (cv_name(name, "owned_buffer_len") or cv_name(name, "owned_buffer_get")) and cv_equal(cv_getkey(target, "file"), cv_getkey(sem, "owned_buffer_file"))
        let args: i64 = cv_getkey(expr, "args")
        let old_reads: i64 = cv_getkey(flow, "call_reads")
        cc_owned_expr(flow, moved, cv_getkey(expr, "indirect_callee"), CC_OWNER_VALUE)
        for i in 0..cv_len(args):
            let arg: i64 = cv_at(args, i)
            if reader and i == 0 and cv_classes(arg, "AddrOf"):
                let owner: i64 = cv_getkey(arg, "x")
                let owner_slot: i64 = cv_getkey(owner, "slot")
                if owner_slot == 0 or not cc_is_owned(cv_getkey(owner_slot, "typ")):
                    cc_owned_error(flow, arg, "требуется адрес локального OwnedBuffer")
                if cv_contains(moved, cv_i(owner_slot)):
                    cc_owned_error(flow, arg, "OwnedBuffer использован после переноса")
                let reads: i64 = cv_vector(CV_SET)
                cv_add_set(reads, cv_i(owner_slot))
                if old_reads != 0: reads = cv_or(old_reads, reads)
                cv_field(flow, "call_reads", reads)
                if deferred: cv_add_set(cv_getkey(flow, "pinned"), cv_i(owner_slot))
            else:
                cc_owned_expr(flow, moved, arg, CC_OWNER_MOVE)
        cv_field(flow, "call_reads", old_reads)
        if cc_is_owned(typ) and not cv_name(cv_getkey(expr, "kindt"), "ctor"):
            let temporary: i64 = cv_at(cv_getkey(sem, "slots"), cv_index(cv_getkey(expr, "temp_slot")))
            cc_owned_slot(flow, temporary)
            cv_field(expr, "owner_result", temporary)
            cv_field(expr, "owner_transfer", temporary)
        return
    if cv_classes(expr, "Member"):
        if not cv_has(expr, cv_text("enum_value")) and not cv_has(expr, cv_text("const_binding")) and not cc_is_sum_ctor(expr):
            cc_owned_expr(flow, moved, cv_getkey(expr, "base"), CC_OWNER_VALUE)
    elif cv_classes(expr, "Unary") or cv_classes(expr, "Cast") or cv_classes(expr, "AddrOf") or cv_classes(expr, "Deref"):
        cc_owned_expr(flow, moved, cv_getkey(expr, "x"), CC_OWNER_VALUE)
    elif cv_classes(expr, "Binary"):
        # Even a conditional RHS move makes the owner unavailable after this expression.
        cc_owned_expr(flow, moved, cv_getkey(expr, "l"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(expr, "r"), CC_OWNER_VALUE)
    elif cv_classes(expr, "Index") or cv_classes(expr, "SliceExpr"):
        cc_owned_expr(flow, moved, cv_getkey(expr, "base"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(expr, "idx"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(expr, "start"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(expr, "end"), CC_OWNER_VALUE)

unsafe fn cc_owned_block(flow: i64, body: i64, moved: i64) -> bool:
    let frames: i64 = cv_getkey(flow, "frames")
    let frame: i64 = cv_list()
    let pinned: i64 = cv_getkey(flow, "pinned")
    let pin_count: i64 = cv_len(pinned)
    cv_push(frames, frame)
    if cv_len(frames) == 1:
        let slots: i64 = cv_getkey(cv_getkey(flow, "sem"), "slots")
        let count: i64 = cv_len(slots)
        for i in 0..count:
            let slot: i64 = cv_at(slots, i)
            if cv_name(cv_getkey(slot, "kind"), "param") and cc_is_owned(cv_getkey(slot, "typ")): cc_owned_slot(flow, slot)
    let falls_through: bool = true
    for i in 0..cv_len(body):
        if not cc_owned_stmt(flow, cv_at(body, i), moved):
            falls_through = false
            break
    for i in 0..cv_len(frame): cv_remove(moved, cv_i(cv_at(frame, i)))
    while cv_len(pinned) > pin_count: cv_pop(pinned)
    cv_pop(frames)
    if cv_len(frame) != 0: cv_set(cv_getkey(flow, "scopes"), cv_i(body), frame)
    return falls_through

unsafe fn cc_owned_join(dst: i64, source: i64):
    for i in 0..cv_len(source): cv_add_set(dst, cv_at(source, i))

unsafe fn cc_owned_backedge(flow: i64, node: i64, loop: i64, moved: i64):
    let before: i64 = cv_at(loop, 0)
    let depth: i64 = cv_at(loop, 2)
    for i in 0..cv_len(moved):
        let id: i64 = cv_at(moved, i)
        if cv_le(cv_getkey(cv_index(id), "owner_depth"), depth) and not cv_contains(before, id):
            cc_owned_error(flow, node, "OwnedBuffer из внешней области может быть повторно использован на следующей итерации")

unsafe fn cc_owned_stmt(flow: i64, stmt: i64, moved: i64) -> bool:
    if cv_classes(stmt, "LetStmt"):
        let slot: i64 = cv_at(cv_getkey(cv_getkey(flow, "sem"), "slots"), cv_index(cv_getkey(stmt, "slot")))
        let init: i64 = cv_getkey(stmt, "init")
        if cc_is_owned(cv_getkey(slot, "typ")):
            if init == 0: cc_owned_error(flow, stmt, "OwnedBuffer требует инициализатор")
            cc_owned_expr(flow, moved, init, CC_OWNER_MOVE)
            cc_owned_slot(flow, slot)
        else:
            cc_owned_expr(flow, moved, init, CC_OWNER_VALUE)
            let items: i64 = cv_getkey(stmt, "aitems")
            for i in 0..cv_len(items): cc_owned_expr(flow, moved, cv_at(items, i), CC_OWNER_VALUE)
    elif cv_classes(stmt, "AssignStmt"):
        let lhs: i64 = cv_getkey(stmt, "target")
        let rhs: i64 = cv_getkey(stmt, "value")
        if cv_name(cv_getkey(stmt, "op"), "="):
            cc_owned_expr(flow, moved, rhs, CC_OWNER_VALUE)
            cc_owned_expr(flow, moved, lhs, CC_OWNER_VALUE)
        else:
            cc_owned_expr(flow, moved, lhs, CC_OWNER_VALUE)
            cc_owned_expr(flow, moved, rhs, CC_OWNER_VALUE)
    elif cv_classes(stmt, "DeferStmt"):
        cv_field(flow, "deferred", CV_TRUE)
        cc_owned_stmt(flow, cv_getkey(stmt, "action"), moved)
        cv_field(flow, "deferred", CV_FALSE)
    elif cv_classes(stmt, "ExprStmt"):
        cc_owned_expr(flow, moved, cv_getkey(stmt, "expr"), CC_OWNER_MOVE)
    elif cv_classes(stmt, "ReturnStmt"):
        cc_owned_expr(flow, moved, cv_getkey(stmt, "value"), CC_OWNER_MOVE)
        return false
    elif cv_classes(stmt, "UnsafeStmt"):
        return cc_owned_block(flow, cv_getkey(stmt, "body"), moved)
    elif cv_classes(stmt, "IfStmt"):
        let arms: i64 = cv_getkey(stmt, "conds")
        let merged: i64 = cv_vector(CV_SET)
        let flows: bool = false
        for i in 0..cv_len(arms):
            let arm: i64 = cv_at(arms, i)
            cc_owned_expr(flow, moved, cv_at(arm, 0), CC_OWNER_VALUE)
            let branch: i64 = cv_asset(moved)
            if cc_owned_block(flow, cv_at(arm, 1), branch):
                flows = true
                cc_owned_join(merged, branch)
        if cc_owned_block(flow, cv_getkey(stmt, "els"), moved):
            flows = true
            cc_owned_join(merged, moved)
        while cv_len(moved) > 0: cv_pop(moved)
        cc_owned_join(moved, merged)
        return flows
    elif cv_classes(stmt, "MatchStmt"):
        cc_owned_expr(flow, moved, cv_getkey(stmt, "value"), CC_OWNER_VALUE)
        let arms: i64 = cv_getkey(stmt, "arms")
        let merged: i64 = cv_vector(CV_SET)
        let flows: bool = false
        for i in 0..cv_len(arms):
            let branch: i64 = cv_asset(moved)
            if cc_owned_block(flow, cv_getkey(cv_at(arms, i), "body"), branch):
                flows = true
                cc_owned_join(merged, branch)
        cc_owned_join(moved, merged)
        return flows
    elif cv_classes(stmt, "ForStmt") or cv_classes(stmt, "WhileStmt"):
        let loops: i64 = cv_getkey(flow, "loops")
        cc_owned_expr(flow, moved, cv_getkey(stmt, "start"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(stmt, "stop"), CC_OWNER_VALUE)
        let loop: i64 = cv_tuple()
        cv_push(loop, cv_asset(moved))
        cv_push(loop, cv_vector(CV_SET))
        cv_push(loop, cv_length(cv_getkey(flow, "frames")))
        cv_push(loops, loop)
        cc_owned_expr(flow, moved, cv_getkey(stmt, "cond"), CC_OWNER_VALUE)
        let branch: i64 = cv_asset(moved)
        if cc_owned_block(flow, cv_getkey(stmt, "body"), branch): cc_owned_backedge(flow, stmt, loop, branch)
        cc_owned_join(moved, cv_at(loop, 1))
        cv_pop(loops)
    elif cv_classes(stmt, "BreakStmt") or cv_classes(stmt, "ContinueStmt"):
        let loop: i64 = cv_at(cv_getkey(flow, "loops"), -1)
        if cv_classes(stmt, "ContinueStmt"): cc_owned_backedge(flow, stmt, loop, moved)
        else: cc_owned_join(cv_at(loop, 1), moved)
        return false
    return true
