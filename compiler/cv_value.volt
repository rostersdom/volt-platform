use cv_number

struct CVValues:
    kind: i64
    len: i64
    cap: i64
    values: ptr<i64>
    name: i64
    slots: ptr<i64>
    slot_count: i64

unsafe fn cv_vector(kind: i64) -> i64:
    let p: ptr<CVValues> = cv_alloc(sizeof(CVValues)) as ptr<CVValues>
    p.kind = kind
    return p as i64

unsafe fn cv_list() -> i64:
    return cv_vector(CV_LIST)

unsafe fn cv_tuple() -> i64:
    return cv_vector(CV_TUPLE)

unsafe fn cv_dict() -> i64:
    return cv_vector(CV_DICT)

unsafe fn cv_node(kind: string) -> i64:
    let p: ptr<CVValues> = cv_vector(CV_NODE) as ptr<CVValues>
    p.name = cv_text(kind)
    return p as i64

unsafe fn cv_reserve(v: ptr<CVValues>, count: i64):
    if count <= v.cap: return
    let cap: i64 = max(count, max(4, v.cap * 2))
    let next: ptr<i64> = cv_alloc(cap * 8) as ptr<i64>
    if v.len != 0: cv_copy(next as ptr<char>, v.values as ptr<char>, v.len * 8)
    v.values = next
    v.cap = cap

unsafe fn cv_push(v: i64, x: i64):
    let p: ptr<CVValues> = v as ptr<CVValues>
    cv_reserve(p, p.len + 1)
    p.values[p.len] = x
    p.len += 1

unsafe fn cv_len(v: i64) -> i64:
    let k: i64 = cv_kind(v)
    if k == 0: return 0
    if k == CV_TEXT or k == CV_NUL: return cv_text_len(v)
    if k == CV_DICT or k == CV_NODE: return (v as ptr<CVValues>).len / 2
    if k >= CV_LIST and k <= CV_SET: return (v as ptr<CVValues>).len
    panic("volt: compiler expected a collection\n")
    return 0

unsafe fn cv_length(v: i64) -> i64:
    return cv_i(cv_len(v))

unsafe fn cv_truth(v: i64) -> bool:
    let k: i64 = cv_kind(v)
    if k == 0 or k == CV_FALSE: return false
    if k == CV_NUMBER: return v != CV_NUMBER
    if k == CV_REAL: return cv_fbits(cv_real_value(v)) & 0x7fffffffffffffff != 0
    if (k >= CV_LIST and k <= CV_SET) or k == CV_TEXT or k == CV_NUL: return cv_len(v) != 0
    return true

unsafe fn cv_at(v: i64, index: i64) -> i64:
    let k: i64 = cv_kind(v)
    let i: i64 = index
    let n: i64 = cv_len(v)
    if i < 0: i += n
    if i < 0 or i >= n: panic("volt: compiler collection index out of bounds\n")
    if k == CV_TEXT or k == CV_NUL: return cv_char(cv_byte(v, i) as i64)
    if k == CV_DICT or k == CV_NODE: return (v as ptr<CVValues>).values[i * 2]
    return (v as ptr<CVValues>).values[i]

unsafe fn cv_pop(v: i64) -> i64:
    let p: ptr<CVValues> = v as ptr<CVValues>
    if p.len == 0: panic("volt: empty compiler sequence\n")
    p.len -= 1
    return p.values[p.len]

unsafe fn cv_classes(v: i64, name: string) -> bool:
    let k: i64 = cv_kind(v)
    if k == CV_NODE:
        let tag: i64 = (v as ptr<CVValues>).name
        return cv_name(tag, name) or (cv_name(cv_text(name), "TInt") and cv_name(tag, "TEnum"))
    if k == CV_NUMBER or k == CV_BIG or k == CV_FALSE or k == CV_TRUE:
        return cv_name(cv_text(name), "int") or ((k == CV_FALSE or k == CV_TRUE) and cv_name(cv_text(name), "bool"))
    if k == CV_REAL: return cv_name(cv_text(name), "float")
    if k == CV_TEXT or k == CV_NUL: return cv_name(cv_text(name), "str")
    if k == CV_LIST: return cv_name(cv_text(name), "list")
    if k == CV_TUPLE: return cv_name(cv_text(name), "tuple")
    if k == CV_DICT: return cv_name(cv_text(name), "dict")
    if k == CV_SET: return cv_name(cv_text(name), "set")
    return false

