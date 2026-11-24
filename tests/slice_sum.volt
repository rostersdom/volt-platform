fn sum(values: []i64) -> i64:
    let total = 0
    for i in 0..len(values):
        total += values[i]
    return total

let values: [4]i64 = [10, 20, 30, 40]
let middle: []i64 = values[1..3]
print(len(middle), middle[0], middle[1], sum(middle))
