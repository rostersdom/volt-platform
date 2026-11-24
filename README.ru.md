# VOLT Platform

[English](README.md) · **Русский** · [Español](README.es.md)

**VOLT Platform** объединяет системный язык VOLT, самособирающийся компилятор,
стандартную библиотеку и нативный браузер с собственным движком. Текущая цель —
**Linux x86-64**. Компилятор версии **0.3.0** написан на VOLT: он сам кодирует
инструкции x86-64 и записывает ELF. Программы могут работать без libc;
подключение C-библиотек явно задаётся через `unsafe extern fn` и `link`.

## Быстрый старт

В корневом каталоге соберите `volt` командой `make compiler`. Для первой
сборки используется готовый статический [компилятор VOLT](bootstrap/README.md),
который лежит в проекте. Затем запустите пример `apps/hello.volt`.

```volt
fn main() -> i64:
    print("Hello, VOLT!")
    return 0
```

```bash
git clone https://github.com/rostersdom/volt-platform.git
cd volt-platform
sha256sum -c bootstrap/SHA256SUMS
make compiler
./volt apps/hello.volt --run
```

Ожидаемый вывод (одна строка):

```text
Hello, VOLT!
```

Скомпилируйте тот же файл, затем запустите полученный бинарник:

```bash
./volt apps/hello.volt -o apps/bin/hello
apps/bin/hello
```

Этот вариант также выводит ровно `Hello, VOLT!` и завершается с кодом 0. `--run`
временно собирает и запускает программу; `-o` сохраняет ELF-бинарник по указанному пути.
Единственная поддерживаемая цель сейчас — `linux-x86_64`; её можно указать явно
через `--target linux-x86_64` (или `--target=linux-x86_64`). Без флага поведение
такое же. Windows и D3D11 пока не поддерживаются.

Другие примеры и проверки (команды также запускаются из корня репозитория):

```bash
./volt apps/demo.volt --run       # типы, функции, строки и структуры
make browser                                 # собрать браузер VOLT
apps/bin/browser                            # открыть стартовую страницу
apps/bin/browser examples/page.html         # открыть локальный HTML
apps/bin/browser examples/layout.html       # посмотреть адаптивную страницу
apps/bin/browser https://example.org/       # открыть HTTPS URL
apps/bin/browser --screenshot apps/bin/layout.png examples/layout.html # снимок без окна
./volt tests/browser_pipeline.volt --run          # проверить HTML/CSS/layout pipeline
./volt tests/paint.volt --run                     # проверить VOLT framebuffer pixels
./volt apps/snake.volt --run      # оконная змейка: WASD/стрелки, Space, R, Esc (нужен SDL2)
./volt apps/rift.volt --run       # рогалик: WASD/стрелки, бой, лут, этажи
./volt apps/sort.volt --run       # сортировка и массивы
./volt apps/bytebuffer.volt --run # чтение файла и владение ByteBuffer
./volt apps/volt_launcher.volt -o apps/bin/volt-launch # launcher .volt для Linux
./volt tests/process_exec.volt --run # fork/exec/wait syscalls
./volt apps/c_ffi.volt --run      # вызов функций libc
./volt apps/http_get.volt --run   # HTTP/1.0 GET к 127.0.0.1:8080
./volt apps/demo.volt --emit-asm  # посмотреть ассемблер
python3 tests/run_all.py             # полный прогон (включая SDL dummy и loopback)
python3 tests/run.py                 # тесты с эталонным выводом
python3 tests/regressions.py         # проверки ошибок и ABI
python3 tests/http_integration.py    # HTTP loopback integration
python3 benchmarks/run.py            # арифметика, строки и вывод
```

Собранный `./volt` ищет `vstd/` рядом с исполняемым файлом или в одном из
родительских каталогов. Ни для сборки компилятора, ни для компиляции `.volt`
не нужны C++, GMP, Python, внешний ассемблер или линковщик. Команда
`make verify-bootstrap` пересобирает компилятор дважды и сравнивает ELF побайтно.
Python 3 нужен только для тестов и замеров. Необязательные воркеры JavaScript
и декодирования видео собираются отдельно из C.

