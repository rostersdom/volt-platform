use fs

fn expect_status(result: Result<i64, i32>, expected: i32, label: string):
    match result:
        Ok(status):
            if expected != 0 or status != 0: panic(label)
        Err(error):
            if expected == 0 or error != expected: panic(label)

fn main() -> i64:
    expect_status(create_dir("created", 0x1ff), 0, "create directory")
    expect_status(create_dir("created", 0x1ff), 17, "duplicate mkdir")
    expect_status(create_dir("invalid", 0x200), 22, "invalid mkdir mode")
    expect_status(create_dir("", 0x1c0), 2, "empty path")
    expect_status(rename_path("created", "moved"), 0, "rename directory")
    expect_status(remove_dir("created"), 2, "old directory name")

    expect_status(rename_path("source", "occupied"), 17, "rename over file")
    expect_status(rename_path("source", "dangling"), 17, "rename over dangling link")
    expect_status(rename_path("source", "moved-file"), 0, "rename file")
    expect_status(rename_path("source-link", "moved-link"), 0, "rename symlink itself")

    expect_status(create_dir("dir-link", 0x1c0), 17, "mkdir at symlink")
    expect_status(create_dir("dir-link/child", 0x1c0), 0, "resolve parent symlink")
    expect_status(remove_dir("dir-link"), 20, "rmdir refuses a symlink")
    expect_status(remove_file("dir-link"), 0, "unlink symlink itself")
    expect_status(remove_file("dangling"), 0, "unlink dangling symlink")
    expect_status(remove_file("target"), 21, "unlink refuses a directory")
    expect_status(remove_dir("target"), 39, "rmdir refuses a nonempty directory")

    expect_status(remove_file("discard"), 0, "unlink regular file")
    expect_status(remove_file("discard"), 2, "repeat unlink")
    expect_status(remove_dir("empty"), 0, "remove empty directory")
    expect_status(remove_dir("empty"), 2, "repeat rmdir")
    print("fs paths ok")
    return 0
