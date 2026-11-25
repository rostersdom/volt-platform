# Пространства имён VOLT

Файл `fs.volt` с заголовком `module fs` не добавляет свои имена в глобальную
область. Клиент пишет `use fs` и обращается к `fs.open(...)`, либо задаёт
локальное имя через `use fs as files`. Пространства имён привязаны к импортам
файла, а не переэкспортируются. Два импортированных модуля могут иметь свои
`open`, не конфликтуя. Файлы без `module` по-прежнему импортируются плоско.

```volt
# store.volt
module store

pub struct Descriptor:
    number: i64

fn make_descriptor(number: i64) -> Descriptor:
    return Descriptor(number)

pub fn open() -> Descriptor:
    return make_descriptor(42)

pub fn number(handle: Descriptor) -> i64:
    return handle.number
```

```volt
# main.volt
use store

let fd: store.Descriptor = store.open()
print(store.number(fd))
# store.make_descriptor(0), store.Descriptor(0) и fd.number запрещены.
```

`pub` допускается для `fn`, `struct`, `enum` и `const`. Публичная структура
разрешена в сигнатурах и может передаваться по значению, но её поля,
конструктор и неявная инициализация нулями доступны только в объявившем файле.
Публичный enum экспортирует варианты; например, `tokens.Token.Number(10)`.
Это правила исходного языка, не песочница для `unsafe`, native-кода или C.

`use fs` из стандартной библиотеки сохраняет старые плоские `file_size`,
`create_dir`, `rename_path`, `remove_file`, `remove_dir`. Новый API включает
`fs.stat(path) -> Result<fs.FileInfo, fs.IoError>`, `fs.size(info)` и
`fs.errno(error)`. `fs.open(path)` открывает файл только для чтения с `O_CLOEXEC`
и возвращает непрозрачный `fs.Descriptor`. Он пока копируемый: вызывающий
обязан закрыть его ровно один раз через `unsafe fs.close_file` (внутри блока
`unsafe:`) и не использовать копии после закрытия.
