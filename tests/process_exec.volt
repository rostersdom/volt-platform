use process

fn main() -> i64:
    unsafe:
        let true_argv: [2]ptr<char>
        true_argv[0] = "true" as ptr<char>
        true_argv[1] = 0 as ptr<char>
        match process_exec_wait("/usr/bin/true", &true_argv[0]):
            Ok(status):
                if status != 0: panic("exec true status")
            Err(error): panic("exec true failed")

        let false_argv: [2]ptr<char>
        false_argv[0] = "false" as ptr<char>
        false_argv[1] = 0 as ptr<char>
        match process_exec_wait("/usr/bin/false", &false_argv[0]):
            Ok(status):
                if status != 1: panic("exec false status")
            Err(error): panic("exec false failed")

        let missing_argv: [2]ptr<char>
        missing_argv[0] = "missing" as ptr<char>
        missing_argv[1] = 0 as ptr<char>
        match process_exec_wait("/no/such/volt-launcher-test", &missing_argv[0]):
            Ok(status):
                if status != 127: panic("exec missing status")
            Err(error): panic("exec missing wait")
    print("process exec ok")
    return 0
