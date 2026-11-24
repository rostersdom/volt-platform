use browser_graphics
use bytes

link "-lturbojpeg -lwebp"

const BROWSER_IMAGE_LIMIT: i64 = 16
const BROWSER_IMAGE_PIXELS: i64 = 4194304
const BROWSER_IMAGE_BYTES: i64 = 1048576

unsafe extern fn cairo_image_surface_create_from_png_stream(reader: fnptr<(ptr<char>, ptr<u8>, u32) -> i32>, closure: ptr<char>) -> ptr<char>
unsafe extern fn WebPGetInfo(data: ptr<u8>, size: i64, width: ptr<i32>, height: ptr<i32>) -> i32
unsafe extern fn WebPDecodeBGRAInto(data: ptr<u8>, size: i64, output: ptr<u8>, capacity: i64, stride: i32) -> ptr<u8>
unsafe extern fn tj3Init(mode: i32) -> ptr<char>
unsafe extern fn tj3Destroy(handle: ptr<char>)
unsafe extern fn tj3Set(handle: ptr<char>, property: i32, value: i32) -> i32
unsafe extern fn tj3DecompressHeader(handle: ptr<char>, data: ptr<u8>, size: i64) -> i32
unsafe extern fn tj3Get(handle: ptr<char>, property: i32) -> i32
unsafe extern fn tj3Decompress8(handle: ptr<char>, data: ptr<u8>, size: i64, pixels: ptr<u8>, stride: i32, format: i32) -> i32

struct BrowserImage:
    surface: ptr<char>
    width: i64
    height: i64
    url: [8193]char

struct BrowserImages:
    count: i64
    pixels: i64
    items: [16]BrowserImage
    by_node: Buffer<u8>

struct BrowserImageReader:
    data: ptr<u8>
    remaining: i64

unsafe fn browser_images_free(images: ptr<BrowserImages>):
    while images.count > 0:
        images.count -= 1
        cairo_surface_destroy(images.items[images.count].surface)
    images.pixels = 0
    buffer_free(&images.by_node)

unsafe fn browser_images_reset(images: ptr<BrowserImages>, nodes: i64) -> i64:
    while images.count > 0:
        images.count -= 1
        cairo_surface_destroy(images.items[images.count].surface)
    images.pixels = 0
    if buffer_reserve(&images.by_node, nodes) < 0: return -12
    let map: ptr<u8> = buffer_data(&images.by_node)
    let i: i64 = 0
    while i < nodes:
        map[i] = 0
        i += 1
    images.by_node.storage.len = nodes
    return 0

unsafe fn browser_image_at(images: ptr<BrowserImages>, node: i64) -> ptr<BrowserImage>:
    if node < 0 or node >= buffer_len(&images.by_node): return 0 as ptr<BrowserImage>
    let map: ptr<u8> = buffer_data(&images.by_node)
    let slot: i64 = map[node] as i64
    if slot < 1 or slot > images.count: return 0 as ptr<BrowserImage>
    return &images.items[slot - 1]

unsafe fn browser_image_reuse(images: ptr<BrowserImages>, node: i64, url: string) -> bool:
    let map: ptr<u8> = buffer_data(&images.by_node)
    let i: i64 = 0
    while i < images.count:
        let image: ptr<BrowserImage> = &images.items[i]
        if (&image.url[0]) as string == url:
            map[node] = (i + 1) as u8
            return true
        i += 1
    return false

unsafe fn browser_png_read(closure: ptr<char>, out: ptr<u8>, size: u32) -> i32:
    let reader: ptr<BrowserImageReader> = closure as ptr<BrowserImageReader>
    let length: i64 = size as i64
    if length > reader.remaining: return 10 as i32  # CAIRO_STATUS_READ_ERROR
    let i: i64 = 0
    while i < length:
        out[i] = reader.data[i]
        i += 1
    reader.data = reader.data + length
    reader.remaining -= length
    return 0 as i32

unsafe fn browser_image_u32(p: ptr<u8>) -> i64:
    return ((p[0] as i64) << 24) | ((p[1] as i64) << 16) | ((p[2] as i64) << 8) | (p[3] as i64)

unsafe fn browser_image_premultiply(data: ptr<u8>, stride: i64, width: i64, height: i64):
    let y: i64 = 0
    while y < height:
        let x: i64 = 0
        while x < width:
            let pixel: ptr<u8> = data + y * stride + x * 4
            let alpha: i64 = pixel[3] as i64
            let channel: i64 = 0
            while channel < 3:
                pixel[channel] = (((pixel[channel] as i64) * alpha + 127) / 255) as u8
                channel += 1
            x += 1
        y += 1

