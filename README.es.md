# VOLT Platform

[English](README.md) · [Русский](README.ru.md) · **Español**

[Inicio rápido](#inicio-rápido) · [Navegador](#probar-el-navegador-volt) ·
[Especificación de la plataforma](#especificación-de-la-plataforma) ·
[Referencia del lenguaje](docs/language.md)

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

| Componente | Fuentes y compilación |
| --- | --- |
| **Lenguaje VOLT** | [Especificación](docs/language.md) canónica (en ruso), [`compiler/`](compiler/) y binario inicial estático en [`bootstrap/`](bootstrap/). `make compiler` genera `./volt`. |
| **Biblioteca estándar** | [`vstd/`](vstd/): entorno de ejecución, búferes, archivos, red y analizadores compartidos, como [JSON](docs/json.md) y HTML. |
| **Navegador y multimedia** | [`browser/`](browser/): navegador nativo, módulos de diseño y renderizado, procesos JavaScript y decodificador de vídeo. Usa `make browser`, `make browser-js` o `make browser-media`. |
| **GPU** | [`gpu/`](gpu/): enlaces opcionales a [CUDA](docs/cuda.md) y ejemplo PTX. `make cuda` compila el ejemplo; la GPU solo se necesita al ejecutarlo. |
| **Herramientas** | [`tools/`](tools/): [búsqueda local](docs/search.md) y lanzador `.volt` para Linux. Usa `make tools`, `make search` o `make launcher`. |
| **Ejemplos y pruebas** | [`apps/`](apps/) y [`examples/`](examples/) contienen ejemplos y recursos; [`tests/`](tests/) y [`benchmarks/`](benchmarks/) verifican los componentes. |

El compilador y la biblioteca estándar funcionan sin los componentes opcionales.
Los ejecutables de aplicaciones y procesos auxiliares se siguen guardando en `apps/bin/` por defecto.

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

Consulta la [documentación del navegador](docs/html-engine.md) y la lista de
[código y dependencias](docs/html-engine.md#исходники-и-внешние-зависимости),
que distingue el navegador de la propuesta TNet.

## Especificación de la plataforma

| Subsistema | Funciones implementadas y límites |
| --- | --- |
| Compilación | Un ELF estático inicial construye el compilador a partir de código VOLT. `volt` carga módulos, analiza el código, comprueba tipos, codifica x86-64 y escribe ELF. `make verify-bootstrap` compara dos generaciones con `PATH` vacío. |
| Navegación y renderizado | VOLT se encarga de la navegación, el diseño y la detección de clics. Admite HTML local y HTTP(S), historial de sesión, anclas, detener y reintentar cargas, zoom y capturas PNG de 640×480. El HTML está limitado a 2 MiB; Grid, Flexbox, consultas de medios y PNG/JPEG/WebP tienen compatibilidad parcial. |
| Recursos de página | Los estilos e imágenes se cargan por HTTP(S) del mismo origen o desde rutas locales confinadas. Los scripts clásicos solo se ejecutan con `--js`; los externos usan HTTP(S) del mismo origen, incluidas las redirecciones, y la IP del documento. Una política CSP desactiva los scripts. El proceso de JavaScript no accede a la red. El inicio está limitado a 750 ms y a 16 scripts de 64 KiB en total. |
| Vídeo y audio | La carga bajo demanda está limitada a 32 MiB. `volt-media` decodifica los formatos admitidos; VOLT muestra fotogramas de hasta 960×540 y envía PCM a SDL. El modo interno de MP4 fragmentado admite H.264 sin cifrado, con AAC opcional, hasta 1 MiB por inserción y 32 MiB por sesión. No implementa la API web MediaSource. |
| Búsqueda local | `volt-search` indexa en memoria los archivos HTML o UTF-8 indicados, busca palabras rusas y ASCII sin distinguir mayúsculas de minúsculas y genera resultados HTML con enlaces. Admite hasta 64 archivos de 256 KiB, sin consultar la red. |
| GPU | `use cuda` carga el controlador NVIDIA bajo demanda en Linux x86-64 con glibc 2.34 o posterior. El ejemplo ejecuta PTX suministrado y gestiona transferencias, sincronización y liberación de recursos. No compila funciones VOLT para la GPU. |

[Navegador y multimedia](docs/html-engine.md) · [HTTP/TLS](docs/http.md) ·
[JSON](docs/json.md) · [Búsqueda local](docs/search.md) · [CUDA](docs/cuda.md)

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

[Referencia en ruso](docs/language.md) · [Hoja de ruta](ROADMAP.md) · [Licencia MIT](LICENSE)

Extensiones del núcleo: [módulos y `pub`](docs/modules.md), [propiedad y `drop`](docs/owned-buffer.md),
[vistas léxicas](docs/slice-borrows.md), [`TextView`](docs/text-view.md),
[`Option`/`Result` compuestos](docs/option-result-payloads.md), [enum con datos](docs/enum-payloads.md)
y [`T: Eq`](docs/language.md#ограничение-t-eq).

## Referencia del lenguaje

La especificación canónica del lenguaje implementado está en
[docs/language.md](docs/language.md) (en ruso). Describe el formato del código
fuente y la CLI del compilador (incluida la opción `-g` para recorrer sentencias
en GDB e inspeccionar argumentos y variables locales), el sistema de tipos, las
expresiones, las sentencias con `defer`,
las funciones y el subconjunto admitido del ABI System V x86-64, las
estructuras, los enum y `match`, los arreglos, las vistas, los punteros y la
memoria, los módulos, la biblioteca estándar y los límites documentados de la
implementación. La [hoja de ruta](ROADMAP.md) y la
[propuesta sobre vistas](docs/slices-proposal.md) describen trabajo futuro, no
garantías adicionales de esta versión.

Aspectos implementados, cada uno documentado en `docs/`:

- Enteros y flotantes con tipos estáticos y aritmética verificada, cadenas
  inmutables, estructuras y enum con datos —
  [referencia del lenguaje](docs/language.md).
- [Vistas léxicas](docs/slice-borrows.md): vistas de solo lectura `[]T` y
  exclusivas `[]mut T` con reglas por bloque, subdivisión de `[]mut T` y
  vistas temporales que se liberan al final de la sentencia o antes del
  cuerpo de una condición.
- [Propiedad única](docs/owned-buffer.md): `OwnedBuffer` y
  [`fs.OwnedFd`](docs/owned-fd.md) de solo movimiento, con liberación
  automática tras `defer`, además de `fs.read_all`, `fs.read_into`,
  `fs.wait_readable` y `fs.close_owned`.
- [`Option`/`Result` compuestos](docs/option-result-payloads.md) con `match`
  y el operador postfijo `?`, incluidas las formas de solo movimiento
  `Result<OwnedBuffer, E>` y `Option<OwnedBuffer>`.
- Funciones y estructuras genéricas con la restricción
  [`T: Eq`](docs/language.md#ограничение-t-eq), especializadas en tiempo de
  compilación.
- FFI con C: `unsafe extern fn`, callbacks tipados con `fnptr`,
  [registros `extern struct` pequeños por valor](docs/language.md#структуры-по-значению-в-c-abi)
  y ensamblador `native fn` — [referencia del lenguaje](docs/language.md).
- Biblioteca estándar: archivos, comprobación de disponibilidad con `poll`,
  hilos y canales, JSON y HTTP/TLS — consulta los enlaces de
  [Pruebas y documentación](#pruebas-y-documentación).

Las [pruebas de salida](tests/run.py), las
[regresiones del compilador](tests/regressions.py) y la
[verificación del binario inicial](bootstrap/README.md) ejercitan el
comportamiento del lenguaje.
