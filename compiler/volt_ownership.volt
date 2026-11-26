use volt_types

# Реестр владеющих типов. Каждая запись связывает struct с домашним файлом
# (только там разрешены ptr на владельца и reader-функции), функцией drop и
# типом-меткой, которая не даёт старому компилятору собрать модуль как
# копируемый.
unsafe fn cc_OwnerKind(v_title: string, v_name: string, v_file: i64, v_drop: string, v_guard: string, v_readers: i64) -> i64:
    let v_self: i64 = cv_node("OwnerKind")
    cv_field(v_self, "title", cv_text(v_title))
    cv_field(v_self, "name", cv_text(v_name))
    cv_field(v_self, "file", v_file)
    cv_field(v_self, "drop", cv_text(v_drop))
    cv_field(v_self, "guard", cv_text(v_guard))
    cv_field(v_self, "readers", v_readers)
    return v_self

unsafe fn cc_owner_kinds(sem: i64) -> i64:
    let buffer_readers: i64 = cv_list()
    cv_push(buffer_readers, cv_text("owned_buffer_len"))
    cv_push(buffer_readers, cv_text("owned_buffer_get"))
    cv_push(buffer_readers, cv_text("owned_buffer_bytes"))
    let fd_readers: i64 = cv_list()
    cv_push(fd_readers, cv_text("owned_fd_number"))
    cv_push(fd_readers, cv_text("read_into"))
    cv_push(fd_readers, cv_text("__volt_owned_fd_take"))
    let kinds: i64 = cv_list()
    cv_push(kinds, cc_OwnerKind("OwnedBuffer", "OwnedBuffer", cv_getkey(sem, "owned_buffer_file"), "__volt_owned_buffer_drop", "__VoltOwnedBufferV1", buffer_readers))
    cv_push(kinds, cc_OwnerKind("OwnedFd", "OwnedFd", cv_getkey(sem, "fs_file"), "__volt_owned_fd_close", "__VoltOwnedFdV1", fd_readers))
    return kinds

# Struct-объявление из реестра или 0.
unsafe fn cc_owner_kind_of_def(sem: i64, def: i64) -> i64:
    let file: i64 = cv_getkey(def, "file")
    let name: i64 = cv_getkey(def, "source_name")
    if name == 0: name = cv_getkey(def, "name")
    let kinds: i64 = cv_getkey(sem, "owned_kinds")
    for i in 0..cv_len(kinds):
        let kind: i64 = cv_at(kinds, i)
        if cv_equal(name, cv_getkey(kind, "name")) and cv_equal(file, cv_getkey(kind, "file")): return kind
    return 0

# В модуле имена получают префикс; сопоставляем обе формы.
unsafe fn cc_owner_name_match(sem: i64, kind: i64, name: i64, source: i64) -> bool:
    if cv_equal(name, source): return true
    let prog: i64 = cv_get(cv_getkey(sem, "module_files"), cv_getkey(kind, "file"), 0)
    if prog == 0: return false
    let prefix: i64 = cv_getkey(prog, "symbol_prefix")
    if prefix == 0: return false
    return cv_equal(name, cv_cat(prefix, source))

unsafe fn cc_owner_kind_of_drop(sem: i64, name: i64) -> i64:
    let kinds: i64 = cv_getkey(sem, "owned_kinds")
    for i in 0..cv_len(kinds):
        let kind: i64 = cv_at(kinds, i)
        if cc_owner_name_match(sem, kind, name, cv_getkey(kind, "drop")): return kind
    return 0

# Если target — reader-функция владеющего типа, возвращает его запись, иначе 0.
unsafe fn cc_owner_reader_kind(sem: i64, target: i64, name: i64) -> i64:
    if target == 0: return 0
    let file: i64 = cv_getkey(target, "file")
    let kinds: i64 = cv_getkey(sem, "owned_kinds")
    for i in 0..cv_len(kinds):
        let kind: i64 = cv_at(kinds, i)
        if not cv_equal(file, cv_getkey(kind, "file")): continue
        let readers: i64 = cv_getkey(kind, "readers")
        for j in 0..cv_len(readers):
            if cc_owner_name_match(sem, kind, name, cv_at(readers, j)): return kind
    return 0

