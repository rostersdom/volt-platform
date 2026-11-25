# VOLT Platform

[English](README.md) · [Русский](README.ru.md) · **Español**

[Inicio rápido](#inicio-rápido) · [Navegador](#probar-el-navegador-volt) ·
[Especificación de la plataforma](#especificación-de-la-plataforma) ·
[Especificación completa del lenguaje](#especificación-del-lenguaje-volt-030)

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
| **Lenguaje VOLT** | [Especificación](#especificación-del-lenguaje-volt-030), [`compiler/`](compiler/) y binario inicial estático en [`bootstrap/`](bootstrap/). `make compiler` genera `./volt`. |
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

## Especificación del lenguaje VOLT 0.3.0

Esta sección describe el lenguaje implementado por el compilador de referencia
para `linux-x86_64` (Linux y ABI System V x86-64). La [hoja de ruta](ROADMAP.md)
y la [propuesta sobre vistas](docs/slices-proposal.md) describen trabajo futuro,
no garantías adicionales de esta versión.

**Contenido:** [Código fuente y compilador](#0-código-fuente-y-compilador) ·
[Tipos y conversiones](#1-variables-tipos-y-conversiones) ·
[Expresiones](#2-expresiones) · [Sentencias](#3-sentencias-y-limpieza) ·
[Funciones y ABI](#4-funciones-y-abi) ·
[Tipos de datos y patrones](#5-estructuras-enumeraciones-y-patrones) ·
[Memoria](#6-arreglos-vistas-punteros-y-memoria) ·
[Módulos](#7-módulos-e-inicio-del-programa) · [Biblioteca](#8-biblioteca-estándar) ·
[Límites](#9-límites-de-la-implementación).

### 0. Código fuente y compilador

- Los dos puntos introducen un bloque. Las sentencias del mismo bloque tienen
  la misma sangría; un bloque anidado aumenta la sangría. Las llaves de
  `native fn` delimitan código ensamblador, no un bloque normal de VOLT.
- Los identificadores distinguen mayúsculas de minúsculas y siguen el patrón
  `[A-Za-z_][A-Za-z0-9_]*`. `#` y `//` inician comentarios de línea; los
  comentarios `/* … */` no se anidan.
- Los enteros pueden escribirse en decimal, hexadecimal (`0xFF`) o binario
  (`0b1010`). Se admiten separadores como `1_000`. Los literales de coma
  flotante decimales tienen una parte fraccionaria (`1.25`) o un exponente
  (`2e-3`). Su tipo inicial es `f64`. Un literal entero es `i64`, salvo que
  exceda el máximo de `i64` y quepa en `u64`. Los valores fuera del intervalo
  admitido producen un error de compilación.
- Las cadenas usan comillas dobles y `char`, comillas simples. Se admiten
  `\n`, `\r`, `\t`, `\\`, `\"`, `\'` y `\0`; `\0` solo es válido en `char`.
  Un `char` representa un byte, no cualquier carácter Unicode. El compilador
  admite 8 MiB por archivo fuente y rechaza bytes NUL en el código.

| Comando | Resultado |
| --- | --- |
| `./volt prog.volt -o prog` | Genera un ejecutable ELF. `--out` equivale a `-o`. |
| `./volt prog.volt -g -o prog` | Añade un mapa DWARF 4 de las funciones nombradas a sus líneas de declaración. |
| `./volt prog.volt --run` | Compila y devuelve el estado del programa. Elimina el ejecutable temporal si no se indica `-o`. |
| `./volt prog.volt --emit-asm` | Solo escribe el listado ensamblador, cuyo nombre por defecto se deriva del código fuente. |
| `./volt prog.volt -S prog.s -o prog` | Escribe el listado ensamblador y el ejecutable. `--asm-file` equivale a `-S`. |
| `./volt prog.volt --parse` | Muestra el árbol sintáctico sin comprobar tipos ni generar código máquina. |
| `./volt --version` | Muestra la versión del compilador. |

`--target linux-x86_64` es el único destino y el predeterminado. Sin `-o`, el
ELF se escribe en `$TMPDIR` o `/tmp`. La construcción desde el binario inicial
no necesita ensamblador ni enlazador externos.

Los errores en archivos cargados muestran un fragmento acotado y la columna
en bytes si se conoce. `-g` requiere salida ELF. También vincula la función de
arranque a la primera sentencia ejecutable del archivo principal, si existe.
No asigna direcciones a cada sentencia ni describe variables locales o tipos.

### 1. Variables, tipos y conversiones

```volt
let count: i64 = 42
let ratio = 3.14
let byte: u8 = 255
const LIMIT: i64 = 100
print(count, ratio, byte, LIMIT)
```

| Tipo | Bytes | Significado |
| --- | --- | --- |
| `i8`, `i16`, `i32`, `i64` | 1, 2, 4, 8 | Enteros con signo |
| `u8`, `u16`, `u32`, `u64` | 1, 2, 4, 8 | Enteros sin signo |
| `f32`, `f64` | 4, 8 | Coma flotante IEEE 754 |
| `bool` | 1 | `true` o `false` |
| `char` | 1 | Valor entre 0 y 255; se imprime como byte a diferencia de `u8` |
| `string`, `ptr<T>` | 8 cada uno | Cadena inmutable terminada en NUL o puntero sin comprobaciones a `T` |
| `fnptr<(A, B) -> R>` | 8 | Dirección de función tipada para callbacks de C |
| `[N]T` | `N × sizeof(T)` | Arreglo de tamaño fijo |
| `[]T` | 16 | Vista de solo lectura: puntero y número de elementos |
| `[]mut T` | 16 | Vista mutable con acceso léxico exclusivo |
| `struct` | Depende de los campos | Agregado con nombre y alineación natural |
| `enum` | 8 sin datos | Discriminante nominal `i64` y datos opcionales de la variante |
| `Option<T>`, `Result<T,E>` | Depende del contenido | Valores etiquetados integrados, almacenados directamente |

`int`, `uint` y `float` son alias de `i64`, `u64` y `f64`. Un `let` local
es mutable. Si falta la anotación, el tipo se infiere del inicializador. Sin
inicializador, debe indicarse el tipo y, si este lo permite, se inicializa a
cero. `const` es inmutable y puede declararse a nivel local o de módulo. Su
expresión escalar se evalúa al compilar: admite literales de tipos permitidos,
operaciones aritméticas, conversiones, variantes de enum, `sizeof`, `alignof`
y constantes previas, no llamadas a funciones ordinarias.
Los tipos de `const` pueden ser enteros, flotantes, `bool`, `char` o enum sin datos,
no cadenas, punteros ni agregados.

`as` convierte explícitamente. Las reglas numéricas también se aplican al
inicializar, asignar, pasar un argumento a un parámetro declarado y devolver
un valor. Un entero debe caber en el tipo destino; el estrechamiento no trunca
silenciosamente los bits. Convertir un flotante a entero trunca hacia cero y
provoca `panic` si el valor es NaN, infinito o queda fuera de rango. La
conversión de entero a flotante redondea directamente a la precisión de
destino, con empates al par; `f64` a `f32` puede producir infinito. Las
operaciones aritméticas y comparaciones no mezclan enteros y flotantes sin
`as`. Entre enteros, si el tipo sin signo tiene anchura igual o mayor, ese es
el tipo común; en caso contrario se usa el tipo más ancho con signo. Las
conversiones numéricas no resuelven desacuerdos en la inferencia genérica ni
cambian implícitamente los tipos del contenido de `Option` o `Result`.

### 2. Expresiones

| Prioridad, de menor a mayor | Operadores |
| --- | --- |
| 1–3 | `or`, luego `and`, luego `not` |
| 4 | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| 5–7 | Bit a bit: `\|`, luego `^`, luego `&` |
| 8 | `<<`, `>>` |
| 9 | `+`, `-` |
| 10 | `*`, `/`, `%` |
| 11 | Prefijos `-`, `*`, `&` |
| 12 | Llamadas por nombre, acceso a campo `.`, índice o vista `[]`, `as`, sufijo `?` |

- La aritmética entera comprueba desbordamiento y división por cero, también
  sin signo. La división entera trunca hacia cero: `-7 / 2 == -3` y
  `-7 % 2 == -1`. `%` no es un operador de coma flotante.
- El desplazamiento debe estar en `[0, anchura_en_bits)` del operando izquierdo.
  A la derecha, un entero con signo conserva el bit de signo y uno sin signo
  se rellena con ceros. A la izquierda se descartan los bits altos sin error
  por esa pérdida: `(64 as i8) << 1` da `-128`.
- La aritmética flotante sigue IEEE 754. Puede producir infinitos y NaN; la
  negación cambia el signo incluso para cero. En condiciones numéricas o
  booleanas, cero, `false` y NaN son falsos; los demás números y `true` son
  verdaderos. `and` y `or` tienen cortocircuito y devuelven `bool`.
- `sizeof(T)` y `alignof(T)` se calculan al compilar y devuelven bytes como
  `i64`. `len(x)` mide arreglos y vistas; `str_len(s)` mide bytes en una cadena.
  `==` y `!=` comparan el contenido de cadenas; `s + t` concatena y `s * n` repite.

### 3. Sentencias y limpieza

`if` / `elif` / `else`, `while` y `for` usan bloques con sangría. Cuando se
admite una sola sentencia, puede ir después de los dos puntos en la misma
línea (`if x < 0: return 1`). La asignación es una sentencia, no una expresión;
también existen `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=` y `>>=`.
Arreglos, estructuras, `Option` y `Result` no sirven como condiciones.

`for i in a..b` recorre `[a, b)`; `for i in a..=b` incluye `b`. Los límites
se evalúan una vez y se convierten a `i64` con comprobación de rango. No se
admiten límites `enum`; `i` es `i64`. Un intervalo invertido está vacío. Con
límites iguales, `..=` ejecuta una iteración. `break` termina el bucle más
interno y `continue` pasa a su siguiente iteración. El intervalo es sintaxis,
no un tipo de valor independiente.

`defer` registra una sentencia simple, como una llamada o asignación, al
alcanzarla. Las acciones se ejecutan en orden inverso al salir de ese bloque,
tanto por flujo normal como por `return`, `break`, `continue` o propagación
con `?`. Solo se limpian los ámbitos que se abandonan. Las variables locales
usadas en `defer` deben estar declaradas antes; se leen cuando se ejecuta la
acción. El resultado de `return` se guarda antes de la limpieza. La acción
no puede contener declaraciones, otro `defer` ni control de flujo, incluido
el operador posfijo `?`. `panic` y
`exit` terminan el proceso sin ejecutar los `defer` pendientes.

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

### 4. Funciones y ABI

Una función se declara `fn name(arg: T) -> R:` seguida de su cuerpo. Si no
devuelve un valor, se omite `-> R`. Las funciones con resultado deben devolverlo
en todos los caminos reconocidos por el compilador. Los parámetros tienen un
tipo explícito y se declaran en la misma línea. No hay argumentos nombrados ni
por defecto, sobrecarga ni funciones anidadas. Las llamadas son por nombre. `unsafe fn` permite
operaciones inseguras y solo se llama desde un contexto `unsafe`.

- El ABI dispone de seis registros de argumentos de clase entera (`rdi`,
  `rsi`, `rdx`, `rcx`, `r8`, `r9`) y ocho de coma flotante (`xmm0`–`xmm7`),
  asignados de forma independiente. Los argumentos que no caben en su clase
  de registro ocupan ranuras de 8 bytes en la pila, en orden de declaración.
  La pila se alinea a 16 bytes antes de la llamada. Una vista usa dos registros
  enteros o se pasa entera en pila. Las estructuras y los valores etiquetados
  se pasan a funciones VOLT por puntero implícito y se copian a almacenamiento
  local. El puntero oculto de resultado `sret` usa el primer registro entero.
  El resultado se conserva durante `defer`. No se pueden pasar o devolver
  arreglos por valor. Una vista de solo lectura puede devolverse con `-> []T from input`.
- **Genéricos:** una función como `fn identity<T>(value: T) -> T:` se
  especializa al compilar para cada combinación de tipos inferida. Los
  argumentos permiten deducir tipos de estructuras anidadas y de punteros.
  Dos deducciones contradictorias para el mismo tipo son un error. Las
  funciones externas y las de ensamblador no pueden ser genéricas. `T: Eq`
  se comprueba en el sitio de la llamada.
- **FFI de C:** `unsafe extern fn` declara un símbolo externo de firma fija.
  `link "-lc"` solicita una biblioteca ELF compartida. Se admiten tipos
  escalares y punteros compatibles. Un `enum` de VOLT sin datos usa `i64`, no la
  representación de un `enum` de C. Los agregados se pasan por dirección, en
  memoria del llamador, salvo `extern struct` de hasta 16 bytes con campos escalares
  y alineación natural, que se puede pasar por valor a un `extern fn` directo.
  No se admiten llamadas variádicas ni exportación automática a C.
- **Callbacks:** `fnptr<(A, B) -> R>` o `fnptr<(A, B)>` (sin resultado) describe
  una firma escalar de C. `callback(named_function)` permite pasar una función
  nombrada a C desde `unsafe`. Se comprueba la firma; los argumentos que no
  caben en registros pasan en pila, igual que en llamadas directas a C.
  En `unsafe` se puede invocar una variable local o un parámetro de este tipo
  con `f(args)`. Se comprueban el número y el tipo de argumentos. Un destino
  nulo termina antes de evaluarlos; los nombres directos tienen prioridad.
  Convertir una dirección sin procesar es inseguro y no valida la firma ni el
  tiempo de vida. Los callbacks no capturan un entorno léxico.
- **Código nativo:** `native fn` admite un subconjunto de ensamblador Intel
  x86-64 y siempre es insegura. El compilador genera prólogo y epílogo, por
  lo que el cuerpo no debe tener `ret`. El cuerpo debe respetar el ABI,
  incluida la conservación de los registros exigidos y de la pila. El primer
  argumento en pila está en `[rbp+16]` tras el prólogo.

```volt
native fn raw_add(a: i64, b: i64) -> i64:
{
    mov rax, rdi
    add rax, rsi
}

unsafe:
    print(raw_add(2, 3))
```

Este ejemplo pasa una función VOLT nombrada a `qsort` de C; requiere libc
del sistema.

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

### 5. Estructuras, enumeraciones y patrones

Una estructura declara campos con nombre. Su constructor recibe argumentos
posicionales en el orden de declaración. Cada campo se alinea según su tipo;
la alineación total es el máximo de los campos y el tamaño se redondea a un
múltiplo de esa alineación. Se permiten estructuras anidadas, arreglos de
estructuras y copias por valor. Cada especialización genérica tiene su propio
diseño. El constructor usa el tipo destino cuando existe; en caso contrario
lo infiere de los campos. Las referencias recursivas se hacen mediante punteros.

```volt
struct Item<T>:
    index: i64
    value: T

fn item_value<T>(item: Item<T>) -> T:
    return item.value

let item: Item<u32> = Item(0, 42)
print(item.index, item_value(item), sizeof(Item<u32>))
```

Un `enum` guarda un discriminante `i64`. Si no se da un valor inicial, empieza
en cero; cada valor implícito es el anterior más uno. Un valor explícito como
`Green = 4` modifica la secuencia. Se escribe `Name.Variant`; solo se comparan
valores del mismo enum con `==`/`!=` y se pueden convertir explícitamente a
`i64` si no contienen datos. Una variante como `Number(i64)` almacena un único
escalar y se construye con `Token.Number(42)`. Los discriminantes son únicos.

`match` es una sentencia. Evalúa el valor una vez y requiere al menos una rama.
Los patrones incluyen `_`, `Enum.Variant`, `Enum.Variant(name)`, `None`, `Some(name)`,
`Ok(name)` y `Err(name)`. El conjunto de patrones debe ser exhaustivo y no
solaparse; `_` cubre los restantes y se escribe al final. No hay guardas ni
desestructuración. Los nombres vinculados son válidos solo dentro de la rama.
Los datos copiables se copian; `Ok` transfiere el búfer del resultado que lo posee.
Para `Option` o `Result`, se usa un valor local, un parámetro
o el resultado de una función, no un constructor directo.

`Option<T>` contiene `None` o `Some(T)` y `Result<T,E>` contiene `Ok(T)` o
`Err(E)`. Si el constructor no determina todos los tipos, especifica una
anotación o usa un contexto que los determine. `let r: Result<i64, i32> =
Err(22 as i32)` contiene exactamente un `i32`. También se admiten estructuras
copiables, enum con datos y `Option`/`Result` anidados copiables, pero no vistas
ni arreglos por valor. [`Result<OwnedBuffer, E>`](docs/owned-buffer.md) solo se
puede mover y requiere un error copiable, al igual que `Option<OwnedBuffer>`:
`Ok`/`Some` reciben el búfer y `match` o `?` consume la envoltura. Los valores
etiquetados pueden ser variables locales,
parámetros o resultados de funciones VOLT, pero no variables globales, constantes,
campos, elementos de arreglo ni variables inicializadas automáticamente a cero.
Solo se pueden reasignar valores etiquetados copiables del mismo tipo; el lado
derecho se evalúa una sola vez.

`?` extrae el valor de éxito. Con `None` o `Err` retorna de la función VOLT
que lo contiene y ejecuta sus `defer` y `drop`. Para `Option` el retorno debe ser
exactamente el mismo `Option<T>`; para `Result` el tipo de error debe coincidir
pero el tipo de éxito puede cambiar. `?` puede usarse en expresiones anidadas
y no está disponible en código `extern` ni `native`.

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

Estos valores etiquetados no requieren memoria dinámica. Comienzan con una
etiqueta `i64`: 0 para `None`/`Ok`, 1 para `Some`/`Err`. Si `P` y `A` son el
tamaño y la alineación del contenido (los máximos entre `T` y `E` para
`Result`), el contenido empieza en `align_up(8, A)`, la alineación total es
`max(8, A)` y el tamaño es `align_up(align_up(8, A) + P, max(8, A))`.
`align_up` indica redondeo a un múltiplo, no una función VOLT. `None` tiene
su área de contenido a cero. Los parámetros se copian desde un puntero
implícito y los resultados se entregan mediante `sret` después de la limpieza.
Es una convención interna de VOLT, no un ABI de C.

### 6. Arreglos, vistas, punteros y memoria

- **Arreglos:** `[N]T` contiene `N` elementos; `N` es un literal entero, no un
  parámetro genérico. Los índices se comprueban con `0 <= i < N`. La lista
  inicial debe caber y los elementos restantes se rellenan con cero. Sin
  anotación, una lista no vacía determina la longitud y el primer elemento
  determina el tipo. Se
  pueden copiar arreglos del mismo tipo; para pasarlos a una función, usa una
  vista o un puntero. Los arreglos locales viven en la pila.
- **Vistas:** `data[start..end]` crea una vista `[]T` de solo lectura;
  `mut data[start..end]` crea una vista exclusiva `[]mut T` de un arreglo local.
  Durante un préstamo mutable no se permite acceder directamente al arreglo.
  El préstamo dura hasta el final del bloque, incluido `defer`. Una vista
  mutable admite una subvista de solo lectura: `buf[0..n]` (sin `mut`) crea
  una `[]T` hija; mientras viva, se rechaza escribir a través de la vista
  mutable o pasarla como `[]mut`, y la escritura se reanuda al salir del
  bloque de la hija. Se puede
  devolver una vista de solo lectura derivada del parámetro indicado por `from`.
  Las vistas no se guardan en agregados ni se pasan por el ABI de C.
- **Punteros:** `&place` obtiene una dirección. Desreferenciar, indexar,
  acceder a campos a través del puntero, hacer aritmética o convertir punteros
  requiere `unsafe`. `p + i`, `i + p` y `p - i` avanzan en unidades de
  `sizeof(T)`. Pueden compararse punteros del mismo tipo, no uno con un entero.
  No se comprueban direcciones, límites ni vidas útiles de punteros sin procesar.
- **Cadenas:** `string` es una secuencia inmutable de bytes terminada en NUL,
  no un búfer con longitud propia. La indexación comprueba el límite y devuelve
  un byte en lugar de un carácter Unicode. `str_len` y la indexación buscan
  el NUL. Los literales no pueden contenerlo. La concatenación y repetición
  usan una arena compartida de 1 MiB por proceso; agotarla produce `panic`.
  Ese límite no se aplica a todos los búferes. Una cadena para C requiere una
  conversión explícita dentro de `unsafe`. [`TextView`](docs/text-view.md)
  guarda la longitud y ofrece acceso O(1) y subrangos sin copia.
- **Búferes:** `ByteBuffer` contiene bytes, incluido NUL, con longitud y
  capacidad; `Buffer<T>` almacena elementos tipados. Parte de almacenamiento
  inicializado a cero, mantén un propietario y libera explícitamente con
  `defer` cuando proceda. No conserves punteros después del crecimiento o
  liberación. `buffer_at` comprueba el índice. `ByteVec` ofrece un descriptor
  comprobado y `ByteView` guarda un intervalo que sobrevive al crecimiento.
  Al liberar el búfer se invalidan todas sus copias y vistas. Hay hasta 64
  búferes activos; las lecturas devuelven `Result` y detectan descriptores
  inválidos.
- **Lecturas léxicas:** [`BorrowBuffer<T>`](docs/buffer-borrow-proposal.md)
  usa descriptores comprobados y vistas de solo lectura hasta el fin del
  bloque. Mientras haya lectores, ninguna copia del descriptor puede editar
  ni liberar el búfer. El propietario se libera explícitamente; los elementos
  se copian de forma superficial.
- **Propietario único:** [`OwnedBuffer`](docs/owned-buffer.md) y
  [`fs.OwnedFd`](docs/owned-fd.md) se mueven con `let`, al llamar o al
  retornar; los propietarios vivos se liberan después de `defer` exactamente
  una vez: el búfer libera su memoria y el descriptor se cierra sin un doble
  `close` de un número reutilizado. `owned_buffer_bytes(&buffer)` presta los
  bytes como un slice `[]u8` sin copiar; el búfer no puede moverse mientras el
  slice esté vivo.

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

### 7. Módulos e inicio del programa

`use NAME` o `use A, B` busca `NAME.volt` junto al archivo que importa y luego
en `vstd/`, `browser/modules/`, `gpu/modules/` y `tools/modules/`, en ese orden,
bajo la raíz de instalación del compilador. Cada módulo se carga una vez; las dependencias se
inicializan primero y los ciclos son errores. Sin `module NAME` se mantienen
las importaciones planas. Un archivo con `module NAME` exporta con `pub` y
se accede con nombres como `fs.open`, también tras `use NAME as ALIAS`.
Los constructores y campos de las estructuras públicas siguen siendo privados. `io` y
`str` se importan automáticamente. Un módulo admite `const`, `let` global
con inicializador constante y llamadas de inicialización de nivel superior.

En el archivo de entrada, las sentencias de nivel superior se ejecutan después
de inicializar los módulos, antes del `main` declarado en el propio archivo.
Un `let` de ese nivel es local a la función de entrada generada. `fn main() -> i64`
devuelve un estado y `fn main():` no devuelve valor; `main` no tiene parámetros.
`use process` ofrece `argc` y `arg_at`. Si no se devuelve estado se sale con 0.

`link "-lNAME"` solicita `libNAME.so`, `-l:FILE` indica un nombre exacto y
`-LPATH` añade una ruta de búsqueda en la compilación. El cargador dinámico
de Linux resuelve esas bibliotecas en ejecución. Esto no proporciona el
protocolo completo de inicio y terminación de libc.
El indicador explícito [`--manifest volt.mod`](docs/volt-mod.md) añade
bibliotecas de C y rutas de búsqueda de compilación. No descarga paquetes ni
ejecuta scripts.

### 8. Biblioteca estándar

| API | Contrato |
| --- | --- |
| Intrínsecas | `sin`, `cos`, `tan`, `log2`, `atan2`, `sqrt`, `abs`, `min`, `max`, `len`, `sizeof` y `alignof`. `panic` escribe el fallo en stderr y termina; `exit` termina con un estado. No ejecutan la limpieza de ámbitos. |
| Entorno Linux | `read`, `write`, `write_all`, `open`, `close`, `mmap`, `munmap` y `brk` son operaciones de bajo nivel; el llamador verifica punteros, tamaños y estados. |
| `io`, `str` | `print` separa valores con espacios y añade un salto de línea; `put_*`, `put_err`, `put_errnl` y `nl` dan control explícito. Los enteros usan decimal y los flotantes normalmente seis cifras fraccionarias, con notación científica para valores grandes. Un error de escritura provoca `panic`. Las cadenas ofrecen `str_len`, `str_eq`, `str_concat` y `str_repeat`. |
| [`math`](vstd/math.volt), [`math3d`](vstd/math3d.volt) | Constantes y operaciones numéricas, como `powi`, `ipowi` y `hypot`, vectores y matrices. Las potencias enteras y factoriales se comprueban; `ipowi` con exponente negativo trunca el recíproco hacia cero. |
| [`time`](vstd/time.volt) | `monotonic_ms() -> Result<i64, i32>` mide intervalos, no fechas. |
| [`fs`](vstd/fs.volt) | `file_size` devuelve el tamaño lógico, incluidos los huecos de archivos dispersos. `create_dir` crea un directorio, `rename_path` mueve una entrada sin reemplazar el destino y `remove_file`/`remove_dir` eliminan un archivo o enlace simbólico y un directorio vacío, respectivamente. Operaciones síncronas de Linux con `errno` positivo en `Err`. `fs.read_all(path, max_bytes)` lee un archivo completo en un `Result<OwnedBuffer, IoError>` no copiable: `Err(EINVAL)` si `max_bytes <= 0`, `Err(EFBIG)` por encima del límite y, en los demás casos, el `errno` positivo del núcleo; un archivo vacío y uno de exactamente `max_bytes` son válidos, y el búfer nunca se libera a mano. |
| [`process`](vstd/process.volt) | `argc`, `arg_at` y el entorno sin procesar leen la pila inicial de Linux. `arg_at` devuelve una cadena prestada o `Err(22)`; `process_exec_wait` ejecuta sin shell. |
| [`event`](vstd/event.volt) | `poll` recibe `[]mut EventPollFd` y escribe `revents` en esa vista sin que el llamador necesite `unsafe`. `poll_readable` devuelve flags de un descriptor. El tiempo límite son milisegundos de `i32` (`-1`: espera indefinida, `0`: consulta inmediata). `poll` devuelve 0 si vence el plazo. `timer_create`, `timer_set`, `timer_read` y `timer_close` operan con `timerfd` monotónico no bloqueante; `first_ms = 0` lo desactiva y sin expiraciones se devuelve `Err(11)`. |
| Flujos de [`event`](vstd/event.volt) | `stream_pair` abre dos extremos de un socket local no bloqueante; se cierran con `event_close`. `try_read(fd, buffer: []mut u8)` y `try_write(fd, buffer: []u8)` intentan una operación en un socket de flujo conectado sin `unsafe`, tomando la longitud del slice; un slice vacío devuelve `Err(EINVAL)`, así que `Ok(0)` siempre significa fin del flujo. Gestiona transferencias parciales y `EAGAIN` con `poll`. La escritura no emite `SIGPIPE`. Las formas con puntero y longitud se conservan como `unsafe try_read_raw`/`try_write_raw`. |
| [`arena`](docs/arena.md) | Asignación lineal de capacidad fija para objetos temporales. El llamador usa `unsafe` y no puede conservar los punteros tras reiniciar o liberar la arena. |
| [`thread`](docs/thread.md) | Pthreads opcionales en Linux x86-64 con glibc ≥ 2.34. Creación y espera de hilos con `unsafe`, mutex con intento de bloqueo y variables de condición con plazos monótonos. Conserva las direcciones y los datos vivos hasta un `join` exitoso. El compilador no analiza la seguridad entre hilos. |
| [`channel`](docs/channel.md) | Mensajes sincronizados por valor de tipo `i64`, con operaciones bloqueantes y variantes `try`, sin `unsafe` para el canal. Crear un pthread y sincronizar el resto del estado compartido siguen siendo responsabilidad del llamador. |
| [`bytes`](vstd/bytes.volt), [`buffer`](vstd/buffer.volt), [`bytevec`](vstd/bytevec.volt), [`utf8`](vstd/utf8.volt) | Almacenamiento con longitud, descriptores comprobados y utilidades UTF-8. `utf8_next` consume un byte inválido y devuelve U+FFFD. |
| [`json`](docs/json.md) | Lee un documento JSON UTF-8 de hasta 8 MiB con 64 contenedores anidados. Busca campos y elementos y conserva rangos numéricos exactos. `JsonValue` toma prestado el origen sin modificar. Decodifica y escapa cadenas en búferes del llamador, sin serializador general de objetos o arreglos. |
| [`http`, `dns`, `tls`](docs/http.md) | GET HTTP acotado por IPv4, resolución de nombres y HTTPS con OpenSSL 3 que comprueba el certificado y el nombre. No es una API general de sockets ni de ejecución asíncrona. |
| [`sdl`, `window`](docs/sdl.md), [`html`, `css`](docs/html-engine.md) | Enlaces opcionales a SDL2 y subconjuntos HTML y CSS para el navegador nativo. |
| [`browser_search`](docs/search.md), [`cuda`](docs/cuda.md) | Índice local sin conexión y enlace opcional al controlador CUDA. Carga `libcuda.so.1` al solicitarlo y ejecuta PTX suministrado; VOLT no genera código para GPU. |

### 9. Límites de la implementación

Solo se admite Linux x86-64 con el subconjunto de ABI descrito. Comprobar
índices y aritmética no hace seguros los punteros sin procesar ni el FFI.
`unsafe` asigna responsabilidades al llamador: no es una zona aislada. La
comprobación de préstamos de vistas es léxica y la destrucción automática se
limita a los tipos propietarios registrados, `OwnedBuffer` y `fs.OwnedFd`,
incluso dentro de un `Result` u `Option`. `Buffer<T>` y `fs.Descriptor` aún se liberan
manualmente. No se implementan
traits, genéricos con parámetros constantes, clausuras, tuplas, macros,
`async`/`await`, bloques arbitrarios de ensamblador en línea ni un recolector de
basura. Las promesas de JavaScript y CUDA son integraciones aparte, no sintaxis de VOLT.

Las [pruebas de salida](tests/run.py), [regresiones](tests/regressions.py) y
[comprobaciones de autocompilación](bootstrap/README.md) ejercitan el contrato.