# Decode after reading dimensions, never allocating an unbounded pixel buffer.
unsafe fn browser_image_add(images: ptr<BrowserImages>, node: i64, body: ptr<ByteBuffer>, mime: string, url: string) -> bool:
    if images.count >= BROWSER_IMAGE_LIMIT or body.len < 12 or body.len > BROWSER_IMAGE_BYTES: return false
    let length: i64 = __volt_strlen(url)
    if length > 8192: return false
    let p: ptr<u8> = body.data
    let png: bool = browser_image_u32(p) == 0x89504e47 and browser_image_u32(p + 4) == 0x0d0a1a0a
    let jpg: bool = p[0] == 255 and p[1] == 216
    let webp: bool = browser_image_u32(p) == 0x52494646 and browser_image_u32(p + 8) == 0x57454250
    let jpeg: ptr<char> = 0 as ptr<char>
    defer browser_jpeg_free(jpeg)
    let width: i32 = 0
    let height: i32 = 0
    if png and (mime == "" or mime == "image/png"):
        if body.len < 24 or browser_image_u32(p + 8) != 13 or browser_image_u32(p + 12) != 0x49484452: return false
        let w: i64 = browser_image_u32(p + 16)
        let h: i64 = browser_image_u32(p + 20)
        if w > 4096 or h > 4096: return false
        width = w as i32
        height = h as i32
    elif jpg and (mime == "" or mime == "image/jpeg"):
        jpeg = tj3Init(1 as i32)  # TJINIT_DECOMPRESS
        if jpeg == (0 as ptr<char>): return false
        if tj3Set(jpeg, 13 as i32, 64 as i32) != 0 or tj3Set(jpeg, 23 as i32, 32 as i32) != 0 or tj3Set(jpeg, 24 as i32, BROWSER_IMAGE_PIXELS as i32) != 0: return false
        if tj3DecompressHeader(jpeg, p, body.len) != 0: return false
        width = tj3Get(jpeg, 5 as i32)  # TJPARAM_JPEGWIDTH
        height = tj3Get(jpeg, 6 as i32)  # TJPARAM_JPEGHEIGHT
    elif webp and (mime == "" or mime == "image/webp"):
        if WebPGetInfo(p, body.len, &width, &height) == 0: return false
    else: return false
    if width < 1 or height < 1 or width > 4096 or height > 4096: return false
    let pixels: i64 = (width as i64) * (height as i64)
    if pixels > BROWSER_IMAGE_PIXELS - images.pixels: return false
    let surface: ptr<char> = 0 as ptr<char>
    if png:
        let reader: BrowserImageReader = BrowserImageReader(p, body.len)
        surface = cairo_image_surface_create_from_png_stream(callback(browser_png_read), (&reader) as ptr<char>)
    else:
        surface = cairo_image_surface_create(CAIRO_ARGB32, width, height)
    if cairo_surface_status(surface) != 0:
        cairo_surface_destroy(surface)
        return false
    if not png:
        let output: ptr<u8> = cairo_image_surface_get_data(surface) as ptr<u8>
        let stride: i32 = cairo_image_surface_get_stride(surface)
        let success: bool = false
        if jpg: success = tj3Decompress8(jpeg, p, body.len, output, stride, 8 as i32) == 0  # TJPF_BGRA
        else:
            success = WebPDecodeBGRAInto(p, body.len, output, (stride as i64) * (height as i64), stride) != (0 as ptr<u8>)
            if success: browser_image_premultiply(output, stride as i64, width as i64, height as i64)
        if not success:
            cairo_surface_destroy(surface)
            return false
        cairo_surface_mark_dirty(surface)
    let item: ptr<BrowserImage> = &images.items[images.count]
    item.surface = surface
    item.width = width as i64
    item.height = height as i64
    let i: i64 = 0
    let name: ptr<char> = url as ptr<char>
    while i <= length:
        item.url[i] = name[i]
        i += 1
    images.count += 1
    let map: ptr<u8> = buffer_data(&images.by_node)
    map[node] = images.count as u8
    images.pixels += pixels
    return true

unsafe fn browser_jpeg_free(jpeg: ptr<char>):
    if jpeg != (0 as ptr<char>): tj3Destroy(jpeg)