# Домашний файл любого владеющего типа: там разрешён ptr на владельца.
unsafe fn cc_owner_home_file(sem: i64, file: i64) -> bool:
    let kinds: i64 = cv_getkey(sem, "owned_kinds")
    for i in 0..cv_len(kinds):
        if cv_equal(file, cv_getkey(cv_at(kinds, i), "file")): return true
    return false

# Тип-метка владеющего модуля: старый компилятор должен отвергнуть такой файл.
unsafe fn cc_owner_guard(sem: i64, name: i64, file: i64) -> bool:
    let kinds: i64 = cv_getkey(sem, "owned_kinds")
    for i in 0..cv_len(kinds):
        let kind: i64 = cv_at(kinds, i)
        if cv_equal(name, cv_getkey(kind, "guard")) and cv_equal(file, cv_getkey(kind, "file")): return true
    return false

unsafe fn cc_is_owned_struct(typ: i64) -> bool:
    return cv_truth(cv_getkey(typ, "owner_kind"))

unsafe fn cc_is_owned_result(typ: i64) -> bool:
    return cv_truth(cv_getkey(typ, "owned_ok"))

unsafe fn cc_is_owned(typ: i64) -> bool:
    return cc_is_owned_struct(typ) or cc_is_owned_result(typ)

unsafe fn cc_is_owned_ptr(typ: i64) -> bool:
    return cv_classes(typ, "TPtr") and cc_is_owned(cv_getkey(typ, "elem"))

# Домашний файл конкретного владеющего типа (0 для невладеющего).
unsafe fn cc_owned_home(typ: i64) -> i64:
    let kind: i64 = cv_getkey(typ, "owner_kind")
    if kind != 0: return cv_getkey(kind, "file")
    if cc_is_owned_result(typ): return cc_owned_home(cv_at(cv_getkey(typ, "args"), 0))
    return 0

unsafe fn cc_owner_title(typ: i64) -> i64:
    let kind: i64 = cv_getkey(typ, "owner_kind")
    if kind == 0 and cc_is_owned_result(typ): kind = cv_getkey(cv_at(cv_getkey(typ, "args"), 0), "owner_kind")
    if kind == 0: return cv_text("владелец")
    return cv_getkey(kind, "title")

# shortcut: drop есть только у типов из реестра cc_owner_kinds и их прямых
# Result/Option; владельцам внутри struct, массивов и вложенных обёрток
# по-прежнему нужна модель мест (place model).
unsafe fn ccs_check_ownership(sem: i64, fn_def: i64):
    if not cv_truth(cv_getkey(sem, "has_owned")): return
    let flow: i64 = cv_node("Ownership")
    cv_field(flow, "sem", sem)
    cv_field(flow, "file", cv_getkey(fn_def, "file"))
    cv_field(flow, "trusted", cv_bool(cc_owner_home_file(sem, cv_getkey(fn_def, "file"))))
    cv_field(flow, "frames", cv_list())
    cv_field(flow, "loops", cv_list())
    cv_field(flow, "pinned", cv_vector(CV_SET))
    # Слоты владельцев, чьи байты заимствует живой срез (owned_buffer_bytes):
    # пин действует до конца блока, как заимствование массива срезом.
    cv_field(flow, "slice_borrows", cv_vector(CV_SET))
    let scopes: i64 = cv_dict()
    cv_field(flow, "scopes", scopes)
    cv_field(fn_def, "owner_scopes", scopes)
    cc_owned_block(flow, cv_getkey(fn_def, "body"), cv_dict(), 0)

# message — уже CV-текст (cv_text/cv_cat), чтобы подставлять имя типа.
unsafe fn cc_owned_error(flow: i64, node: i64, message: i64):
    cc_error_at(message, cv_getkey(flow, "file"), cv_getkey(node, "line"), cc_node_column(node))

unsafe fn cc_owned_after_move(flow: i64, node: i64, slot: i64, move: i64):
    let title: i64 = cc_owner_title(cv_getkey(slot, "typ"))
    cc_error_note(cv_cat(title, cv_text(" использован после переноса")), cv_getkey(flow, "file"), node, cv_text("перенесён здесь"), move)

