# `OwnedBuffer`: перенос и автоматическое освобождение

`use owned_buffer` загружает первый некопируемый тип VOLT: один владелец
байтового буфера. Механизм владения общий: компилятор ведёт реестр владеющих
типов (`cc_owner_kinds` в `compiler/volt_ownership.volt`), и всё описанное ниже
в равной мере относится к [`fs.OwnedFd`](owned-fd.md) с его `close(2)`.
`owned_buffer_new(string)` копирует исходные байты в буфер.
Перенос происходит при инициализации другого `let`, передаче в обычную
VOLT-функцию по значению и `return`. После переноса исходное имя больше
недоступно, даже если перенос мог произойти лишь в одной из веток, доходящих
до следующего оператора.

```volt
use owned_buffer

fn forward(input: OwnedBuffer) -> OwnedBuffer:
    return input

fn show(input: OwnedBuffer):
    defer print(owned_buffer_get(&input, 0) as char)

let original = owned_buffer_new("VOLT")
let buffer = forward(original)
show(buffer) # сначала печатает V, затем освобождает буфер
```

`owned_buffer_len(&buffer)` и `owned_buffer_get(&buffer, i)` читают живого
владельца. Адрес нельзя сохранить или передать другой функции. Отложенное
чтение заимствует владельца до конца блока, поэтому после регистрации такого
`defer` перенос запрещён. Внешнего владельца нельзя переносить на пути к
следующей итерации; перенести его на пути к `break` или `return` можно.

## `owned_buffer_bytes`: байты без копирования

`owned_buffer_bytes(&buffer) -> []u8` возвращает все байты буфера срезом, не
копируя их, — результат `fs.read_all` можно передать парсеру напрямую:

```volt
use fs, owned_buffer

fn count(data: []u8) -> i64:
    let total = 0
    for i in 0..len(data):
        total += data[i]
    return total

fn load(path: string) -> Result<i64, fs.IoError>:
    let buffer = fs.read_all(path, 4096)?
    let bytes = owned_buffer_bytes(&buffer)
    return Ok(count(bytes))
```

Срез заимствует владельца до конца своего блока (включая `defer`), как срез
локального массива: пока срез жив, буфер нельзя перенести — это ошибка
компиляции; после выхода из блока перенос снова разрешён. Сигнатура
`-> []u8 from buffer` привязывает срез к адресу владельца: вернуть такой срез
из функции, владеющей буфером, или иначе пережить владельца нельзя. Из
полученного среза можно делать поддиапазоны и прокидывать его через другие
`from`-функции — заимствование сохраняется.

Для каждого покидаемого блока сначала выполняются зарегистрированные
`defer` в обратном порядке, затем освобождаются ещё живые владельцы в обратном
порядке инициализации их слотов. Очистка идёт из внутреннего блока во внешний
при обычном выходе, `return`, `?`, `break` и `continue`. Параметры принадлежат
вызванной функции. Если `?` прерывает вычисление аргументов до вызова,
аргументы-владельцы ещё принадлежат вызывающей функции. `panic` и `exit`
не раскручивают стек и не запускают ни `defer`, ни `drop`.

## `Result<OwnedBuffer, E>`

Если `E` — допустимый копируемый тип ошибки, `Ok(buffer)` переносит буфер в
`Result<OwnedBuffer, E>`. Весь результат некопируемый, даже если в нём `Err`.
Его можно перенести через `let`, аргумент или `return`. `match` и `?` потребляют
весь результат: ветка `Ok(buffer)` или успешный `?` получает отдельного
владельца, а `Err` обрабатывается как обычная копируемая ошибка. Использовать
исходный результат после любого из этих переносов нельзя.

```volt
use fs, owned_buffer

fn checked_buffer(path: string, text: string) -> Result<OwnedBuffer, fs.IoError>:
    let info = fs.stat(path)?
    return Ok(owned_buffer_new(text))

fn forward(path: string) -> Result<OwnedBuffer, fs.IoError>:
    let buffer = checked_buffer(path, "VOLT")?
    return Ok(buffer)

match forward("."):
    Ok(buffer): defer print(owned_buffer_get(&buffer, 0) as char)
    Err(error): print(fs.errno(error))
```

