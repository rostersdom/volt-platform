use browser_search

fn main() -> i64:
    unsafe:
        let index: ptr<BrowserSearchIndex> = browser_search_new()
        if index == (0 as ptr<BrowserSearchIndex>): return 1
        defer browser_search_free(index)
        if browser_search_add(index, "/body.txt", "ёжик чай", false) != 0: return 2
        if browser_search_add(index, "/title.html", "<title>Ёжик</title><p>Чай</p>", true) != 1: return 3
        let top: [1]BrowserSearchHit
        if browser_search_query(index, "чай", &top[0], 1) != 1 or top[0].document != 0: return 4
        if browser_search_query(index, "Ёжик", &top[0], 1) != 1 or top[0].document != 1: return 5

        # Create more unique terms than the whole dictionary can hold.
        let bytes: i64 = 7 * 16385 + 1
        let source: ptr<char> = mmap(bytes)
        if (source as i64) < 0: return 6
        defer munmap(source, bytes)
        for i in 0..16385:
            let code: i64 = i
            source[7 * i] = 'x'
            for j in 1..6:
                source[7 * i + j] = ('a' as i64 + code % 26) as char
                code /= 26
            source[7 * i + 6] = ' '
        source[bytes - 1] = '\0'
        if browser_search_add(index, "/overflow.txt", source as string, false) != -7: return 7
        if browser_search_query(index, "xaaaaa", &top[0], 1) != 0: return 8
        if browser_search_query(index, "ёЖиК", &top[0], 1) != 1 or top[0].document != 1: return 9
        if browser_search_add(index, "/later.txt", "новый xaaaaa", false) != 2: return 10
        if browser_search_query(index, "xaaaaa", &top[0], 1) != 1 or top[0].document != 2: return 11
        print("browser search reusable index ok")
    return 0
