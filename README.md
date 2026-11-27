# VOLT Platform

**English** · [Русский](README.ru.md) · [Español](README.es.md)

[Quick start](#quick-start) · [Components](#components) · [Browser](#try-the-volt-browser) ·
[Platform specification](#platform-specification) · [Language reference](docs/language.md)

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
| **VOLT Language** | The canonical [language reference](docs/language.md) (Russian), self-hosted [`compiler/`](compiler/) and static [`bootstrap/`](bootstrap/). Build `./volt` with `make compiler`. |
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
| Browser UI and rendering | VOLT owns navigation, layout, and hit testing. Local HTML and HTTP(S), address-bar web search (`VOLT_SEARCH_URL`), session history, anchors, stop/retry, resize, zoom, and 640×480 PNG screenshots are supported. HTML is capped at 2 MiB; Grid, Flexbox, media queries, and PNG/JPEG/WebP support are limited to the documented subset. |
| Page resources | Styles and images use same-origin HTTP(S) or confined local paths. Classic scripts run only with `--js`; external scripts come from the same origin over HTTP(S), including redirects, using the document peer's IP address. A Content Security Policy disables scripts. The worker has no direct network access, with a 750 ms initialization budget and at most 16 scripts totalling 64 KiB; same-origin `fetch`/`XMLHttpRequest` go through a bounded browser bridge, with a parent-owned cookie jar hidden from scripts and a build-once createElement/appendChild/classList DOM API. |
| Media | Direct video is loaded on request, up to 32 MiB. `volt-media` decodes supported streams; VOLT presents frames up to 960×540 and sends PCM to SDL. An internal fragmented-MP4 mode supports clear H.264 with optional AAC, up to 1 MiB per append and 32 MiB per session. It is not a web MediaSource implementation. |
| Local search | `volt-search` indexes supplied HTML and UTF-8 text files in memory, matches Russian and ASCII words case-insensitively, and writes linked HTML results. It accepts at most 64 files of 256 KiB each and never sends queries over the network. |
| GPU | `use cuda` loads the NVIDIA driver on demand on Linux x86-64 with glibc 2.34 or later. The demo runs supplied PTX, transfers data, synchronizes, and releases resources. It does not compile VOLT functions to GPU code. |

[Browser and media](docs/html-engine.md) · [Online browser](docs/browser-online.md) ·
[HTTP/TLS](docs/http.md) · [JSON](docs/json.md) · [Local search](docs/search.md) ·
[CUDA](docs/cuda.md)

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

## Language reference

The canonical specification of the implemented language lives in
[docs/language.md](docs/language.md) (Russian). It covers the source format
and compiler CLI (including `-g` for GDB stepping, arguments, and scoped locals),
the type system, expressions,
statements with `defer`, functions and the supported x86-64 System V ABI
subset, structures, enums and `match`, arrays, slices, pointers and memory,
modules, the standard library, and the documented implementation boundaries.
The [roadmap](ROADMAP.md) and the [slice proposal](docs/slices-proposal.md)
describe future work, not additional guarantees of this version.

Implemented highlights, each documented under `docs/`:

- Statically typed integers and floats with checked arithmetic, immutable
  strings, structures, and payload enums — [language reference](docs/language.md).
- [Lexical slice borrowing](docs/slice-borrows.md): read-only `[]T` and
  exclusive `[]mut T` views with block-scoped rules, re-slicing of `[]mut T`,
  and temporary slices released at the end of the statement or before the
  body of a condition.
- [Single ownership](docs/owned-buffer.md): move-only `OwnedBuffer` and
  [`fs.OwnedFd`](docs/owned-fd.md) with an automatic drop after `defer`,
  plus `fs.read_all`, `fs.read_into`, `fs.wait_readable`, and `fs.close_owned`.
- [Compound `Option`/`Result`](docs/option-result-payloads.md) with `match`
  and the postfix `?` operator, including the move-only
  `Result<OwnedBuffer, E>` and `Option<OwnedBuffer>` forms.
- Generic functions and structures with the
  [`T: Eq`](docs/language.md#ограничение-t-eq) constraint, specialised at
  compile time.
- C FFI: `unsafe extern fn`, typed `fnptr` callbacks,
  [small `extern struct` records by value](docs/language.md#структуры-по-значению-в-c-abi),
  and `native fn` assembly — [language reference](docs/language.md).
- Standard library: files, `poll`-based event readiness, threads and
  channels, JSON, and HTTP/TLS — see the links in
  [Tests and documentation](#tests-and-documentation).

The language behaviour is exercised by the [golden tests](tests/run.py),
[compiler regression tests](tests/regressions.py), and
[bootstrap verification](bootstrap/README.md).
