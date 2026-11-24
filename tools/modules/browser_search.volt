# A small offline inverted index: each term stores two sets of document IDs.
use browser_search_text

const BROWSER_SEARCH_DOCUMENTS: i64 = 64
const BROWSER_SEARCH_PATH_BYTES: i64 = 2048
const BROWSER_SEARCH_QUERY_BYTES: i64 = 1024
const BROWSER_SEARCH_SLOTS: i64 = 32768

struct BrowserSearchTerm:
    key: [97]char
    body: u64
    title: u64

struct BrowserSearchDocument:
    path: [2049]char
    title: [644]char
    preview: [644]char

struct BrowserSearchIndex:
    documents: [64]BrowserSearchDocument
    terms: [32768]BrowserSearchTerm
    document_count: i64
    term_count: i64

struct BrowserSearchHit:
    document: i64
    matched: i64
    in_title: i64

unsafe fn browser_search_new() -> ptr<BrowserSearchIndex>:
    let index: ptr<BrowserSearchIndex> = mmap(sizeof(BrowserSearchIndex)) as ptr<BrowserSearchIndex>
    if (index as i64) < 0: return 0 as ptr<BrowserSearchIndex>
    return index

unsafe fn browser_search_free(index: ptr<BrowserSearchIndex>):
    if index != (0 as ptr<BrowserSearchIndex>): munmap(index as ptr<char>, sizeof(BrowserSearchIndex))

# An empty slot terminates lookup. Keep at least half the table empty.
unsafe fn browser_search_slot(index: ptr<BrowserSearchIndex>, key: string) -> i64:
    let text: ptr<char> = key as ptr<char>
    let hash: i64 = 2166136261
    let at: i64 = 0
    while text[at] != '\0':
        hash = ((hash ^ (text[at] as i64)) * 16777619) & 0xffffffff
        at += 1
    let mask: i64 = BROWSER_SEARCH_SLOTS - 1
    let slot: i64 = hash & mask
    while index.terms[slot].key[0] != '\0':
        if (&index.terms[slot].key[0]) as string == key: return slot
        slot = (slot + 1) & mask
    return slot

unsafe fn browser_search_index_text(index: ptr<BrowserSearchIndex>, text: ptr<char>, length: i64, title: bool, bit: u64) -> i64:
    let at: i64 = 0
    let key: [97]char
    while browser_search_next_term(text, length, &at, &key[0]):
        let slot: ptr<BrowserSearchTerm> = &index.terms[browser_search_slot(index, (&key[0]) as string)]
        if slot.key[0] == '\0':
            if index.term_count >= BROWSER_SEARCH_SLOTS / 2: return -7
            let size: i64 = __volt_strlen((&key[0]) as string)
            for i in 0..(size + 1): slot.key[i] = key[i]
            index.term_count += 1
        if title: slot.title = slot.title | bit
        else: slot.body = slot.body | bit
    return 0

unsafe fn browser_search_discard(index: ptr<BrowserSearchIndex>, bit: u64):
    for i in 0..BROWSER_SEARCH_SLOTS:
        let term: ptr<BrowserSearchTerm> = &index.terms[i]
        if ((term.body | term.title) & bit) == 0: continue
        if (term.body & bit) != 0: term.body = term.body ^ bit
        if (term.title & bit) != 0: term.title = term.title ^ bit
        if (term.body | term.title) == 0:
            # New keys used previously empty slots, so no older probe chain crosses them.
            term.key[0] = '\0'
            index.term_count -= 1

# Copies an absolute local path and extracts text immediately. Returns the document ID
# or a negative errno; on failure the existing index remains usable.
unsafe fn browser_search_add(index: ptr<BrowserSearchIndex>, path: string, source: string, is_html: bool) -> i64:
    let name: ptr<char> = path as ptr<char>
    let path_size: i64 = __volt_strlen(path)
    if path_size < 2 or path_size > BROWSER_SEARCH_PATH_BYTES or name[0] != '/' or name[1] == '/': return -22
    for i in 0..index.document_count:
        if (&index.documents[i].path[0]) as string == path: return i
    let id: i64 = index.document_count
    if id >= BROWSER_SEARCH_DOCUMENTS: return -7
    let body: ptr<char> = source as ptr<char>
    let size: i64 = __volt_strlen(source)
    if size > BROWSER_SEARCH_FILE_BYTES: return -7
    if not browser_search_utf8(body, size): return -22
    let fields: BrowserSearchFields
    bytes_init(&fields.title)
    bytes_init(&fields.body)
    defer bytes_free(&fields.title)
    defer bytes_free(&fields.body)
    if is_html:
        let parsed: i64 = browser_search_extract(source, size, &fields)
        if parsed < 0: return parsed
        body = fields.body.data as ptr<char>
        size = fields.body.len
    let title: ptr<char> = fields.title.data as ptr<char>
    let bit: u64 = (1 as u64) << id
    let status: i64 = browser_search_index_text(index, title, fields.title.len, true, bit)
    if status == 0: status = browser_search_index_text(index, body, size, false, bit)
    if status < 0:
        browser_search_discard(index, bit)
        return status

    let document: ptr<BrowserSearchDocument> = &index.documents[id]
    for i in 0..(path_size + 1): document.path[i] = name[i]
    browser_search_preview(title, fields.title.len, &document.title[0])
    if document.title[0] == '\0':
        let start: i64 = path_size
        while start > 0 and name[start - 1] != '/': start -= 1
        browser_search_preview(name + start, path_size - start, &document.title[0])
    browser_search_preview(body, size, &document.preview[0])
    index.document_count += 1
    return id

# Sort by number of distinct query terms matched, then by title matches, then by input order.
# The caller provides space for up to capacity hits; returns their count or a negative errno.
unsafe fn browser_search_query(index: ptr<BrowserSearchIndex>, query: string, hits: ptr<BrowserSearchHit>, capacity: i64) -> i64:
    let length: i64 = __volt_strlen(query)
    let text: ptr<char> = query as ptr<char>
    if length > BROWSER_SEARCH_QUERY_BYTES or capacity < 0 or not browser_search_utf8(text, length): return -22
    let limit: i64 = min(capacity, index.document_count)
    if limit == 0: return 0
    let matched: [64]i64
    let title: [64]i64
    let seen: [1024]i64
    let seen_count: i64 = 0
    let key: [97]char
    let at: i64 = 0
    while browser_search_next_term(text, length, &at, &key[0]):
        let slot: i64 = browser_search_slot(index, (&key[0]) as string)
        let term: ptr<BrowserSearchTerm> = &index.terms[slot]
        if term.key[0] == '\0': continue
        let previous: i64 = 0
        while previous < seen_count and seen[previous] != slot: previous += 1
        if previous < seen_count: continue
        seen[seen_count] = slot
        seen_count += 1
        let any: u64 = term.body | term.title
        for id in 0..index.document_count:
            let bit: u64 = (1 as u64) << id
            if (any & bit) != 0: matched[id] += 1
            if (term.title & bit) != 0: title[id] += 1

    let count: i64 = 0
    for id in 0..index.document_count:
        if matched[id] == 0: continue
        let insert: i64 = 0
        while insert < count:
            if matched[id] > hits[insert].matched or (matched[id] == hits[insert].matched and title[id] > hits[insert].in_title): break
            insert += 1
        if insert >= limit: continue
        if count < limit: count += 1
        let move: i64 = count - 1
        while move > insert:
            hits[move] = hits[move - 1]
            move -= 1
        hits[insert] = BrowserSearchHit(id, matched[id], title[id])
    return count