unsafe fn cv_typename(v: i64) -> i64:
    let k: i64 = cv_kind(v)
    if k == CV_NODE: return (v as ptr<CVValues>).name
    if k == CV_LIST: return cv_text("list")
    if k == CV_TUPLE: return cv_text("tuple")
    if k == CV_DICT: return cv_text("dict")
    if k == CV_SET: return cv_text("set")
    if k == CV_TEXT or k == CV_NUL: return cv_text("str")
    if k == CV_REAL: return cv_text("float")
    if k == CV_NUMBER or k == CV_BIG: return cv_text("int")
    if k == CV_FALSE or k == CV_TRUE: return cv_text("bool")
    return cv_text("NoneType")

# A sparse index for large string dictionaries (notably the ELF symbol table).
# Keep the dense entries so deterministic iteration doesn't depend on hashing.
unsafe fn cv_hash_text(key: i64) -> i64:
    let text: ptr<char> = cv_cptr(key)
    let hash: i64 = 5381
    let i: i64 = 0
    while text[i] != '\0':
        hash = ((hash * 33) ^ (text[i] as i64)) & 0x7fffffff
        i += 1
    return hash

unsafe fn cv_lookup(p: ptr<CVValues>, key: i64) -> i64:
    let mask: i64 = p.slot_count - 1
    let slot: i64 = cv_hash_text(key) & mask
    while p.slots[slot] != 0:
        let entry: i64 = p.slots[slot] - 1
        if cv_text_cmp(p.values[entry], key) == 0: break
        slot = (slot + 1) & mask
    return slot

unsafe fn cv_reindex(p: ptr<CVValues>, count: i64):
    p.slots = cv_alloc(count * 8) as ptr<i64>
    p.slot_count = count
    for i in 0..p.len / 2:
        let key: i64 = p.values[2 * i]
        if cv_istext(key): p.slots[cv_lookup(p, key)] = 2 * i + 1

unsafe fn cv_pos(v: i64, key: i64) -> i64:
    if v == 0: return -1
    let p: ptr<CVValues> = v as ptr<CVValues>
    if p.slot_count != 0 and cv_istext(key): return p.slots[cv_lookup(p, key)] - 1
    let step: i64 = 2
    if p.kind == CV_SET: step = 1
    let i: i64 = 0
    while i < p.len:
        if cv_equal(p.values[i], key): return i
        i += step
    return -1

unsafe fn cv_get(v: i64, key: i64, fallback: i64) -> i64:
    if v == 0: return fallback
    if cv_kind(v) == CV_DICT or cv_kind(v) == CV_NODE:
        let i: i64 = cv_pos(v, key)
        if i < 0: return fallback
        return (v as ptr<CVValues>).values[i + 1]
    return cv_at(v, cv_index(key))

unsafe fn cv_getkey(v: i64, key: string) -> i64:
    return cv_get(v, cv_text(key), 0)

unsafe fn cv_has(v: i64, key: i64) -> bool:
    return cv_pos(v, key) >= 0

unsafe fn cv_set(v: i64, key: i64, x: i64):
    let p: ptr<CVValues> = v as ptr<CVValues>
    if p.kind == CV_DICT or p.kind == CV_NODE:
        let i: i64 = cv_pos(v, key)
        if i >= 0:
            p.values[i + 1] = x
        else:
            cv_push(v, key)
            cv_push(v, x)
            if p.kind == CV_DICT and p.len >= 32:
                if p.slot_count == 0: cv_reindex(p, 64)
                elif p.len > p.slot_count: cv_reindex(p, 2 * p.slot_count)
                elif cv_istext(key): p.slots[cv_lookup(p, key)] = p.len - 1
    else:
        let i: i64 = cv_index(key)
        if i < 0: i += p.len
        if i < 0 or i >= p.len: panic("volt: compiler collection index out of bounds\n")
        p.values[i] = x

unsafe fn cv_field(v: i64, key: string, x: i64):
    cv_set(v, cv_text(key), x)

unsafe fn cv_add_set(v: i64, x: i64):
    if not cv_has(v, x): cv_push(v, x)