unsafe fn cc_owned_slot(flow: i64, slot: i64):
    let sem: i64 = cv_getkey(flow, "sem")
    let frames: i64 = cv_getkey(flow, "frames")
    let flag: i64 = ccs_declare_temp(sem, cc_int(CV_FALSE, cv_i(64)), cv_getkey(slot, "line"))
    cv_field(slot, "owner_flag", flag)
    cv_field(slot, "owner_depth", cv_length(frames))
    cv_push(cv_at(frames, -1), slot)

const CC_OWNER_VALUE: i64 = 0
const CC_OWNER_MOVE: i64 = 1

unsafe fn cc_owned_temporary(flow: i64, expr: i64):
    let slots: i64 = cv_getkey(cv_getkey(flow, "sem"), "slots")
    let slot: i64 = cv_subscript(slots, cv_getkey(expr, "temp_slot"))
    cc_owned_slot(flow, slot)
    cv_field(expr, "owner_result", slot)
    cv_field(expr, "owner_transfer", slot)

unsafe fn cc_owned_expr(flow: i64, moved: i64, expr: i64, use_kind: i64):
    if expr == 0: return
    let typ: i64 = cv_getkey(expr, "type")
    let slot: i64 = cv_getkey(expr, "slot")
    let deferred: bool = cv_truth(cv_getkey(flow, "deferred"))
    if cc_is_owned(typ):
        let title: i64 = cc_owner_title(typ)
        if use_kind == CC_OWNER_VALUE: cc_owned_error(flow, expr, cv_cat(title, cv_text(" нельзя копировать или использовать здесь")))
        if deferred: cc_owned_error(flow, expr, cv_cat(cv_text("defer не может переносить или создавать "), title))
        if cv_classes(expr, "VarRef"):
            if slot == 0: cc_owned_error(flow, expr, cv_cat(title, cv_text(" использован после переноса")))
            let move: i64 = cv_get(moved, cv_i(slot), 0)
            if move != 0: cc_owned_after_move(flow, expr, slot, move)
            if cv_contains(cv_getkey(flow, "slice_borrows"), cv_i(slot)):
                cc_owned_error(flow, expr, cv_cat(title, cv_text(" нельзя перенести, пока срез заимствует его байты")))
            if cv_contains(cv_getkey(flow, "pinned"), cv_i(slot)) or cv_contains(cv_getkey(flow, "call_reads"), cv_i(slot)):
                cc_owned_error(flow, expr, cv_cat(title, cv_text(" нельзя перенести, пока он заимствован вызовом или defer")))
            cv_set(moved, cv_i(slot), expr)
            cv_field(expr, "owner_transfer", slot)
            return
        if cv_classes(expr, "Unary") and cv_name(cv_getkey(expr, "op"), "?"):
            cc_owned_expr(flow, moved, cv_getkey(expr, "x"), CC_OWNER_MOVE)
            cc_owned_temporary(flow, expr)
            return
        if not cv_classes(expr, "Call"): cc_owned_error(flow, expr, cv_cat(title, cv_text(" можно перенести только целиком")))
    if cc_is_owned_ptr(typ) and not cv_truth(cv_getkey(flow, "trusted")):
        cc_owned_error(flow, expr, cv_cat(cv_text("адрес "), cv_cat(cc_owner_title(cv_getkey(typ, "elem")), cv_text(" допустим только как аргумент reader-функций его модуля"))))
    if cv_classes(expr, "Call"):
        if cv_has(expr, cv_text("callback_target")): return
        let name: i64 = cv_getkey(expr, "name")
        let sem: i64 = cv_getkey(flow, "sem")
        let target: i64 = cv_get(cv_getkey(sem, "fns"), name, 0)
        let reader: i64 = cc_owner_reader_kind(sem, target, name)
        let args: i64 = cv_getkey(expr, "args")
        let old_reads: i64 = cv_getkey(flow, "call_reads")
        cc_owned_expr(flow, moved, cv_getkey(expr, "indirect_callee"), CC_OWNER_VALUE)
        for i in 0..cv_len(args):
            let arg: i64 = cv_at(args, i)
            if reader != 0 and i == 0 and cv_classes(arg, "AddrOf"):
                let owner: i64 = cv_getkey(arg, "x")
                let owner_slot: i64 = cv_getkey(owner, "slot")
                if owner_slot == 0 or cv_getkey(cv_getkey(owner_slot, "typ"), "owner_kind") != reader:
                    cc_owned_error(flow, arg, cv_cat(cv_text("требуется адрес локального "), cv_getkey(reader, "title")))
                let move: i64 = cv_get(moved, cv_i(owner_slot), 0)
                if move != 0: cc_owned_after_move(flow, owner, owner_slot, move)
                let reads: i64 = cv_vector(CV_SET)
                cv_add_set(reads, cv_i(owner_slot))
                if old_reads != 0: reads = cv_or(old_reads, reads)
                cv_field(flow, "call_reads", reads)
                if deferred: cv_add_set(cv_getkey(flow, "pinned"), cv_i(owner_slot))
            else:
                cc_owned_expr(flow, moved, arg, CC_OWNER_MOVE)
        cv_field(flow, "call_reads", old_reads)
        # Срез из reader-функции владельца удерживает его до конца блока,
        # а не только на время вызова.
        let borrow: i64 = cv_get(expr, cv_text("owner_slice_borrow"), 0)
        if borrow != 0: cv_add_set(cv_getkey(flow, "slice_borrows"), cv_i(borrow))
        if cc_is_owned(typ) and not cv_name(cv_getkey(expr, "kindt"), "ctor"):
            cc_owned_temporary(flow, expr)
        return
    if cv_classes(expr, "Member"):
        if not cv_has(expr, cv_text("enum_value")) and not cv_has(expr, cv_text("const_binding")) and not cc_is_sum_ctor(expr):
            cc_owned_expr(flow, moved, cv_getkey(expr, "base"), CC_OWNER_VALUE)
    elif cv_classes(expr, "Unary") or cv_classes(expr, "Cast") or cv_classes(expr, "AddrOf") or cv_classes(expr, "Deref"):
        cc_owned_expr(flow, moved, cv_getkey(expr, "x"), CC_OWNER_VALUE)
    elif cv_classes(expr, "Binary"):
        let left: i64 = cv_getkey(expr, "l")
        let right: i64 = cv_getkey(expr, "r")
        cc_owned_expr(flow, moved, left, CC_OWNER_VALUE)
        let known: i64 = cc_literal_condition(left)
        let op: i64 = cv_getkey(expr, "op")
        if (known == CV_FALSE and cv_name(op, "and")) or (known == CV_TRUE and cv_name(op, "or")):
            # Set up the dead operand for lowering without committing its loans or moves.
            let pinned: i64 = cv_getkey(flow, "pinned")
            let borrows: i64 = cv_getkey(flow, "slice_borrows")
            let pin_count: i64 = cv_len(pinned)
            let borrow_count: i64 = cv_len(borrows)
            cc_owned_expr(flow, cc_owned_snapshot(moved), right, CC_OWNER_VALUE)
            while cv_len(pinned) > pin_count: cv_pop(pinned)
            while cv_len(borrows) > borrow_count: cv_pop(borrows)
        else:
            cc_owned_expr(flow, moved, right, CC_OWNER_VALUE)
    elif cv_classes(expr, "Index") or cv_classes(expr, "SliceExpr"):
        cc_owned_expr(flow, moved, cv_getkey(expr, "base"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(expr, "idx"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(expr, "start"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(expr, "end"), CC_OWNER_VALUE)

unsafe fn cc_owned_block(flow: i64, body: i64, moved: i64, entry: i64) -> bool:
    let frames: i64 = cv_getkey(flow, "frames")
    let frame: i64 = cv_list()
    let pinned: i64 = cv_getkey(flow, "pinned")
    let pin_count: i64 = cv_len(pinned)
    let borrows: i64 = cv_getkey(flow, "slice_borrows")
    let borrow_count: i64 = cv_len(borrows)
    cv_push(frames, frame)
    if cv_len(frames) == 1:
        let slots: i64 = cv_getkey(cv_getkey(flow, "sem"), "slots")
        let count: i64 = cv_len(slots)
        for i in 0..count:
            let slot: i64 = cv_at(slots, i)
            if cv_name(cv_getkey(slot, "kind"), "param") and cc_is_owned(cv_getkey(slot, "typ")): cc_owned_slot(flow, slot)
    if entry != 0:
        cc_owned_slot(flow, entry)
        cv_field(entry, "owner_at_entry", CV_TRUE)
    let falls_through: bool = true
    for i in 0..cv_len(body):
        if not cc_owned_stmt(flow, cv_at(body, i), moved):
            falls_through = false
            break
    for i in 0..cv_len(frame): cv_remove(moved, cv_i(cv_at(frame, i)))
    while cv_len(pinned) > pin_count: cv_pop(pinned)
    while cv_len(borrows) > borrow_count: cv_pop(borrows)
    cv_pop(frames)
    if cv_len(frame) != 0: cv_set(cv_getkey(flow, "scopes"), cv_i(body), frame)
    return falls_through

# Each moved slot carries one origin from a path that reaches this point.
unsafe fn cc_owned_snapshot(moved: i64) -> i64:
    let copy: i64 = cv_dict()
    cv_update(copy, moved)
    return copy

unsafe fn cc_owned_join(dst: i64, source: i64):
    for i in 0..cv_len(source):
        let id: i64 = cv_at(source, i)
        if not cv_has(dst, id): cv_set(dst, id, cv_get(source, id, 0))

unsafe fn cc_owned_backedge(flow: i64, node: i64, loop: i64, moved: i64):
    let before: i64 = cv_at(loop, 0)
    let depth: i64 = cv_at(loop, 2)
    for i in 0..cv_len(moved):
        let id: i64 = cv_at(moved, i)
        if cv_le(cv_getkey(cv_index(id), "owner_depth"), depth) and not cv_has(before, id):
            cc_owned_error(flow, node, cv_cat(cc_owner_title(cv_getkey(cv_index(id), "typ")), cv_text(" из внешней области может быть повторно использован на следующей итерации")))

unsafe fn cc_owned_stmt(flow: i64, stmt: i64, moved: i64) -> bool:
    if cv_classes(stmt, "LetStmt"):
        let slot: i64 = cv_at(cv_getkey(cv_getkey(flow, "sem"), "slots"), cv_index(cv_getkey(stmt, "slot")))
        let init: i64 = cv_getkey(stmt, "init")
        if cc_is_owned(cv_getkey(slot, "typ")):
            if init == 0: cc_owned_error(flow, stmt, cv_cat(cc_owner_title(cv_getkey(slot, "typ")), cv_text(" требует инициализатор")))
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
        let expr: i64 = cv_getkey(stmt, "expr")
        cc_owned_expr(flow, moved, expr, CC_OWNER_MOVE)
        if cv_truth(cv_getkey(expr, "no_return")): return false
    elif cv_classes(stmt, "ReturnStmt"):
        cc_owned_expr(flow, moved, cv_getkey(stmt, "value"), CC_OWNER_MOVE)
        return false
    elif cv_classes(stmt, "UnsafeStmt"):
        return cc_owned_block(flow, cv_getkey(stmt, "body"), moved, 0)
    elif cv_classes(stmt, "IfStmt"):
        let arms: i64 = cv_getkey(stmt, "conds")
        let merged: i64 = cv_dict()
        let flows: bool = false
        let can_reach: bool = true
        let dead: i64 = cv_getkey(flow, "dead_branch")
        let borrows: i64 = cv_getkey(flow, "slice_borrows")
        for i in 0..cv_len(arms):
            let arm: i64 = cv_at(arms, i)
            let cond: i64 = cv_at(arm, 0)
            let known: i64 = cc_literal_condition(cond)
            let borrow_count: i64 = cv_len(borrows)
            cc_owned_expr(flow, moved, cond, CC_OWNER_VALUE)
            let branch: i64 = cc_owned_snapshot(moved)
            let reachable: bool = can_reach and known != CV_FALSE
            # Still check and lower dead arms, but do not let their exits affect live paths.
            cv_field(flow, "dead_branch", cv_bool(cv_truth(dead) or not reachable))
            if cc_owned_block(flow, cv_at(arm, 1), branch, 0) and reachable:
                flows = true
                cc_owned_join(merged, branch)
            if not can_reach:
                while cv_len(borrows) > borrow_count: cv_pop(borrows)
            if known == CV_TRUE: can_reach = false
        cv_field(flow, "dead_branch", cv_bool(cv_truth(dead) or not can_reach))
        if cc_owned_block(flow, cv_getkey(stmt, "els"), moved, 0) and can_reach:
            flows = true
            cc_owned_join(merged, moved)
        cv_field(flow, "dead_branch", dead)
        while cv_len(moved) > 0: cv_remove(moved, cv_at(moved, -1))
        cv_update(moved, merged)
        return flows
    elif cv_classes(stmt, "MatchStmt"):
        let value: i64 = cv_getkey(stmt, "value")
        let typ: i64 = cv_getkey(value, "type")
        let owned: bool = cc_is_owned_result(typ)
        let mode: i64 = CC_OWNER_VALUE
        if owned: mode = CC_OWNER_MOVE
        cc_owned_expr(flow, moved, value, mode)
        let arms: i64 = cv_getkey(stmt, "arms")
        let merged: i64 = cv_dict()
        let flows: bool = false
        let sem: i64 = cv_getkey(flow, "sem")
        for i in 0..cv_len(arms):
            let arm: i64 = cv_at(arms, i)
            let entry: i64 = 0
            if owned:
                let pattern: i64 = cv_getkey(arm, "pattern")
                if cv_name(pattern, "Ok") or cv_name(pattern, "Some"):
                    entry = cv_subscript(cv_getkey(sem, "slots"), cv_getkey(arm, "binding_slot"))
                elif cv_name(pattern, "_"):
                    # Keep an ignored Ok alive until the arm has run its defers.
                    let id: i64 = ccs_declare_temp(sem, typ, cv_getkey(arm, "line"))
                    entry = cv_subscript(cv_getkey(sem, "slots"), id)
                    cv_field(arm, "owner_discard", entry)
            let branch: i64 = cc_owned_snapshot(moved)
            if cc_owned_block(flow, cv_getkey(arm, "body"), branch, entry):
                flows = true
                cc_owned_join(merged, branch)
        cc_owned_join(moved, merged)
        return flows
    elif cv_classes(stmt, "ForStmt") or cv_classes(stmt, "WhileStmt"):
        let loops: i64 = cv_getkey(flow, "loops")
        cc_owned_expr(flow, moved, cv_getkey(stmt, "start"), CC_OWNER_VALUE)
        cc_owned_expr(flow, moved, cv_getkey(stmt, "stop"), CC_OWNER_VALUE)
        let loop: i64 = cv_tuple()
        cv_push(loop, cc_owned_snapshot(moved))
        cv_push(loop, cv_dict())
        cv_push(loop, cv_length(cv_getkey(flow, "frames")))
        cv_push(loop, CV_FALSE)  # a reachable break, even if it moves nothing
        cv_push(loops, loop)
        let cond: i64 = cv_getkey(stmt, "cond")
        cc_owned_expr(flow, moved, cond, CC_OWNER_VALUE)
        let branch: i64 = cc_owned_snapshot(moved)
        let dead: i64 = cv_getkey(flow, "dead_branch")
        let unreachable: bool = cv_truth(dead) or cc_literal_condition(cond) == CV_FALSE
        cv_field(flow, "dead_branch", cv_bool(unreachable))
        if cc_owned_block(flow, cv_getkey(stmt, "body"), branch, 0) and not unreachable:
            cc_owned_backedge(flow, stmt, loop, branch)
        cv_field(flow, "dead_branch", dead)
        cc_owned_join(moved, cv_at(loop, 1))
        cv_pop(loops)
        if cc_literal_condition(cond) == CV_TRUE and not cv_truth(cv_at(loop, 3)): return false
    elif cv_classes(stmt, "BreakStmt") or cv_classes(stmt, "ContinueStmt"):
        if cv_truth(cv_getkey(flow, "dead_branch")): return false
        let loop: i64 = cv_at(cv_getkey(flow, "loops"), -1)
        if cv_classes(stmt, "ContinueStmt"): cc_owned_backedge(flow, stmt, loop, moved)
        else:
            cv_set(loop, cv_i(3), CV_TRUE)
            cc_owned_join(cv_at(loop, 1), moved)
        return false
    return true