### Браузер VOLT

Браузер открывает локальные HTML-файлы, HTTP и HTTPS. Для сборки нужны пакеты
разработки SDL2, Cairo, PangoCairo, OpenSSL 3, zlib, libwebp и TurboJPEG 3.
VOLT разбирает HTML и CSS и рассчитывает геометрию документа. Cairo и Pango
рисуют интерфейс и пропорциональный текст, а SDL2 выводит кадр в окно.

Без аргументов браузер показывает стартовую страницу с быстрыми ссылками.

- `Ctrl+L` или клик по адресной строке выделяют адрес. `Ctrl+A/C/X/V` работают с
  выделением и буфером обмена. `Enter` открывает адрес, `Esc` отменяет ввод.
- `Alt+←` и `Alt+→` переходят назад и вперёд, `Alt+Home` открывает стартовую
  страницу, `F5` или `Ctrl+R` обновляют документ. `Ctrl+H` открывает историю сеанса.
- Во время загрузки нажмите `Esc` или кнопку «Стоп» на месте «Обновить», чтобы
  остаться на текущей странице.
- Колесо, полоса прокрутки, стрелки и `PageUp` / `PageDown` прокручивают страницу.
  При изменении размера окна текст переносится по доступной ширине.
- `Ctrl+плюс` и `Ctrl+минус` меняют масштаб от 100% до 300%, `Ctrl+0` возвращает
  100%. На масштаб также можно нажать в строке состояния.
- При наведении на ссылку строка состояния показывает её адрес. Если загрузка
  завершилась ошибкой, кнопка «Повторить» отправляет тот же запрос ещё раз.

Оконный режим применяет внешние CSS, адаптивные колонки Grid, выравнивание
Flexbox, градиенты, полупрозрачные цвета, скругления и тени. PNG, JPEG и WebP
могут заполнять рамку с сохранением пропорций через `object-fit`. Для проверки
отрисовки без окна используйте `--screenshot`. Лимит HTML составляет 2 МиБ.

Чтобы воспроизводить прямые файлы WebM, MP4 или Ogg в HTML-элементе `<video>`,
соберите необязательный декодер (`pkg-config`, FFmpeg/libav и libseccomp):

```sh
make browser-media
apps/bin/browser examples/video.html
```

Щелчок по ролику — запуск или пауза; пробел — пауза или продолжение. Кадры
рисуются в окне VOLT, звук выводится через SDL.

**YouTube (эксперимент).** Вставьте ссылку `youtube.com/watch?v=…` или `youtu.be/…`
в адресную строку либо запустите `apps/bin/browser 'https://youtu.be/jNQXAC9IVRw'`.
В VOLT откроется своя страница ролика. Нажмите «Проверить доступность», а если
появится плеер — «Смотреть видео». Ролик можно проиграть только тогда, когда
YouTube отдаёт подходящий прямой файл со звуком и видео без входа в аккаунт.
Полноценный сайт и официальный встроенный плеер YouTube пока не работают.

Для экспериментального JavaScript соберите воркер на Duktape и libseccomp и
откройте пример с `--js`.

```sh
make browser-js
apps/bin/browser --js examples/interactive.html
```

JavaScript выполняется отдельным процессом. Вместо Duktape можно собрать
воркер QuickJS-NG с поддержкой современного синтаксиса и `Promise`:
`make browser-js-modern QUICKJS_DIR=/путь/к/quickjs-amalgam`. Обычная сборка
`make browser` использует только зависимости рендеринга и транспорта.
Список поддерживаемых возможностей приведён в [документации движка](docs/html-engine.md).

### Поиск, JSON и CUDA

- [`volt-search`](docs/search.md) строит локальный индекс по переданным HTML- и
  текстовым файлам, без сетевых запросов. Результаты можно открыть в браузере VOLT.