unsafe fn cv_remove(v: i64, x: i64):
    let i: i64 = cv_pos(v, x)
    if i < 0: return
    let p: ptr<CVValues> = v as ptr<CVValues>
    let step: i64 = 2
    if p.kind == CV_SET: step = 1
    p.len -= step
    while i < p.len:
        p.values[i] = p.values[i + step]
        i += 1
    if p.slot_count != 0: cv_reindex(p, p.slot_count)

unsafe fn cv_type_eq(a: i64, b: i64, name: i64) -> bool:
    if cv_name(name, "TInt"):
        return cv_equal(cv_getkey(a, "bits"), cv_getkey(b, "bits")) and cv_equal(cv_getkey(a, "signed"), cv_getkey(b, "signed")) and cv_equal(cv_getkey(a, "alias"), cv_getkey(b, "alias"))
    if cv_name(name, "TFloat"): return cv_equal(cv_getkey(a, "bits"), cv_getkey(b, "bits"))
    if cv_name(name, "TPtr"): return cv_equal(cv_getkey(a, "elem"), cv_getkey(b, "elem"))
    if cv_name(name, "TSlice"):
        return cv_equal(cv_getkey(a, "elem"), cv_getkey(b, "elem")) and cv_equal(cv_getkey(a, "mutable"), cv_getkey(b, "mutable"))
    if cv_name(name, "TArray"):
        return cv_equal(cv_getkey(a, "elem"), cv_getkey(b, "elem")) and cv_equal(cv_getkey(a, "n"), cv_getkey(b, "n"))
    if cv_name(name, "TFnPtr"):
        return cv_equal(cv_getkey(a, "params"), cv_getkey(b, "params")) and cv_equal(cv_getkey(a, "result"), cv_getkey(b, "result"))
    if cv_name(name, "TStruct") or cv_name(name, "TWrapper"):
        return cv_equal(cv_getkey(a, "name"), cv_getkey(b, "name")) and cv_equal(cv_getkey(a, "args"), cv_getkey(b, "args"))
    if cv_name(name, "TEnum") or cv_name(name, "TTypeVar"): return cv_equal(cv_getkey(a, "name"), cv_getkey(b, "name"))
    return cv_name(name, "TBool") or cv_name(name, "TString")

unsafe fn cv_numeric(k: i64) -> bool:
    return k == CV_NUMBER or k == CV_BIG or k == CV_REAL or k == CV_TRUE or k == CV_FALSE

unsafe fn cv_equal(a: i64, b: i64) -> bool:
    if a == b:
        if cv_kind(a) == CV_REAL: return cv_numcmp(a, b) == 0
        return true
    let ka: i64 = cv_kind(a)
    let kb: i64 = cv_kind(b)
    if (ka == CV_TEXT or ka == CV_NUL) and (kb == CV_TEXT or kb == CV_NUL): return cv_text_cmp(a, b) == 0
    if cv_numeric(ka) and cv_numeric(kb): return cv_numcmp(a, b) == 0
    if ka != kb: return false
    if ka == CV_LIST or ka == CV_TUPLE:
        if cv_len(a) != cv_len(b): return false
        for i in 0..cv_len(a):
            if not cv_equal(cv_at(a, i), cv_at(b, i)): return false
        return true
    if ka == CV_SET:
        return cv_len(a) == cv_len(b) and cv_subset(a, b)
    if ka == CV_NODE:
        let name: i64 = (a as ptr<CVValues>).name
        return cv_equal(name, (b as ptr<CVValues>).name) and cv_type_eq(a, b, name)
    return false

unsafe fn cv_subset(a: i64, b: i64) -> bool:
    for i in 0..cv_len(a):
        if not cv_has(b, cv_at(a, i)): return false
    return true

unsafe fn cv_less(a: i64, b: i64) -> bool:
    if cv_istext(a): return cv_text_cmp(a, b) < 0
    return cv_numcmp(a, b) < 0

unsafe fn cv_le(a: i64, b: i64) -> bool:
    if cv_kind(a) == CV_SET and cv_kind(b) == CV_SET: return cv_subset(a, b)
    return cv_equal(a, b) or cv_less(a, b)

