use css
use http_frame

struct BrowserPolicy:
    present: bool
    block_styles: bool
    block_images: bool
    block_style_elements: bool
    block_style_attributes: bool
    block_media: bool

unsafe fn browser_policy_self(p: ptr<char>, start: i64, end: i64) -> bool:
    let at: i64 = css_trim_start(p, start, end)
    while at < end:
        let stop: i64 = at
        while stop < end and not css_space(p[stop]): stop += 1
        if http_frame_equal(p, at, stop, "'self'") or http_frame_equal(p, at, stop, "*"): return true
        at = css_trim_start(p, stop, end)
    return false

unsafe fn browser_policy_inline(p: ptr<char>, start: i64, end: i64) -> bool:
    let at: i64 = css_trim_start(p, start, end)
    let allow: bool = false
    while at < end:
        let stop: i64 = at
        while stop < end and not css_space(p[stop]): stop += 1
        if http_frame_equal(p, at, stop, "'unsafe-inline'"): allow = true
        if stop - at >= 5 and http_frame_equal(p, at, at + 5, "'sha2"): return false
        if stop - at >= 5 and http_frame_equal(p, at, at + 5, "'sha3"): return false
        if stop - at >= 5 and http_frame_equal(p, at, at + 5, "'sha5"): return false
        if stop - at >= 7 and http_frame_equal(p, at, at + 7, "'nonce-"): return false
        at = css_trim_start(p, stop, end)
    return allow

# shortcut: support same-origin sources and unconditional inline styles until full CSP is implemented.
unsafe fn browser_policy_read(policy: ptr<BrowserPolicy>, p: ptr<char>, start: i64, end: i64):
    policy.present = true
    let at: i64 = start
    while at < end:
        let fallback: i64 = 0
        let style: i64 = 0
        let sheet: i64 = 0
        let image: i64 = 0
        let media: i64 = 0
        let fallback_inline: i64 = 0
        let style_inline: i64 = 0
        let sheet_inline: i64 = 0
        let attr_inline: i64 = 0
        while at < end and p[at] != ',':
            let stop: i64 = at
            while stop < end and p[stop] != ';' and p[stop] != ',': stop += 1
            let key: i64 = css_trim_start(p, at, stop)
            let value: i64 = key
            while value < stop and not css_space(p[value]): value += 1
            let allow: i64 = -1
            if browser_policy_self(p, value, stop): allow = 1
            let inline: i64 = -1
            if browser_policy_inline(p, value, stop): inline = 1
            if fallback == 0 and http_frame_equal(p, key, value, "default-src"):
                fallback = allow
                fallback_inline = inline
            elif style == 0 and http_frame_equal(p, key, value, "style-src"):
                style = allow
                style_inline = inline
            elif sheet == 0 and http_frame_equal(p, key, value, "style-src-elem"):
                sheet = allow
                sheet_inline = inline
            elif attr_inline == 0 and http_frame_equal(p, key, value, "style-src-attr"): attr_inline = inline
            elif image == 0 and http_frame_equal(p, key, value, "img-src"): image = allow
            elif media == 0 and http_frame_equal(p, key, value, "media-src"): media = allow
            at = stop
            if at < end and p[at] == ';': at += 1
        if sheet == 0: sheet = style
        if sheet == 0: sheet = fallback
        if image == 0: image = fallback
        if media == 0: media = fallback
        if sheet < 0: policy.block_styles = true
        if image < 0: policy.block_images = true
        if media < 0: policy.block_media = true
        if style_inline == 0: style_inline = fallback_inline
        if sheet_inline == 0: sheet_inline = style_inline
        if attr_inline == 0: attr_inline = style_inline
        if sheet_inline < 0: policy.block_style_elements = true
        if attr_inline < 0: policy.block_style_attributes = true
        if at < end: at += 1

unsafe fn browser_policy_meta(policy: ptr<BrowserPolicy>, source: string, nodes: ptr<HtmlNode>, attributes: ptr<HtmlAttribute>, count: i64):
    let p: ptr<char> = source as ptr<char>
    let total: i64 = __volt_strlen(source)
    let i: i64 = 1
    while i < count:
        let node: ptr<HtmlNode> = &nodes[i]
        if node.kind == HTML_ELEMENT and node.attribute_count > 0 and html_name_equal(source, node, "meta"):
            let equity: i64 = css_find_html_attribute(source, node, attributes, "http-equiv")
            if equity >= 0 and attributes[equity].has_value:
                let name: [65]char
                let attr: ptr<HtmlAttribute> = &attributes[equity]
                let size: i64 = html_decode_range(p, total, attr.value_start, attr.value_length, &name[0], 65)
                let begin: i64 = css_trim_start(&name[0], 0, max(0, size))
                let end: i64 = css_trim_end(&name[0], begin, max(0, size))
                if size == -7 or (size > 0 and http_frame_equal(&name[0], begin, end, "content-security-policy")):
                    policy.present = true
                    if size == -7: policy.block_media = true
                    let content: i64 = css_find_html_attribute(source, node, attributes, "content")
                    if content >= 0 and attributes[content].has_value:
                        attr = &attributes[content]
                        let text: [8193]char
                        let length: i64 = html_decode_range(p, total, attr.value_start, attr.value_length, &text[0], 8193)
                        if length >= 0: browser_policy_read(policy, &text[0], 0, length)
                        else:
                            policy.block_styles = true
                            policy.block_images = true
                            policy.block_style_elements = true
                            policy.block_style_attributes = true
                            policy.block_media = true
        i += 1
