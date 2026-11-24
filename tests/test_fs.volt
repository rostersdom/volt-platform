use fs

fn main() -> i64:
    match file_size("tests/fixtures/http_fixture.volt"):
        Ok(size): print("fixture", size)
        Err(error): print("fixture error", error)
    match file_size("tests/fixtures/missing_fs_fixture"):
        Ok(size): print("missing", size)
        Err(error): print("missing errno", error)
    return 0