unsafe fn cv_find(v: i64, part: i64, start: i64) -> i64:
    let n: i64 = cv_text_len(part)
    let end: i64 = cv_text_len(v) - n
    if start < 0 or start > end: return -1
    let p: ptr<char> = cv_cptr(v)
    let q: ptr<char> = cv_cptr(part)
    for at in start..=end:
        let i: i64 = 0
        while i < n and p[at + i] == q[i]: i += 1
        if i == n: return at
    return -1

unsafe fn cv_contains(v: i64, x: i64) -> bool:
    if cv_istext(v): return cv_find(v, x, 0) >= 0
    let k: i64 = cv_kind(v)
    if k == CV_SET or k == CV_DICT or k == CV_NODE: return cv_has(v, x)
    for i in 0..cv_len(v):
        if cv_equal(cv_at(v, i), x): return true
    return false

unsafe fn cv_subscript(v: i64, x: i64) -> i64:
    return cv_get(v, x, 0)

unsafe fn cv_extend(out: i64, v: i64):
    for i in 0..cv_len(v): cv_push(out, cv_at(v, i))

unsafe fn cv_seq(kind: i64, v: i64) -> i64:
    let out: i64 = cv_vector(kind)
    if kind == CV_SET:
        for i in 0..cv_len(v): cv_add_set(out, cv_at(v, i))
    else:
        cv_extend(out, v)
    return out

unsafe fn cv_aslist(v: i64) -> i64:
    return cv_seq(CV_LIST, v)

unsafe fn cv_astuple(v: i64) -> i64:
    return cv_seq(CV_TUPLE, v)

unsafe fn cv_asset(v: i64) -> i64:
    return cv_seq(CV_SET, v)

unsafe fn cv_add(a: i64, b: i64) -> i64:
    if cv_istext(a): return cv_cat(a, b)
    let k: i64 = cv_kind(a)
    if k == CV_LIST or k == CV_TUPLE:
        let out: i64 = cv_seq(k, a)
        cv_extend(out, b)
        return out
    return cv_numadd(a, b)

unsafe fn cv_sub(a: i64, b: i64) -> i64:
    if cv_kind(a) != CV_SET: return cv_numsub(a, b)
    let out: i64 = cv_vector(CV_SET)
    for i in 0..cv_len(a):
        let v: i64 = cv_at(a, i)
        if not cv_has(b, v): cv_push(out, v)
    return out

unsafe fn cv_and(a: i64, b: i64) -> i64:
    if cv_kind(a) != CV_SET: return cv_bitop(a, b, 0)
    let out: i64 = cv_vector(CV_SET)
    for i in 0..cv_len(a):
        let v: i64 = cv_at(a, i)
        if cv_has(b, v): cv_push(out, v)
    return out

unsafe fn cv_or(a: i64, b: i64) -> i64:
    if cv_kind(a) != CV_SET: return cv_bitop(a, b, 1)
    let out: i64 = cv_asset(a)
    for i in 0..cv_len(b): cv_add_set(out, cv_at(b, i))
    return out

unsafe fn cv_xor(a: i64, b: i64) -> i64:
    return cv_bitop(a, b, 2)

unsafe fn cv_shl(a: i64, b: i64) -> i64:
    return cv_shift(a, b, true)

unsafe fn cv_shr(a: i64, b: i64) -> i64:
    return cv_shift(a, b, false)

unsafe fn cv_floor(a: i64, b: i64) -> i64:
    return cv_division(a, b, false)

unsafe fn cv_abs(a: i64) -> i64:
    if cv_less(a, CV_NUMBER): return cv_neg(a)
    return a

unsafe fn cv_slice(v: i64, a: i64, b: i64) -> i64:
    let n: i64 = cv_len(v)
    let lo: i64 = 0
    let hi: i64 = n
    if a != 0:
        lo = cv_index(a)
        if lo < 0: lo += n
    if b != 0:
        hi = cv_index(b)
        if hi < 0: hi += n
    lo = max(0, min(lo, n))
    hi = max(lo, min(hi, n))
    if cv_istext(v): return cv_subtext(v, lo, hi - lo)
    let out: i64 = cv_vector(cv_kind(v))
    for i in lo..hi: cv_push(out, cv_at(v, i))
    return out

unsafe fn cv_pair(a: i64, b: i64) -> i64:
    let out: i64 = cv_tuple()
    cv_push(out, a)
    cv_push(out, b)
    return out

