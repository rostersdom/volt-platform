# VOLT Platform

**English** · [Русский](README.ru.md) · [Español](README.es.md)

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

## What is in the repository?

| Component | What it does |
| --- | --- |
| [`compiler/`](compiler/) | The VOLT compiler, written in VOLT. It supports type inference, generics, checked array indexing and integer arithmetic, `match`, `Option`, `Result`, `defer`, and a limited System V C FFI. |
| [`vstd/`](vstd/) | Core types and buffers, file and network APIs, [JSON](docs/json.md), and optional bindings including [CUDA](docs/cuda.md). |
| [`apps/`](apps/) and [`examples/`](examples/) | The browser, an [offline search CLI](docs/search.md), and examples. Search indexes only the local files you provide; it does not crawl the web. |
| [`tests/`](tests/) and [`benchmarks/`](benchmarks/) | Golden-output tests, compiler regressions, loopback integration tests, and repeatable benchmarks. |

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

See the [browser documentation](docs/html-engine.md) for setup and limits.

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

[Language reference](docs/language.md) · [Roadmap](ROADMAP.md) · [MIT license](LICENSE)
