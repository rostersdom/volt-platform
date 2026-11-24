link "-lc"

unsafe extern fn qsort(base: ptr<char>, count: u64, width: u64, compare: fnptr<(ptr<char>, ptr<char>) -> i32>)

unsafe fn compare_i32(a: ptr<char>, b: ptr<char>) -> i32:
    let left = *(a as ptr<i32>)
    let right = *(b as ptr<i32>)
    if left < right: return -1
    if left > right: return 1
    return 0

let values: [6]i32 = [19, -2147483648, 6, 0, 2147483647, -2147483648]
unsafe: qsort((&values[0]) as ptr<char>, len(values) as u64, sizeof(i32) as u64, callback(compare_i32))
print(values[0], values[1], values[2], values[3], values[4], values[5])
