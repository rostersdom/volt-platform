use browser_engine

fn main() -> i64:
    unsafe:
        let history: BrowserHistory
        browser_history_init(&history)
        let i: i64 = 0
        while i < 33:
            browser_history_store(&history, -1, "page-" + "x" * i, 5 + i)
            i += 1
        if history.count != 32 or history.current != 31: return 1
        if browser_history_at(&history, 0) != "page-x": return 2
        if browser_history_at(&history, 31) != "page-" + "x" * 32: return 3
        if browser_history_resource_length(&history, 31) != 37: return 7
        browser_history_store(&history, 2, "redirected", 10)
        if history.current != 2 or browser_history_at(&history, 2) != "redirected": return 4
        browser_history_store(&history, -1, "new branch#end", 10)
        browser_history_store(&history, -1, "new branch#end", 10)
        if history.current != 3 or history.count != 4 or browser_history_at(&history, 4) != "": return 5
        if browser_history_at(&history, 3) != "new branch#end" or browser_history_resource_length(&history, 3) != 10: return 6
    print("browser history ok")
    return 0
