# VOLT Platform

**English** · [Русский](README.ru.md) · [Español](README.es.md)

[Quick start](#quick-start) · [Components](#components) · [Browser](#try-the-volt-browser) ·
[Platform specification](#platform-specification) · [Full language specification](#volt-030-language-specification)

**VOLT Platform** brings together the VOLT systems programming language, its
self-hosted compiler and standard library, and a native browser for **Linux
x86-64**. The compiler generates x86-64 machine code and writes ELF executables
directly, without an external assembler or linker. Programs that do not link
external libraries can run without libc.

## Quick start

```sh
git clone https://github.com/rostersdom/volt-platform.git
cd volt-platform
sha256sum -c bootstrap/SHA256SUMS
make compiler
./volt apps/hello.volt --run
```

Expected output: `Hello, VOLT!`. To keep the executable, run
`./volt apps/hello.volt -o apps/bin/hello`.

```volt
fn main() -> i64:
    print("Hello, VOLT!")
    return 0
```

The compiler builds from the checked-in [static bootstrap](bootstrap/README.md).
It does not need Python or a C/C++ compiler. Run `make verify-bootstrap` to
build two generations with an empty `PATH` and compare them byte for byte.

## Components

| Component | Sources and build |
| --- | --- |
| **VOLT Language** | The [language reference](#volt-030-language-specification), self-hosted [`compiler/`](compiler/) and static [`bootstrap/`](bootstrap/). Build `./volt` with `make compiler`. |
| **VOLT Standard Library** | [`vstd/`](vstd/): runtime support, buffers, files, networking, and shared parsers such as [JSON](docs/json.md) and HTML. |
| **VOLT Browser & Media** | [`browser/`](browser/): native browser, layout and rendering modules, JavaScript workers, and the video decoder. Build with `make browser`, `make browser-js`, or `make browser-media`. |
| **VOLT GPU** | [`gpu/`](gpu/): optional [CUDA](docs/cuda.md) bindings and a PTX demo. Build the demo with `make cuda`; a GPU is needed only to run it. |
| **VOLT Tools** | [`tools/`](tools/): [offline search](docs/search.md) and a Linux `.volt` launcher. Build with `make tools`, `make search`, or `make launcher`. |
| **Examples and checks** | [`apps/`](apps/) and [`examples/`](examples/) hold demos and assets; [`tests/`](tests/) and [`benchmarks/`](benchmarks/) verify the components. |

The compiler and standard library work without the optional components. The
default output directory for applications and workers is still `apps/bin/`.

## Try the VOLT browser

```sh
make browser
apps/bin/browser examples/layout.html
```

The browser requires development libraries for SDL2, Cairo, Pango, OpenSSL 3,
zlib, libwebp, and TurboJPEG 3. VOLT parses HTML and CSS and lays out documents;
Cairo, Pango, and SDL draw and display the result. It does not embed Chromium,
WebKit, or another browser.

- **Video:** Build with `make browser-media` and open
  `apps/bin/browser examples/video.html`. The optional FFmpeg/libav worker
  decodes direct WebM, MP4, and Ogg files; VOLT controls playback and SDL outputs
  audio. The worker build needs `pkg-config`, the libav development libraries,
  and libseccomp.
- **JavaScript:** Build with `make browser-js` (Duktape and libseccomp) and run
  `apps/bin/browser --js examples/interactive.html`. The isolated worker exposes
  a limited DOM and runs supported classic scripts from the same origin.
  [QuickJS-NG](docs/html-engine.md#экспериментальный-javascript)
  is an optional alternative for modern JavaScript syntax and promises.
- **Web compatibility:** HTML, CSS, and JavaScript support are partial. The
  experimental YouTube view accepts watch links but can play only a compatible
  direct file when one is available. The official YouTube player, MediaSource
  (MSE), and DRM are not supported.

See the [browser documentation](docs/html-engine.md) for setup and limits, and
[source and dependencies](docs/html-engine.md#исходники-и-внешние-зависимости)
for the implementation map and the distinction from TNet.

## Platform specification

| Subsystem | Implemented behaviour and limits |
| --- | --- |
| Bootstrap and compilation | A static ELF seed builds the compiler from VOLT sources. Module loading, parsing, type checking, x86-64 encoding, and ELF emission run inside `volt`. `make verify-bootstrap` compares two rebuilt executables with no external tools on `PATH`. |
| Browser UI and rendering | VOLT owns navigation, layout, and hit testing. Local HTML and HTTP(S), session history, anchors, stop/retry, resize, zoom, and 640×480 PNG screenshots are supported. HTML is capped at 2 MiB; Grid, Flexbox, media queries, and PNG/JPEG/WebP support are limited to the documented subset. |
| Page resources | Styles and images use same-origin HTTP(S) or confined local paths. Classic scripts run only with `--js`; external scripts come from the same origin over HTTP(S), including redirects, using the document peer's IP address. A Content Security Policy disables scripts. The worker has no network access, with a 750 ms initialization budget and at most 16 scripts totalling 64 KiB. |
| Media | Direct video is loaded on request, up to 32 MiB. `volt-media` decodes supported streams; VOLT presents frames up to 960×540 and sends PCM to SDL. An internal fragmented-MP4 mode supports clear H.264 with optional AAC, up to 1 MiB per append and 32 MiB per session. It is not a web MediaSource implementation. |
| Local search | `volt-search` indexes supplied HTML and UTF-8 text files in memory, matches Russian and ASCII words case-insensitively, and writes linked HTML results. It accepts at most 64 files of 256 KiB each and never sends queries over the network. |
| GPU | `use cuda` loads the NVIDIA driver on demand on Linux x86-64 with glibc 2.34 or later. The demo runs supplied PTX, transfers data, synchronizes, and releases resources. It does not compile VOLT functions to GPU code. |

[Browser and media](docs/html-engine.md) · [HTTP/TLS](docs/http.md) ·
[JSON](docs/json.md) · [Local search](docs/search.md) · [CUDA](docs/cuda.md)

## Tests and documentation

```sh
make verify-bootstrap
python3 tests/run_all.py
python3 tests/cuda_integration.py  # separate; set VOLT_CUDA_GPU=1 to require a real GPU
```

The full suite needs Python 3 and the browser development libraries; optional
worker tests are skipped when their dependencies are unavailable. The CUDA
example needs a compatible NVIDIA driver to run on a GPU, but no CUDA Toolkit
or `nvcc` to build. The base compiler and browser do not require CUDA.

[Russian language reference](docs/language.md) · [Roadmap](ROADMAP.md) · [MIT license](LICENSE)

Core extensions: [modules and `pub`](docs/modules.md), [owned buffers](docs/owned-buffer.md),
[lexical slice borrowing](docs/slice-borrows.md), [`TextView`](docs/text-view.md),
[compound `Option`/`Result`](docs/option-result-payloads.md), [payload enums](docs/enum-payloads.md),
[`T: Eq`](docs/language.md#ограничение-t-eq) and [small C records](docs/language.md#структуры-по-значению-в-c-abi).

## VOLT 0.3.0 language specification

This describes the implemented language and its reference compiler, targeting
`linux-x86_64` (Linux, x86-64 System V ABI). The [roadmap](ROADMAP.md) and the
[slice proposal](docs/slices-proposal.md) describe future work, not additional
guarantees of this version.

**Contents:** [Source and compiler](#0-source-text-and-compiler) ·
[Types and conversions](#1-bindings-types-and-conversions) ·
[Expressions](#2-expressions) · [Statements](#3-statements-and-cleanup) ·
[Functions and ABI](#4-functions-and-abi) ·
[Data types and matching](#5-structures-enums-and-matching) ·
[Memory](#6-arrays-slices-pointers-and-memory) ·
[Modules](#7-modules-and-program-start) · [Library](#8-standard-library) ·
[Limits](#9-implementation-boundaries).

### 0. Source text and compiler

- A colon introduces a block. Statements in the same block use the same
  indentation; a nested block uses a greater indentation. `native fn` uses
  braces for its assembly body, not for ordinary VOLT statements.
- Identifiers are case-sensitive and have the form `[A-Za-z_][A-Za-z0-9_]*`.
  `#` and `//` introduce line comments; `/* … */` comments do not nest.
- Integers can be decimal, hexadecimal (`0xFF`), or binary (`0b1010`). Digits
  can use separators such as `1_000`. Decimal floats have a fractional part
  (`1.25`) or exponent (`2e-3`). A float literal starts as `f64`; an integer
  literal is `i64`, or `u64` if it is larger than `i64`'s maximum and fits in
  `u64`. A literal outside the supported range is a compile-time error.
- Strings use double quotes and `char` uses single quotes. The escape sequences
  are `\n`, `\r`, `\t`, `\\`, `\"`, `\'`, and `\0`; `\0` is valid only in a
  `char` literal. `char` represents a byte, not an arbitrary Unicode character.
  The compiler accepts up to 8 MiB per source file and rejects NUL bytes in it.

| Command | Result |
| --- | --- |
| `./volt prog.volt -o prog` | Write a Linux ELF executable. `--out` is an alias for `-o`. |
| `./volt prog.volt -g -o prog` | Add DWARF 4 mappings from named functions to their declaration lines. |
| `./volt prog.volt --run` | Compile and return the program's exit status; remove the temporary executable when `-o` is not supplied. |
| `./volt prog.volt --emit-asm` | Emit the assembly listing only; the default name is derived from the source path. |
| `./volt prog.volt -S prog.s -o prog` | Write both an assembly listing and an ELF executable. `--asm-file` is an alias for `-S`. |
| `./volt prog.volt --parse` | Print the syntax tree without type checking or generating machine code. |
| `./volt --version` | Print the compiler version. |

`--target linux-x86_64` is the default and only target. With no output path,
the compiler puts the ELF in `$TMPDIR` or `/tmp`. The bootstrap does not use
an external assembler or linker.

Errors in loaded sources include a bounded excerpt and a byte column when
known. `-g` works with ELF output only. It also maps the startup wrapper to
the first executable statement in the entry file, when present. It does not
map each statement or describe local variables and types.

### 1. Bindings, types, and conversions

```volt
let count: i64 = 42
let ratio = 3.14
let byte: u8 = 255
const LIMIT: i64 = 100
print(count, ratio, byte, LIMIT)
```

| Type | Size in bytes | Meaning |
| --- | --- | --- |
| `i8`, `i16`, `i32`, `i64` | 1, 2, 4, 8 | Signed integers |
| `u8`, `u16`, `u32`, `u64` | 1, 2, 4, 8 | Unsigned integers |
| `f32`, `f64` | 4, 8 | IEEE 754 floating-point values |
| `bool` | 1 | `true` or `false` |
| `char` | 1 | Byte value, 0–255; printed as a byte, unlike `u8` |
| `string`, `ptr<T>` | 8 each | An immutable NUL-terminated string, or a raw pointer to `T` |
| `fnptr<(A, B) -> R>` | 8 | Typed native function address for C callbacks |
| `[N]T` | `N × sizeof(T)` | Fixed-size array |
| `[]T` | 16 | Read-only slice: pointer and element count |
| `[]mut T` | 16 | Mutable slice with exclusive lexical access |
| Structure type | Depends on its fields | Named aggregate with natural alignment |
| Enum type | 8 without payload | Nominal `i64` discriminant and optional variant payload |
| `Option<T>`, `Result<T,E>` | Depends on the payload | Built-in, inline tagged values |

The aliases are `int = i64`, `uint = u64`, and `float = f64`. A local `let`
is mutable. Without a type annotation, its type is inferred from the initializer;
without an initializer, an annotation is required and types that permit it are
zero-initialized. A `const` is immutable, at module or local scope. Its scalar
initializer is evaluated at compile time: supported expressions include
literals of eligible types, arithmetic, casts, enum variants, `sizeof`,
`alignof`, and earlier constants. Ordinary function calls are not const evaluation.
Constants can have integer, floating-point, `bool`, `char`, or payload-free enum types,
not `string`, pointers, or aggregates.

`as` performs explicit casts. Initialization, assignment, ordinary declared
parameters (including foreign calls), and return values share numeric conversion
rules. An integer must fit the destination; narrowing never silently wraps.
Float-to-integer conversion truncates toward zero, and traps on NaN, infinity,
or an out-of-range result. Integer-to-float conversion rounds directly to
destination precision, ties to even; `f64` to `f32` can overflow to infinity.
Arithmetic and comparison do not mix integers and floats without `as`.
For mixed signed/unsigned integer operands the common type is unsigned if the
unsigned width is equal or larger, otherwise it is the wider signed type.
Generic type inference and `Option`/`Result` constructors require exact matching
where described below; numeric conversions do not reconcile mismatched payloads.

### 2. Expressions

| Precedence, low to high | Operators |
| --- | --- |
| 1–3 | `or`, then `and`, then `not` |
| 4 | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| 5–7 | bitwise `\|`, then `^`, then `&` |
| 8 | `<<`, `>>` |
| 9 | `+`, `-` |
| 10 | `*`, `/`, `%` |
| 11 | prefix `-`, `*`, `&` |
| 12 | named calls, field access `.`, indexing/slicing `[]`, `as`, postfix `?` |

- Integer arithmetic traps on overflow or division by zero, including overflow
  in unsigned arithmetic. Integer division truncates toward zero:
  `-7 / 2 == -3` and `-7 % 2 == -1`. `%` is not a floating-point operator.
- The shift count must be in `[0, bit_width)` for the left operand. Signed right
  shift preserves the sign bit, unsigned right shift fills with zeros. Left
  shift discards high bits rather than trapping on their loss; for example,
  `(64 as i8) << 1` is `-128`.
- Floating-point arithmetic follows IEEE 754. Infinity and NaN can be results;
  unary minus changes the sign, including for zero. In numeric or boolean
  conditions, zero, `false`, and NaN are false; other numeric values and
  `true` are true. `and` and `or` short-circuit and return `bool`.
- `sizeof(T)` and `alignof(T)` are compile-time `i64` byte counts. `len(x)`
  returns an array or slice length; `str_len(s)` returns a string's byte length.
  Strings use content equality with `==` and `!=`, `s + t` for concatenation,
  and `s * n` for repetition.

### 3. Statements and cleanup

`if` / `elif` / `else`, `while`, and `for` take indented bodies. A supported
statement can also follow the colon on the same line (`if x < 0: return 1`).
Assignments, including `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`,
and `>>=`, are statements, not expressions. Arrays, structures, and
`Option`/`Result` do not serve as conditions. Use `match` or `?` for the built-in
result types.

`for i in a..b` is half-open; `for i in a..=b` includes the final bound.
Both bounds are evaluated once and converted to `i64` with range checks;
enum bounds are not accepted. `i` has type `i64`. Reversed ranges are empty;
equal bounds produce one iteration only with `..=`. `break` exits the nearest
loop and `continue` advances it. Ranges are syntax here, not first-class types.

`defer` registers a simple operation, such as a call or assignment, when
execution reaches it. Operations on exit from that block run last-in,
first-out on fallthrough, `return`, `break`, `continue`, or a propagated `?`.
Only scopes being exited are cleaned up. Locals used by `defer` must already
be declared, and are read when the deferred code runs. The return value is
saved before cleanup. A deferred operation cannot contain declarations, nested
`defer`, or control flow, including postfix `?`. `panic` and `exit` terminate
the process without unwinding it.

```volt
fn total() -> i64:
    let sum = 0
    defer print("cleanup", sum)
    for i in 1..=3:
        sum += i
    return sum

let answer = total()
print("total", answer)
```

### 4. Functions and ABI

An ordinary function is declared `fn name(arg: T) -> R:` followed by a body.
Omit `-> R` for a procedure with no result. Value-returning functions must
return a value on each path recognised by the compiler. Declare typed parameters
on the same line. Named arguments, defaults, nested functions, and overloads are not
supported. Functions are called by name. `unsafe fn` permits unsafe operations
in its body and can only be called in an unsafe context.

- The x86-64 ABI has six integer-class argument registers (`rdi`, `rsi`,
  `rdx`, `rcx`, `r8`, `r9`) and eight independently allocated floating-point
  registers (`xmm0`–`xmm7`). Arguments that do not fit in their register class
  are placed in 8-byte stack slots in declaration order. The stack is aligned
  to 16 bytes before a call. A slice uses two integer registers or goes entirely
  on the stack. Ordinary VOLT functions receive structures and tagged values
  through implicit pointer arguments and copy them into local storage. A hidden
  caller-owned result pointer (`sret`) uses the first integer register, and the
  result is saved before `defer` runs. Arrays cannot be passed or returned by
  value. A read-only slice can be returned with `-> []T from input`.
- **Generic functions** such as `fn identity<T>(value: T) -> T:` are specialised
  at compile time for each inferred type combination. Inference uses arguments,
  including type arguments of nested structures and pointers. Conflicting types
  for the same parameter are rejected; `T: Eq` is checked at the call site.
  Generic foreign/assembly functions are not implemented.
- **C FFI:** `unsafe extern fn` declares an external symbol with a fixed
  signature. `link "-lc"` requests a shared ELF library. A C-facing call uses
  supported scalar and pointer types. A payload-free VOLT enum uses `i64`, not
  C's enum representation. Pass aggregate data via pointers to caller-owned
  storage, except that `extern struct` opts into naturally aligned scalar-field
  structs of at most 16 bytes for direct `extern fn` calls. Other aggregates by
  value, variadic calls and automatic exports are unsupported.
- **Callbacks:** `fnptr<(A, B) -> R>` or `fnptr<(A, B)>` (no return value)
   describes a supported scalar C signature. In `unsafe`, pass
   `callback(named_function)` to C. The compiler checks the signature; excess
   scalar arguments use stack slots just as in direct C calls.
   A local variable or parameter of this type can be called as `f(args)` in
   `unsafe`. The types and argument count are checked. A null target exits
   before argument evaluation; direct names retain priority. Casting a raw
   address is unsafe and does not validate the external signature or lifetime.
   Callbacks do not capture a lexical environment.
- **Native code:** `native fn` uses a supported subset of Intel x86-64
  assembly and is always unsafe. The compiler emits the prologue and epilogue;
  the body must not contain `ret`. The function must honour the calling
   convention, including any required preservation of registers and the stack.
   The first stack argument is at `[rbp+16]` after the prologue.

```volt
native fn raw_add(a: i64, b: i64) -> i64:
{
    mov rax, rdi
    add rax, rsi
}

unsafe:
    print(raw_add(2, 3))
```

This example passes a named VOLT function to the standard C `qsort` routine;
it requires the system libc library.

```volt
link "-lc"
unsafe extern fn qsort(base: ptr<i32>, n: u64, size: u64, cmp: fnptr<(ptr<char>, ptr<char>) -> i32>)

unsafe fn compare(a: ptr<char>, b: ptr<char>) -> i32:
    let left: i32 = *(a as ptr<i32>)
    let right: i32 = *(b as ptr<i32>)
    if left < right: return -1
    if left > right: return 1
    return 0

let values: [3]i32 = [5, 3, 4]
unsafe: qsort(&values[0], 3 as u64, 4 as u64, callback(compare))
print(values[0], values[1], values[2]) # 3 4 5
```

### 5. Structures, enums, and matching

Structures declare named fields and construct values with positional arguments
in declaration order. Fields use natural alignment; the structure alignment
is the maximum field alignment and the size is rounded up to it. Nested
structures, arrays of structures, and by-value copies are supported. Generic
structures have a separate layout for each type combination. Constructors use
the destination type when provided, otherwise infer type arguments from the
fields. A recursive structure may refer to itself through a pointer.

```volt
struct Item<T>:
    index: i64
    value: T

fn item_value<T>(item: Item<T>) -> T:
    return item.value

let item: Item<u32> = Item(0, 42)
print(item.index, item_value(item), sizeof(Item<u32>))
```

An `enum` stores an `i64` tag. If the first variant has no explicit value, it
gets zero. Each later implicit value is the previous discriminant plus one;
an explicit declaration like `Green = 4` changes that sequence. Use
`Name.Variant` for a variant without data; plain enums can be compared or cast
to `i64`. Variants such as `Number(i64)` carry one scalar value and are
constructed with `Token.Number(42)`. Discriminants must be unique.

`match` is a statement, not an expression. It evaluates the subject once and
requires at least one arm. Its patterns include `_`, `Enum.Variant`,
`Enum.Variant(name)`, `None`, `Some(name)`, `Ok(name)`, and `Err(name)`. Every
variant must be covered exactly once; `_` covers the remaining variants and is
last. Other types, overlapping
patterns, guards, and structural destructuring are unsupported. Each binding
is visible only in that arm. Copyable payloads are copied; `Ok` moves an owned
buffer out of its result. For `Option`/`Result`, match a local value, parameter,
or function result rather than a direct constructor.

`Option<T>` has `None` or `Some(T)`. `Result<T,E>` has `Ok(T)` or `Err(E)`.
Use an explicit type or sufficient context to determine both type arguments
when a constructor alone is ambiguous. For example, `let r: Result<i64, i32> =
Err(22 as i32)` has a payload of exactly `i32`. Payloads may be scalars, copyable
structures, enums, or copyable nested `Option`/`Result`, but not arrays or slices
by value. [`Result<OwnedBuffer, E>`](docs/owned-buffer.md) is move-only with a
copyable error type: `Ok` moves the buffer in, and `match` or `?` consumes the
result. Tagged values can be locals, parameters, and results in ordinary VOLT
functions, but not globals, constants, fields, array elements, or zero-initialized
bindings. Only copyable tagged values can be reassigned; the right-hand side
is evaluated once and must have the same type.

The postfix `?` extracts the successful payload. `None` or `Err` returns from
the enclosing ordinary VOLT function, running its registered `defer` actions and drops.
With `Option`, the enclosing return type must be the same `Option<T>`. With
`Result`, the error type must match exactly, but the success types can differ.
`?` may appear in a nested expression and is not available in `extern` or
`native` code.

```volt
fn square(input: Result<i64, i32>) -> Result<i64, i32>:
    let value = input?
    return Ok(value * value)

let input: Result<i64, i32> = Ok(7)
let result = square(input)
match result:
    Ok(value): print(value)
    Err(code): print(code)
```

Tagged values are inline, not heap boxes. The first eight bytes are an `i64`
tag: `Option` uses 0 for `None`, 1 for `Some`; `Result` uses 0 for `Ok`, 1 for
`Err`. Let `P` and `A` be the payload size and alignment (the maxima over
`T` and `E` for `Result`). The payload offset is `align_up(8, A)`; the overall
alignment is `max(8, A)` and the size is
`align_up(align_up(8, A) + P, max(8, A))`. `align_up` here means rounding up to
a multiple, not a VOLT function. `None` has zeroed payload storage. The internal
VOLT call convention copies tagged parameters into the callee and tagged
results through `sret`, preserving the result across cleanup. It is not a
stable C type layout or call contract.

### 6. Arrays, slices, pointers, and memory

- **Arrays:** `[N]T` uses a fixed element count; `N` is an integer literal, not
  a generic parameter. Indexing checks `0 <= i < N`. List initializers must fit;
  omitted trailing elements are zeroed. Without an annotation, a non-empty
  list initializer determines the length and takes its type from its first
  element. Arrays of the same type can be copied;
  use slices or pointers to pass their data to a function. Local arrays use
  stack storage.
- **Slices:** `data[start..end]` makes a checked read-only `[]T` view;
  `mut data[start..end]` creates an exclusive `[]mut T` of a local array.
  Several read-only views may coexist; a mutable view prevents all direct
  array access until block exit, including `defer`. A mutable view can be
  re-sliced for reading: `buf[0..n]` (without `mut`) yields a `[]T` child,
  and while that child lives, writing through the mutable view or passing
  it as `[]mut` is rejected; writes resume after the child's block ends.
  Read-only views can be
  re-sliced or returned from an explicit parameter source. Slice bindings
  cannot be reassigned or stored in aggregates, and do not cross the C ABI.
- **Raw pointers:** `&place` produces a pointer to an addressable target.
  Dereference, indexing, accessing a field through a pointer, pointer
  arithmetic, and raw casts require `unsafe`. `p + i`, `i + p`, and `p - i`
  use steps of `sizeof(T)`; compare pointers of the same type, not a pointer
  and an integer. Raw operations do not check lifetime, address, or bounds.
- **Strings:** a `string` is an immutable NUL-terminated byte sequence, not an
  owning, counted buffer. Indexing checks bounds and returns a byte, not a
  Unicode character. `str_len` scans to NUL, as does checked indexing. String
  literals cannot contain NUL. The shared arena for dynamic concatenation and
  repetition is 1 MiB per process; exhaustion traps. This is not a cap on
  explicit byte buffers. Use an explicit unsafe cast at a C string boundary.
  [`TextView`](docs/text-view.md) is a separate length-tagged view for O(1)
  indexing and zero-copy subranges, with explicit C-string conversion.
- **Buffers:** `ByteBuffer` stores bytes, including NUL, with length and
  capacity. `Buffer<T>` does the same for typed elements. Start from zeroed
  storage, keep one owner, free it explicitly (often with `defer`), and do not
  retain pointers to elements after growth or release. `buffer_at` checks
  its index. `ByteVec` instead offers a checked handle and `ByteView` a
  counted range: growth does not invalidate the range, but dropping the
  underlying buffer invalidates all copies and views. The handle registry is
  limited to 64 simultaneous buffers; `get` operations return `Result` and
  invalid handles are reported rather than dereferenced.
- **Lexical buffer reads:** [`BorrowBuffer<T>`](docs/buffer-borrow-proposal.md)
  has checked owner handles and read-only views that end with their block.
  Mutations and release through any owner alias are rejected while a reader is
  active. The owner still requires explicit release; element copies are shallow.
- **Single ownership:** [`OwnedBuffer`](docs/owned-buffer.md) and
  [`fs.OwnedFd`](docs/owned-fd.md) move through `let`, calls and returns. Live
  owners drop once after their block's `defer`: the buffer frees its storage
  and the descriptor is closed exactly once, with no double close of a reused
  descriptor number. `owned_buffer_bytes(&buffer)` lends the bytes as a `[]u8`
  slice without copying; the buffer cannot move while the slice is alive.

```volt
fn sum(values: []i64) -> i64:
    let total = 0
    for i in 0..len(values):
        total += values[i]
    return total

let data: [4]i64 = [10, 20, 30, 40]
let middle: []i64 = data[1..3]
print(sum(middle)) # 50
```

### 7. Modules and program start

`use NAME` (or `use A, B`) looks for `NAME.volt` beside the importing source,
then under the compiler's installation root in `vstd/`, `browser/modules/`,
`gpu/modules/`, and `tools/modules/`, in that order. Module names do not depend
on the source directory layout. A module is loaded once; dependencies initialise before
the modules that import them. Cycles are errors. Files without a `module NAME`
header retain flat imports. A namespaced file exports declarations with `pub`,
and `use NAME [as ALIAS]` makes them available by qualified names such as
`fs.open`. Public record constructors and fields remain private. `io` and
`str` are auto-imported. A module can declare `const`, global `let` with a
constant initializer, and top-level calls for initialization.

The entry source is different: its top-level executable statements run after
module initialization, before a locally declared `main`. Top-level `let` in
that file is local to the generated entry point, not shared module storage.
Use `fn main() -> i64` to return an exit status, or `fn main():` for a
procedure. `main` must have no parameters; `use process` provides `argc` and
`arg_at`. With no returned status the program exits with 0.

`link "-lNAME"` requests `libNAME.so`; `-l:FILE` uses an exact library filename,
and `-LPATH` adds an ELF library search path at build time. The Linux dynamic
loader resolves linked libraries at runtime. These declarations do not
provide a full libc startup/shutdown protocol.
An explicit [`--manifest volt.mod`](docs/volt-mod.md) adds C-library names and
compile-time search paths. It does not download packages or run build scripts.

### 8. Standard library

| API | Contract |
| --- | --- |
| Intrinsics | `sin`, `cos`, `tan`, `log2`, `atan2`, `sqrt`, `abs`, `min`, `max`, `len`, `sizeof`, and `alignof`. `panic` reports a failure to stderr and exits; `exit` terminates with a status. Neither unwinds scopes. |
| Linux runtime | `read`, `write`, `write_all`, `open`, `close`, `mmap`, `munmap`, and `brk` expose low-level operations. Callers must obey the raw-memory contract and check return values; these are not ownership abstractions. |
| `io`, `str` | `print` separates values with spaces and appends a newline; `put_*`, `put_err`, `put_errnl`, and `nl` support explicit output. Integer output is decimal; floats normally use six fractional digits, with scientific notation for large values. Writes fail with `panic` rather than silently dropping an error. `str_len`, `str_eq`, `str_concat`, and `str_repeat` operate on NUL strings. |
| [`math`](vstd/math.volt), [`math3d`](vstd/math3d.volt) | Numeric constants and helpers (including `powi`, `ipowi`, and `hypot`), vectors and matrices. Integer powers and factorials are checked; integer negative powers truncate the reciprocal toward zero. |
| [`time`](vstd/time.volt) | `monotonic_ms() -> Result<i64, i32>` measures intervals, not wall time. |
| [`fs`](vstd/fs.volt) | `file_size` returns the logical size, including holes. `create_dir` creates one directory, `rename_path` moves an entry without replacing the destination, and `remove_file`/`remove_dir` delete a file or symlink and an empty directory, respectively. These are synchronous Linux operations with positive `errno` in `Err`. `fs.read_all(path, max_bytes)` reads a whole file into a move-only `Result<OwnedBuffer, IoError>`: `Err(EINVAL)` for `max_bytes <= 0`, `Err(EFBIG)` above the limit, otherwise the kernel's positive errno; an empty file and exactly `max_bytes` are valid, and the buffer is never released by hand. |
| [`process`](vstd/process.volt) | `argc`, `arg_at`, and the raw environment read the initial Linux stack. `arg_at` returns a borrowed string or `Err(22)` for an invalid index. `process_exec_wait` runs an executable without a shell. |
| [`event`](vstd/event.volt) | `poll` takes `[]mut EventPollFd` and writes `revents` within that slice; the caller does not need `unsafe`. `poll_readable` returns flags for one descriptor. The timeout is signed `i32` milliseconds (`-1` waits indefinitely, `0` checks without waiting). `poll` returns 0 on a timeout. Nonblocking monotonic `timerfd` supports one-shot and periodic timers via `timer_create`, `timer_set`, `timer_read`, and `timer_close`; `first_ms = 0` disarms, and a read without an expiration reports `Err(11)`. |
| Stream I/O in [`event`](vstd/event.volt) | `stream_pair` opens two local nonblocking socket ends. Close both with `event_close`. `try_read(fd, buffer: []mut u8)` and `try_write(fd, buffer: []u8)` attempt a single operation on a connected stream socket without `unsafe`, taking the length from the slice; an empty slice returns `Err(EINVAL)`, so `Ok(0)` always means end of stream. Handle short counts and `EAGAIN` with `poll`. Writes do not raise `SIGPIPE`. The raw pointer and length forms remain as `unsafe try_read_raw`/`try_write_raw`. |
| [`arena`](docs/arena.md) | Fixed-capacity linear allocation for temporary objects. `unsafe` callers manage the arena and must stop using all allocated pointers on reset or drop. |
| [`thread`](docs/thread.md) | Optional pthreads on Linux x86-64 with glibc ≥ 2.34. `unsafe` thread creation and joining, mutexes with try-lock, and condition variables with monotonic deadlines. Keep slots at stable addresses and worker data alive until a successful join. No compiler thread-safety checks. |
| [`channel`](docs/channel.md) | Synchronized, value-only `i64` messages, with blocking send/receive and `try` variants. Channel operations do not require `unsafe`; raw pthread creation and other shared state are still the caller's responsibility. |
| [`bytes`](vstd/bytes.volt), [`buffer`](vstd/buffer.volt), [`bytevec`](vstd/bytevec.volt), [`utf8`](vstd/utf8.volt) | Counted storage, checked byte handles, and UTF-8 code-point helpers. `utf8_next` consumes one byte on invalid input and returns U+FFFD. |
| [`json`](docs/json.md) | Read one UTF-8 JSON document (8 MiB, at most 64 nested containers); inspect fields, array elements, booleans and exact numeric spans. Decoding and quoting strings use caller-owned buffers and byte lengths. `JsonValue` borrows the unchanged input. No general object/array serializer. |
| [`http`, `dns`, `tls`](docs/http.md) | Bounded HTTP/IPv4 GET, hostname resolution, and HTTPS through OpenSSL 3 with certificate and hostname checks. This is not a general socket or async runtime API. |
| [`sdl`, `window`](docs/sdl.md), [`html`, `css`](docs/html-engine.md) | Optional SDL2 bindings and partial HTML/CSS support for the native browser. |
| [`browser_search`](docs/search.md), [`cuda`](docs/cuda.md) | Offline local-document index and optional CUDA driver bindings. CUDA loads `libcuda.so.1` on request and can execute supplied PTX; VOLT does not generate GPU code. |

### 9. Implementation boundaries

Linux x86-64 and the documented ABI subset are the only supported target.
Runtime checks on indexing and arithmetic do not make raw pointers and FFI
memory-safe. `unsafe` is a caller obligation, not a sandbox. Slice borrow checks
are lexical, and automatic destruction is limited to the registered owning
types `OwnedBuffer` and `fs.OwnedFd`, including
when held in a `Result`. Ordinary `Buffer<T>` and `fs.Descriptor` still require manual release.
Traits, const generics, closures,
tuple types, macros, `async`/`await`, arbitrary inline assembly blocks, and a
garbage collector are not implemented. JavaScript promises and GPU dispatch
are separate integrations.

The language behaviour is exercised by the [golden tests](tests/run.py),
[compiler regression tests](tests/regressions.py), and
[bootstrap verification](bootstrap/README.md).
