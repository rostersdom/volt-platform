use buffer

struct Record:
    id: i64
    code: char
    weight: i64

struct Entry<T>:
    value: T

fn main() -> i64:
    unsafe:
        let records: Buffer<Record>
        defer buffer_free(&records)
        let numbers: Buffer<u16>
        defer buffer_free(&numbers)
        if buffer_len(&records) != 0 or buffer_capacity(&records) != 0: return 1
        let i: i64 = 0
        while i < 1500:
            if buffer_push(&records, Record(i, 'A', i * 17)) != 0: return 2
            if buffer_push(&numbers, i as u16) != 0: return 3
            i += 1
        let capacity: i64 = buffer_capacity(&records)
        if capacity < 1500 or buffer_reserve(&records, 9223372036854775807) != -75: return 4
        if buffer_len(&records) != 1500 or buffer_capacity(&records) != capacity: return 5
        i = 0
        while i < 1500:
            let entry: ptr<Record> = buffer_at(&records, i)
            if entry.id != i or entry.code != 'A' or entry.weight != i * 17: return 6
            if *buffer_at(&numbers, i) != i as u16: return 7
            i += 1
        if buffer_free(&numbers) != 0 or buffer_len(&numbers) != 0: return 8
        if buffer_push(&numbers, 7 as u16) != 0 or *buffer_at(&numbers, 0) != 7: return 9
        let empty_elements: Buffer<[0]i64>
        if buffer_len(&empty_elements) != 0 or buffer_capacity(&empty_elements) != 0: return 10
        if buffer_reserve(&empty_elements, 1) != -22: return 11
        let entries: Buffer<Entry<u8>>
        defer buffer_free(&entries)
        if buffer_push(&entries, Entry(7)) != 0 or buffer_at(&entries, 0).value != 7: return 12
    print("typed buffer ok")
    return 0