При очистке живого результата освобождается только активный `Ok`, после `defer`.
Если `match` попал в `_`, не извлечённый буфер освобождается при выходе из этой
ветки, также после её `defer`. Результат, отброшенный отдельным выражением,
освобождается в конце этого выражения. Перенос не копирует байты самого буфера.

## `Option<OwnedBuffer>`

`Option<OwnedBuffer>` — такая же move-only обёртка по той же схеме, что и
владеющий `Result`: `Some(buffer)` переносит буфер, вся обёртка некопируема
даже в состоянии `None`, переносится через `let`, аргумент или `return`.
`match` потребляет обёртку: ветка `Some(buffer)` получает владельца, ветка `_`
держит неизвлечённый буфер до конца ветки (после её `defer`), а `None` ничего
не освобождает — `drop` проверяет метку и освобождает только живой `Some`.
`?` извлекает буфер из `Some` и переносит его, а при `None` возвращает `None`
из охватывающей функции; по общему правилу `Option` её тип результата должен
быть тем же `Option<OwnedBuffer>`.

```volt
use fs, owned_buffer

fn checked(path: string) -> Option<OwnedBuffer>:
    match fs.read_all(path, 4096):
        Ok(buffer): return Some(buffer)
        Err(error): return None

fn relay(input: Option<OwnedBuffer>) -> Option<OwnedBuffer>:
    let buffer = input?
    return Some(buffer)

match relay(checked("payload.bin")):
    Some(buffer): print(owned_buffer_len(&buffer))
    None: print("no payload")
```

Хранить владельца внутри `Err`, вкладывать владеющие обёртки друг в друга
(`Option<Option<OwnedBuffer>>`, `Option<Result<OwnedBuffer, E>>`,
`Result<Option<OwnedBuffer>, E>`) по-прежнему нельзя.

## `fs.read_all`: первый клиент

`fs.read_all(path, max_bytes) -> Result<OwnedBuffer, fs.IoError>` читает файл
целиком в свежий `OwnedBuffer`, но не более `max_bytes` байт. Это первое
реальное применение переноса владения через `Result`: вызывающий получает
буфер через `match` или `?` и ничего не освобождает вручную.

```volt
use fs, owned_buffer

fn load(path: string, limit: i64) -> Result<OwnedBuffer, fs.IoError>:
    let buffer = fs.read_all(path, limit)?
    return Ok(buffer)

match load("payload.bin", 4096):
    Ok(buffer): print(owned_buffer_len(&buffer))
    Err(error): print(fs.errno(error))
```

Байты прочитанного буфера доступны срезом без копирования и побайтового
`owned_buffer_get`: `owned_buffer_bytes(&buffer)` (см. выше).

Функция никогда не паникует: все сбои — это `Err` с положительным `errno`.
Отсутствующий файл и другие ошибки `stat`/`open`/`read` приходят от ядра без
изменений (`ENOENT` и т.п.), нехватка памяти — `ENOMEM` (12) из `mmap`.
Превышение лимита — `EFBIG` (27): тот же код, которым ядро отвечает на
слишком большой файл; проверяется по `fs.stat` до чтения и повторно по факту,
если файл вырос во время чтения (для этого читается на один байт больше
лимита). Неположительный лимит — `EINVAL` (22): `max_bytes <= 0` отклоняется
до обращения к файлу, даже если файл пуст. Пустой файл и файл ровно
`max_bytes` байт — валидные случаи и возвращают `Ok`.

Ошибка посередине чтения закрывает дескриптор и освобождает частично
заполненное хранилище до возврата `Err`. После того как байты становятся
`OwnedBuffer`, оставшиеся пути с ошибкой (например, сбой `close`) освобождают
буфер автоматическим `drop` при `return`, поэтому ни один путь не утекает.

Частичный перенос, переприсваивание владельца, хранение в структурах и массивах,
`OwnedBuffer` в `Err`, вложение владеющих обёрток друг в друга,
пользовательский `drop` и C ABI не поддерживаются. Существующие
`ByteBuffer`, `Buffer<T>` и `BorrowBuffer<T>` не меняются.