- [`use json`](docs/json.md) разбирает JSON по заданной длине, сохраняет числовые
  лексемы без округления и умеет записывать JSON-строки с экранированием.
- [`use cuda`](docs/cuda.md) загружает драйвер NVIDIA при запуске, если он нужен.
  Пример запускает готовое PTX-ядро; CUDA Toolkit и `nvcc` не обязательны.

```sh
./volt apps/volt_search.volt -o apps/bin/volt-search
apps/bin/volt-search 'ёжик' tests/search_body.txt tests/search_title.html > apps/bin/results.html
./volt apps/cuda_smoke.volt -o apps/bin/cuda-smoke
CUDA_CACHE_DISABLE=1 apps/bin/cuda-smoke # требует доступный NVIDIA GPU
```

### Открытие `.volt` двойным щелчком в Linux

Сначала соберите `volt` и задайте `VOLT_COMPILER` в окружении рабочего стола.
Укажите абсолютный путь к собранному `volt` в дереве проекта. Затем установите
launcher и привязку MIME для текущего пользователя.

```bash
mkdir -p ~/.local/bin ~/.local/share/applications ~/.local/share/mime/packages
./volt apps/volt_launcher.volt -o apps/bin/volt-launch
cp apps/bin/volt-launch ~/.local/bin/volt-launch
cp share/applications/volt-launcher.desktop ~/.local/share/applications/
cp share/mime/packages/volt.xml ~/.local/share/mime/packages/
update-mime-database ~/.local/share/mime
update-desktop-database ~/.local/share/applications
xdg-mime default volt-launcher.desktop text/x-volt
```

После входа в систему файловый менеджер сможет открывать `.volt` через launcher.
Команда `volt-launch [--] <source.volt|browser> [args...]` передаёт программу и
аргументы в компилятор по абсолютному пути из `VOLT_COMPILER`. Команда с
псевдонимом `browser` собирает `apps/browser.volt` из того же дерева.
`--` отделяет флаги запуска от пути к исходнику. Аргументы после пути
передаются собранной программе. Относительные пути разрешаются от каталога
запуска. В интерактивном терминале launcher запрашивает подтверждение перед
исполнением произвольного `.volt`. `Terminal=true` оставляет терминал открытым
для вывода и ошибок.

## Пример

```volt
use math

struct Point:
    x: f64
    y: f64

fn dist(a: Point, b: Point) -> f64:
    return hypot(a.x - b.x, a.y - b.y)

fn main() -> i64:
    let a = Point(0.0, 0.0)
    let b = Point(3.0, 4.0)
    print("dist =", dist(a, b))
    return 0
```

## Возможности текущей версии

- статические типы: целые `i8..i64`/`u8..u64`, `f32`/`f64`, `bool`, `char`,
  неизменяемые `string`, raw `ptr<T>`, `[N]T`, immutable `[]T` slices, структуры,
  enum и локальные `Option<T>`/`Result<T,E>`;
