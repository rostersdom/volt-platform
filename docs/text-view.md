# `TextView`: строки с сохранённой длиной

`use text_view` добавляет `text_view.TextView` — пару «адрес байтов, длина»
размером 16 байт на Linux x86-64. Обычный NUL-терминированный `string` и его
ABI не меняются. `text_view.from_string(source)` вычисляет длину один раз и
не копирует байты. `text_view.len(view)`, `text_view.get(view, index)` и
`text_view.slice(view, start, end)` работают за O(1).

```volt
use text_view

let input = text_view.from_string("name:value")
let colon: i64 = 0
while colon < text_view.len(input) and text_view.get(input, colon) != (':' as u8):
    colon += 1
let name = text_view.slice(input, 0, colon) # Только адрес и длина, без копирования.
let output: [5]char
unsafe:
    if text_view.copy_cstr(name, &output[0], len(output)) >= 0:
        print((&output[0]) as string) # name
```

`get` принимает индексы `[0, len)`, `slice` — полуоткрытый диапазон
`0 <= start <= end <= len`. Нарушение границ вызывает `panic`. Пустые диапазоны
разрешены. Считаются байты, а не кодовые точки UTF-8. Поля и конструктор
структуры приватны. Если адрес и длина уже известны, `unsafe text_view.from_bytes`
строит представление без сканирования; в этом случае вызывающий отвечает за
читаемость памяти и её время жизни. Поддиапазон не продлевает время жизни данных.

`unsafe text_view.copy_cstr(view, out, capacity)` — явный переход к C-строке:
поддиапазон сам по себе не обязан заканчиваться NUL. При успехе копируются
только выбранные байты и завершающий NUL, возвращается длина без NUL. Ёмкость
должна быть строго больше длины представления. `-28` означает нехватку места,
`-22` — встроенный NUL либо неверный `out` или `capacity`. При этих ошибках
выходной буфер не меняется. Память назначения должна быть доступна для записи
на всю ёмкость и не перекрываться с исходным диапазоном.