unsafe fn cv_zip(a: i64, b: i64) -> i64:
    let out: i64 = cv_list()
    for i in 0..min(cv_len(a), cv_len(b)): cv_push(out, cv_pair(cv_at(a, i), cv_at(b, i)))
    return out

unsafe fn cv_enumerate(v: i64) -> i64:
    let out: i64 = cv_list()
    for i in 0..cv_len(v): cv_push(out, cv_pair(cv_i(i), cv_at(v, i)))
    return out

unsafe fn cv_reverse(v: i64) -> i64:
    let out: i64 = cv_list()
    let n: i64 = cv_len(v)
    for i in 0..n: cv_push(out, cv_at(v, n - i - 1))
    return out

unsafe fn cv_keys(v: i64) -> i64:
    return cv_asset(v)

unsafe fn cv_items(v: i64) -> i64:
    let out: i64 = cv_list()
    let p: ptr<CVValues> = v as ptr<CVValues>
    for i in 0..p.len / 2: cv_push(out, cv_pair(p.values[i * 2], p.values[i * 2 + 1]))
    return out

unsafe fn cv_values(v: i64) -> i64:
    let out: i64 = cv_list()
    let p: ptr<CVValues> = v as ptr<CVValues>
    for i in 0..p.len / 2: cv_push(out, p.values[i * 2 + 1])
    return out

unsafe fn cv_update(v: i64, items: i64):
    let p: ptr<CVValues> = items as ptr<CVValues>
    for i in 0..p.len / 2: cv_set(v, p.values[i * 2], p.values[i * 2 + 1])

unsafe fn cv_asdict(pairs: i64) -> i64:
    let out: i64 = cv_dict()
    for i in 0..cv_len(pairs):
        let pair: i64 = cv_at(pairs, i)
        cv_set(out, cv_at(pair, 0), cv_at(pair, 1))
    return out

unsafe fn cv_clone(v: i64) -> i64:
    let k: i64 = cv_kind(v)
    if k == CV_NODE:
        let out: i64 = cv_node(cv_cptr(cv_typename(v)) as string)
        let p: ptr<CVValues> = v as ptr<CVValues>
        for i in 0..p.len / 2: cv_set(out, p.values[i * 2], cv_clone(p.values[i * 2 + 1]))
        return out
    if k == CV_LIST or k == CV_TUPLE:
        let out: i64 = cv_vector(k)
        for i in 0..cv_len(v): cv_push(out, cv_clone(cv_at(v, i)))
        return out
    return v

unsafe fn cv_sorted(v: i64) -> i64:
    let out: i64 = cv_aslist(v)
    let p: ptr<CVValues> = out as ptr<CVValues>
    for i in 1..p.len:
        let j: i64 = i
        let item: i64 = p.values[i]
        while j > 0 and cv_less(item, p.values[j - 1]):
            p.values[j] = p.values[j - 1]
            j -= 1
        p.values[j] = item
    return out

unsafe fn cv_max(a: i64, b: i64) -> i64:
    if cv_less(a, b): return b
    return a

unsafe fn cv_min(a: i64, b: i64) -> i64:
    if cv_less(b, a): return b
    return a

unsafe fn cv_maximum(v: i64, fallback: i64) -> i64:
    if cv_len(v) == 0: return fallback
    let out: i64 = cv_at(v, 0)
    for i in 1..cv_len(v): out = cv_max(out, cv_at(v, i))
    return out

unsafe fn cv_sum(v: i64) -> i64:
    let out: i64 = CV_NUMBER
    for i in 0..cv_len(v): out = cv_numadd(out, cv_at(v, i))
    return out

unsafe fn cv_any(v: i64) -> i64:
    for i in 0..cv_len(v):
        if cv_truth(cv_at(v, i)): return CV_TRUE
    return CV_FALSE

unsafe fn cv_all(v: i64) -> i64:
    for i in 0..cv_len(v):
        if not cv_truth(cv_at(v, i)): return CV_FALSE
    return CV_TRUE

unsafe fn cv_union(v: i64) -> i64:
    let out: i64 = cv_vector(CV_SET)
    for i in 0..cv_len(v):
        let group: i64 = cv_at(v, i)
        for j in 0..cv_len(group): cv_add_set(out, cv_at(group, j))
    return out
