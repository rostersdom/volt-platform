# VOLT Platform

[English](README.md) · [Русский](README.ru.md) · **Español**

**VOLT Platform** reúne un lenguaje de programación de sistemas, un compilador
escrito en VOLT, una biblioteca estándar y un navegador nativo para **Linux
x86-64**. El compilador genera código máquina x86-64 y escribe ejecutables ELF
directamente, sin ensamblador ni enlazador externos. Los programas que no enlazan
bibliotecas externas pueden ejecutarse sin libc.

## Inicio rápido

```sh
git clone https://github.com/rostersdom/volt-platform.git
cd volt-platform
sha256sum -c bootstrap/SHA256SUMS
make compiler
./volt apps/hello.volt --run
```

Salida esperada: `Hello, VOLT!`. Para guardar el ejecutable, usa
`./volt apps/hello.volt -o apps/bin/hello`.

```volt
fn main() -> i64:
    print("Hello, VOLT!")
    return 0
```

El compilador se construye a partir del [binario inicial estático](bootstrap/README.md)
incluido en el repositorio, sin Python ni un compilador C/C++. `make verify-bootstrap`
construye dos generaciones sucesivas con `PATH` vacío y las compara byte a byte.

## Componentes

| Componente | Función |
| --- | --- |
| [`compiler/`](compiler/) | Compilador escrito en VOLT. Incluye inferencia de tipos, genéricos, comprobación de índices y de desbordamientos de enteros, `match`, `Option`, `Result`, `defer` y una interfaz limitada para C (System V). |
| [`vstd/`](vstd/) | Tipos y búferes básicos, archivos, red, [JSON](docs/json.md) e integraciones opcionales como [CUDA](docs/cuda.md). |
| [`apps/`](apps/) y [`examples/`](examples/) | Navegador, [búsqueda local](docs/search.md) y ejemplos. La búsqueda solo indexa los archivos que le indiques y no accede a Internet. |
| [`tests/`](tests/) y [`benchmarks/`](benchmarks/) | Pruebas de salida, regresión e integración local, además de mediciones reproducibles. |

## Probar el navegador VOLT

```sh
make browser
apps/bin/browser examples/layout.html
```

Se necesitan las bibliotecas de desarrollo de SDL2, Cairo, Pango, OpenSSL 3,
zlib, libwebp y TurboJPEG 3. VOLT analiza HTML y CSS y calcula el diseño;
Cairo, Pango y SDL dibujan y muestran el resultado. No incorpora Chromium,
WebKit ni otro navegador.

- **Vídeo:** Ejecuta `make browser-media` y abre
  `apps/bin/browser examples/video.html`. Un proceso opcional con FFmpeg/libav
  decodifica archivos WebM, MP4 y Ogg; VOLT controla la reproducción y SDL emite
  el audio. La compilación necesita `pkg-config`, libav y libseccomp.
- **JavaScript:** Ejecuta `make browser-js` (Duktape y libseccomp) y abre
  `apps/bin/browser --js examples/interactive.html`. El proceso aislado ofrece
  un DOM limitado y ejecuta los scripts clásicos compatibles del mismo origen.
  [QuickJS-NG](docs/html-engine.md#экспериментальный-javascript)
  es una alternativa opcional para la sintaxis moderna y las promesas.
- **Compatibilidad web:** La compatibilidad con HTML, CSS y JavaScript es parcial.
  La vista experimental de YouTube reconoce enlaces a vídeos, pero solo puede
  reproducir un archivo directo compatible, si está disponible. El reproductor
  oficial de YouTube, MediaSource (MSE) y DRM no están disponibles.

Consulta la [documentación del navegador](docs/html-engine.md) para más detalles.

## Pruebas y documentación

```sh
make verify-bootstrap
python3 tests/run_all.py
python3 tests/cuda_integration.py  # aparte; VOLT_CUDA_GPU=1 exige una GPU real
```

La suite completa necesita Python 3 y las bibliotecas de desarrollo del navegador.
Las pruebas de los procesos opcionales se omiten si faltan sus dependencias.
El ejemplo CUDA necesita un controlador NVIDIA compatible para ejecutarse en una
GPU, pero no requiere CUDA Toolkit ni `nvcc` para compilarse. El compilador y
el navegador básicos no necesitan CUDA.

[Referencia del lenguaje](docs/language.md) · [Hoja de ruta](ROADMAP.md) · [Licencia MIT](LICENSE)
