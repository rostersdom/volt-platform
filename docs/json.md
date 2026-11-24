# JSON в VOLT

`use json` проверяет один JSON-документ в UTF-8 и возвращает диапазоны
исходных байтов. Модуль не строит дерево, не выделяет память и не копирует вход.

```volt
use json

fn main() -> i64:
    unsafe:
        let text: string = "{\"items\":[\"Привет\",9007199254740993]}"
        let root: JsonValue
        let items: JsonValue
        let item: JsonValue
        if json_parse(text as ptr<char>, str_len(text), &root) != 0: return 1
        if json_member(&root, "items" as ptr<char>, 5, &items) != 0: return 1
        if json_index(&items, 0, &item) != 0: return 1
        let decoded: [32]char
        let size: i64 = json_decode_string(&item, &decoded[0], 32)
        if size < 0: return 1
        # decoded[0..size] — ровно байты UTF-8, не VOLT string.
        let quoted: [64]char
        let quoted_size: i64 = json_quote(&decoded[0], size, &quoted[0], 64)
        if quoted_size < 0: return 1
        if json_index(&items, 1, &item) != 0 or item.kind != JSON_NUMBER: return 1
        # item.text + item.start, item.stop - item.start — точная лексема числа.
    return 0
```

## Чтение

```volt
unsafe fn json_parse(text: ptr<char>, length: i64, out: ptr<JsonValue>) -> i64
unsafe fn json_member(object: ptr<JsonValue>, key: ptr<char>, length: i64, out: ptr<JsonValue>) -> i64
unsafe fn json_index(array: ptr<JsonValue>, index: i64, out: ptr<JsonValue>) -> i64
unsafe fn json_bool(value: ptr<JsonValue>) -> i64
```

- `json_parse` принимает ровно `length` байтов, без требования NUL в конце.
  В корне допустим любой из шести типов JSON. Только пробел, табуляция, CR и LF
  разрешены вне токенов; BOM, комментарии, завершающие запятые и лишние данные
  не принимаются. Строки проверяются на правильный UTF-8 и JSON-экранирование.
  В `\uXXXX` одиночный суррогат считается ошибкой; правильно спаренные
  суррогаты представляют один Unicode-символ.
- У `JsonValue` поля `text`, `start`, `stop`, `kind`. Диапазон `[start, stop)`
  отсчитывается от `text`: без окружающих пробелов, но с кавычками или скобками
  токена. `kind` — `JSON_OBJECT`, `JSON_ARRAY`, `JSON_STRING`, `JSON_NUMBER`,
  `JSON_BOOL` или `JSON_NULL`. Числа остаются лексемами: нет округления,
  ограничения на величину числа или автоматического преобразования в `f64`.
- `json_member` ищет непосредственное поле по декодированному имени. Ключ
  передаётся как необрамлённый UTF-8 с явной длиной; возможны пустой ключ и
  байт NUL. Сравнение точное, без нормализации; неправильный UTF-8 не совпадает.
  Синтаксически правильный документ может содержать повторяющиеся имена, но
  запрос неоднозначного поля возвращает `JSON_ERR_DUPLICATE`, даже если одно
  из написаний экранировано. `json_index` ищет непосредственный элемент по
  индексу с нуля. Оба вызова последовательно обходят контейнер без индекса.
- Первые три функции возвращают `0` при успехе; при любой ошибке `out` не
  меняется. Его можно направить в тот же `JsonValue`, что и аргумент объекта
  или массива. `json_bool` возвращает `1` для `true`, `0` для `false` или
  отрицательный статус, если значение не булево.

## Работа со строками

```volt
unsafe fn json_decode_string(value: ptr<JsonValue>, out: ptr<char>, capacity: i64) -> i64
unsafe fn json_quote(text: ptr<char>, length: i64, out: ptr<char>, capacity: i64) -> i64
```

Обе функции возвращают число байтов, **не добавляют завершающий NUL** и не
пишут в буфер при ошибке. Вызов с `out = 0 as ptr<char>` и `capacity = 0`
проверяет вход и вычисляет нужный размер. Ёмкости, равной этому размеру,
достаточно для последующей записи.

- `json_decode_string` снимает кавычки, декодирует escapes и пишет UTF-8.
  `\u0000` декодируется в обычный нулевой байт и входит в возвращаемую длину.
  Храните результат как байты с длиной. Для преобразования в `string` вызывающий
  код должен сначала отклонить встроенный NUL и дописать терминатор сам.
- `json_quote` пишет **один JSON-токен-строку** с обеими кавычками. Проверяет
  UTF-8, экранирует `"`, `\`, байты `0x00`–`0x1f` и `0x7f`. Остальной UTF-8
  сохраняется. Это экранирование JSON, не HTML или JavaScript; универсальной
  сериализации объектов и массивов, а также потокового API пока нет.

## Лимиты, буферы и статусы

- `JSON_MAX_BYTES` = 8 МиБ: максимум для входного документа (включая пробелы),
  ключа поиска, входа `json_quote` и полученного от `json_quote` токена.
- `JSON_MAX_DEPTH` = 64 одновременно открытых объектов/массивов. Корневой
  контейнер считается первым; скаляр внутри 64-го контейнера разрешён.
- `JsonValue` заимствует данные. Держите исходный буфер живым и неизменным до
  окончания работы со всеми его диапазонами. Если вход — `ByteBuffer`, не
  изменяйте его и не вызывайте `bytes_reserve`/`bytes_free`, пока диапазоны
  используются. Передавайте только `JsonValue`, полученные от ридера.
- Операции с указателями `unsafe`: вызывающий код предоставляет читаемые
  диапазоны указанной длины и записываемые буферы указанной ёмкости. Байтовые
  вход и выход не должны перекрываться; вход не изменяется до конца вызова.
  Буфером записи владеет вызывающий код.

| Статус | Причина |
| --- | --- |
| `JSON_NOT_FOUND` (`-2`) | Нет поля или элемента по неотрицательному индексу |
| `JSON_ERR_SPACE` (`-7`) | Слишком короткий выходной буфер |
| `JSON_ERR_DUPLICATE` (`-17`) | Неоднозначное имя запрошенного поля |
| `JSON_ERR_ARGUMENT` (`-22`) | Неподходящий тип значения, отрицательная длина/ёмкость/индекс или недопустимый нулевой указатель |
| `JSON_ERR_SYNTAX` (`-74`) | Неправильный синтаксис, escape, Unicode или UTF-8 |
| `JSON_ERR_DEPTH` (`-75`) | Превышена глубина контейнеров |
| `JSON_ERR_TRAILING` (`-84`) | После корневого значения есть байты кроме допустимых пробелов |
| `JSON_ERR_SIZE` (`-90`) | Превышен лимит байтов |

## Проверка

Из корня проекта, с существующим `./volt`:

```sh
set -eu
build=$(mktemp -d "${TMPDIR:-/tmp}/volt-json.XXXXXX")
for name in json_reader json_strings; do
  ./volt "tests/$name.volt" -o "$build/$name"
  "$build/$name" > "$build/$name.out"
  diff -u "tests/expected/$name.txt" "$build/$name.out"
done
```