- обобщённые функции и структуры специализируются на конкретных типах при
  компиляции. [Пример синтаксиса](docs/language.md#обобщённые-структуры);
- обычные VOLT-функции могут возвращать структуры через внутренний hidden-sret
  ABI; это не распространяется на `Option`/`Result` payload и extern/native ABI;
- обычные VOLT-функции поддерживают Option/Result-параметры и результаты через внутренний pointer/sret ABI; postfix `?` разворачивает `Some`/`Ok` и распространяет `None`/`Err` с выполнением `defer`; extern/native wrappers не поддерживаются;
- индексы фиксированных массивов и строк проверяются во время выполнения;
- целочисленная арифметика и преобразования проверяют диапазон; ошибка вызывает
  `panic`, вместо молчаливого wrap или аппаратного исключения;
- `for i in a..=b` включает правую границу диапазона;
- raw-указатели и функции с ними требуют `unsafe:`/`unsafe fn`; обычные строки
  имеют безопасный тип и ограниченную индексацию;
- C FFI для вызова внешних функций (`unsafe extern fn`, `link`) и передачи
  типизированных колбэков (`fnptr`, `callback`);
- `native fn` для x86-64 assembly, `mmap`/`munmap` и Linux runtime на syscalls;
- модули `use` и стандартные модули `io`, `str`, `math`, `math3d`, `bytes`, `buffer`,
  `time`, `fs`, `process`, `event`;
- `event` предоставляет безопасный `poll_readable(fd, timeout_ms)` для проверки
  одного дескриптора и `unsafe poll(fds, timeout_ms)` для массива дескрипторов
  через Linux `poll`; `-1` означает ожидание без тайм-аута, а `poll` возвращает
  число готовых записей и заполняет их `revents`. Там же есть unsafe timerfd
  API: `timer_create`, относительный `timer_set` в миллисекундах, `timer_read`
  счётчика истечений и `timer_close`, совместимые с `poll`;
- `ByteBuffer` с ростом, чтением файла как бинарных данных и ручным освобождением
  ([рецепт](apps/bytebuffer.volt));
- безопасный растущий `ByteVec` и диапазоны `ByteView` с сохранённой длиной
  в [`use bytevec`](docs/language.md#безопасный-байтовый-буфер-bytevec);
- растущий `Buffer<T>` для значений и структур в куче. `buffer_at` проверяет
  индекс. Память освобождается явным вызовом `buffer_free`;
- минимальный блокирующий HTTP/1.0 GET по IPv4/TCP в `use http`, с ограничениями размера; `use dns` разрешает IPv4 для hostname-навигации viewer-а;
- `io` сообщает об ошибках записи и завершает программу с ненулевым кодом.
- `window` — минимальный convenience API поверх SDL2: `Window`, создание через
  возврат `Window` по значению с нулевым sentinel при ошибке, polling закрытия/выхода, очистка, прямоугольник,
  present и закрытие; см. [`apps/window.volt`](apps/window.volt) и
  [`docs/sdl.md`](docs/sdl.md).
- начальный HTML tokenizer/DOM tree builder в `use html`; это только этап 1
  движка, не HTML5-парсер и не браузер (лимиты и пробелы описаны в
  [`docs/html-engine.md`](docs/html-engine.md)).
- начальный bounded CSS rule parser `use css`; только простые selector-блоки и
  диапазоны declarations, `!important`, tag/class/id matching, descendant/child
  cascade, inline `<style>` extraction, ограниченные resolved values и вертикальная DOM-геометрия без
  inline formatting/rendering (см.
  [`docs/html-engine.md`](docs/html-engine.md)).

Приложения: вызов libc — [`apps/c_ffi.volt`](apps/c_ffi.volt); HTTP GET —
[`apps/http_get.volt`](apps/http_get.volt); API и ограничения описаны
в справочнике [`docs/language.md`](docs/language.md) и подробном описании
[`docs/http.md`](docs/http.md).

## Структура

```
volt                 исполняемый компилятор (результат make compiler)
compiler/            компилятор на VOLT, включая кодирование x86-64 и запись ELF
bootstrap/           начальный статический компилятор Linux x86-64
vstd/                стандартные модули VOLT
docs/language.md     справочник по языку
ROADMAP.md           этапы развития
apps/                приложения VOLT и bin/ для собранных исполняемых файлов
examples/            входные данные и ресурсы приложений
tests/               тесты и регрессии
benchmarks/          повторяемые замеры производительности
```

## Ограничения

- сейчас поддерживается только Linux x86-64 и System V ABI;
- `link` работает с разделяемыми ELF-библиотеками. Для `native fn` поддерживается
  подмножество инструкций Intel x86-64, включая все используемые в `vstd/`;
- C FFI поддерживает вызовы и передачу скалярных колбэков по System V ABI.
  Модуль CUDA использует `dlopen` и нативные переходники; общий вызов через
  `fnptr` и экспорт функций для C пока не реализованы.
- VOLT использует собственный старт и завершение процесса, не полный C runtime;
  функции, зависящие от lifecycle libc, пока не гарантируются;
- передавайте структуры во внешние функции через указатели в `unsafe`-коде;
- `unsafe` не проверяет raw-указатели во время выполнения и не доказывает их
  время жизни; безопасный код может использовать строки, массивы и `ByteVec`;
- строки используют общую арену размером 1 MiB; переполнение или исчерпание
  арены вызывает `panic`;
- `Buffer<T>` использует ручное владение в `unsafe`. Рост может сделать
  указатели на его элементы недействительными;
- `use http` отправляет HTTP/1.0 GET по IPv4 с лимитом 8 КиБ на запрос и 64 КиБ
  на ответ по умолчанию. Браузер использует отдельный бюджет для документов до
  2 МиБ, разрешает ASCII-имена, поддерживает HTTPS и до пяти перенаправлений.
  Оконная загрузка выполняется в фоне; её можно остановить кнопкой на месте
  «Обновить» или клавишей Esc. [Подробности о транспорте](docs/http.md).
- `monotonic_ms()` из `time` и `file_size()` из `fs` используют Linux x86-64
  syscalls; время монотонное и не является датой, а размер файла — логический
  размер на момент `statx` и возвращается через `Result` вместе с положительным
  `errno` при ошибке;
- `argc()` и `arg_at()` из `process` читают аргументы из начального стека Linux
  x86-64; `arg_at()` возвращает `Err(22)` для отрицательного или недопустимого
  индекса, а успешная строка ссылается на память начального стека;
- `poll_readable()` и `poll()` из `event` используют Linux x86-64 syscall `poll`
  и принимают тайм-аут в миллисекундах; `poll()` небезопасен, поскольку ядро
  изменяет `revents` в immutable-срезе, и возвращает положительный `errno` при
  ошибке. Timerfd из `event` использует `CLOCK_MONOTONIC`, является
  неблокирующим и возвращает положительный `errno`; это не переносимый event
  loop и не API для других архитектур;
- SDL2 binding ограничен одним software renderer и минимальным polling SDL_QUIT /
  window-close через `use window`: нет keyboard/mouse API, pixel assertions,
  OpenGL/Vulkan, звука или загрузчиков;
- SDL2 необязателен, но импорт `sdl` требует установленной SDL2 development library
  на этапе сборки и shared library при запуске; интеграционная проверка запускается
  командой `SDL_VIDEODRIVER=dummy python3 tests/sdl_integration.py`; нет
  cross-platform ABI guarantee;
- потоков/атомиков, traits, графики OpenGL/Vulkan и готовых загрузчиков
  текстур/моделей пока нет.

## Проверки

Запуск из корня репозитория с установленными зависимостями браузера.

```sh
python3 tests/run_all.py
python3 tests/cuda_integration.py # отдельно; реальная GPU-проверка: VOLT_CUDA_GPU=1
```

`tests/run.py --update` перезаписывает golden-файлы только после успешной
компиляции и запуска; при ошибке или тайм-ауте эталон не изменяется. Обычный
запуск каждого golden-теста ограничен 10 секундами.
Проверки JavaScript и видео пропускаются, если `pkg-config` не находит их
необязательные зависимости (Duktape или FFmpeg/libav, а также libseccomp).

Объявление `let` в импортируемом модуле создаёт изменяемое глобальное значение
после выполнения его константного инициализатора; для неизменяемого значения
используйте `const`. Корневые `let` основного файла остаются локальными
объявлениями синтетической `__voltmain__`.

Подробности синтаксиса — в [`docs/language.md`](docs/language.md), статус
запланированных функций — в [`ROADMAP.md`](ROADMAP.md). Проект распространяется
по лицензии [MIT](LICENSE).
