use browser_youtube_url
use browser_youtube_metadata
use browser_youtube_view

unsafe fn expect_video_id(url: string, expected: string):
    let id: [12]char
    id[11] = '!'
    if not youtube_video_id(url, &id[0]) or id[11] != '\0' or (&id[0]) as string != expected:
        panic("wrong YouTube video ID for " + url)

unsafe fn expect_no_video_id(url: string):
    let id: [12]char
    if youtube_video_id(url, &id[0]): panic("unexpected YouTube video ID for " + url)

unsafe fn expect_no_media(url: string):
    if youtube_media_url(url): panic("unexpected YouTube media URL: " + url)

unsafe fn check_urls():
    expect_video_id("https://www.youtube.com/watch?feature=share&v=AbC_123-xyz#time", "AbC_123-xyz")
    expect_video_id("https://youtu.be/ZXy_987-abc?si=mock", "ZXy_987-abc")
    expect_video_id("https://m.youtube.com/shorts/AbC_123-xyz", "AbC_123-xyz")
    expect_no_video_id("https://www.youtube.com/watch?other=v=AbC_123-xyz")
    expect_no_video_id("https://www.youtube.com/watch?vv=AbC_123-xyz")
    expect_no_video_id("https://www.youtube.com/watch?v=AbC_123-xyz&v=ZXy_987-abc")
    expect_no_video_id("https://www.youtube.com/watch?%76=ZXy_987-abc&v=AbC_123-xyz")
    expect_no_video_id("https://www.youtube.com/watch?v=AbC_123-xyz0")
    expect_no_video_id("https://www.youtube.com/watch?v=AbC_123.xyz")
    expect_no_video_id("https://www.youtube.com.example.test/watch?v=AbC_123-xyz")
    expect_no_video_id("https://youtu.be/ZXy_987-abc/more")

    if not youtube_media_url("https://r1.googlevideo.com/videoplayback?id=mock&token=a%2Bb"):
        panic("direct YouTube media URL rejected")
    expect_no_media("http://r1.googlevideo.com/videoplayback?id=mock")
    expect_no_media("https://googlevideo.com/videoplayback?id=mock")
    expect_no_media("https://r1.googlevideo.com.example.test/videoplayback?id=mock")
    expect_no_media("https://demo@r1.googlevideo.com/videoplayback?id=mock")
    expect_no_media("https://r1.googlevideo.com:443/videoplayback?id=mock")
    expect_no_media("https://r1.googlevideo.com/videoplayback-extra?id=mock")
    expect_no_media("https://r1.googlevideo.com/videoplayback?")
    expect_no_media("https://r1.googlevideo.com/videoplayback?id=mock#fragment")
    expect_no_media("https://r1.googlevideo.com/videoplayback?id=mock%2")

    let prefix: string = "https://r1.googlevideo.com/videoplayback?id="
    let bounded: string = prefix + "a" * (8192 - str_len(prefix))
    if not youtube_media_url(bounded): panic("8 KiB YouTube media URL rejected")
    if youtube_media_url(bounded + "a"): panic("overlong YouTube media URL accepted")

    let loopback: [4]u8 = [127, 0, 0, 1]
    let shared: [4]u8 = [100, 64, 0, 1]
    let link_local: [4]u8 = [169, 254, 25, 1]
    let public_ip: [4]u8 = [142, 251, 155, 4]
    if browser_youtube_public_ipv4(&loopback[0]): panic("YouTube destination allowed loopback")
    if browser_youtube_public_ipv4(&shared[0]): panic("YouTube destination allowed shared address space")
    if browser_youtube_public_ipv4(&link_local[0]): panic("YouTube destination allowed link-local")
    if not browser_youtube_public_ipv4(&public_ip[0]): panic("YouTube destination rejected public address")

fn player_response(status: string, id: string, list: string, format: string) -> string:
    let playability: string = "\"playabilityStatus\":{\"status\":\"" + status + "\"}"
    let details: string = "\"videoDetails\":{\"videoId\":\"" + id + "\",\"title\":\"Demo {\\\"clip\\\"}\"}"
    let streams: string = "\"streamingData\":{\"" + list + "\":[" + format + "]}"
    return "ytInitialPlayerResponse = {" + playability + "," + details + "," + streams + "};"

fn mp4_format(url_field: string, content_length: string) -> string:
    let mime: string = "\"mimeType\":\"video/mp4; codecs=\\\"avc1.42001E, mp4a.40.2\\\"\""
    return "{\"itag\":18," + mime + ",\"contentLength\":\"" + content_length + "\"," + url_field + "}"

fn player_script(response: string) -> string:
    return "<script>var " + response + "</script>"

unsafe fn expect_unavailable(markup: string, expected: string, reason: string):
    let metadata: YoutubeMetadata
    if youtube_metadata(markup as ptr<char>, str_len(markup), expected, &metadata) > 0:
        panic("accepted YouTube metadata: " + reason)

unsafe fn check_metadata():
    let id: string = "AbC_123-xyz"
    let url_field: string = "\"url\":\"https:\\/\\/r1.googlevideo.com\\/videoplayback?id=mock\\u0026token=a%2Bb\""
    let direct: string = mp4_format(url_field, "10000")
    let response: string = player_response("OK", id, "formats", direct)
    let markup: string = player_script(response)
    let title: string = "Demo {\"clip\"}"
    let media: string = "https://r1.googlevideo.com/videoplayback?id=mock&token=a%2Bb"
    let metadata: YoutubeMetadata
    metadata.title[str_len(title)] = '!'
    metadata.media[str_len(media)] = '!'
    if youtube_metadata(markup as ptr<char>, str_len(markup), id, &metadata) != 1:
        panic("valid YouTube metadata rejected")
    if metadata.title[str_len(title)] != '\0' or (&metadata.title[0]) as string != title:
        panic("YouTube title did not round-trip")
    if metadata.media[str_len(media)] != '\0' or (&metadata.media[0]) as string != media:
        panic("JSON escapes changed the YouTube media URL")

    let unknown: string = "{\"itag\":18,\"mimeType\":\"video/mp4\",\"bitrate\":1,\"url\":\"https://r1.googlevideo.com/videoplayback?id=unknown-size\"}"
    let ranked: string = player_script(player_response("OK", id, "formats", unknown + "," + direct))
    if youtube_metadata(ranked as ptr<char>, str_len(ranked), id, &metadata) != 1 or (&metadata.media[0]) as string != media:
        panic("YouTube format with known in-budget size was not preferred")

    expect_unavailable(player_script(player_response("LOGIN_REQUIRED", id, "formats", direct)), id, "login required")
    expect_unavailable(markup, "AbC_123-xyZ", "different video ID")
    expect_unavailable("<div>" + response + "</div>", id, "assignment outside script")
    let truncated: i64 = str_len(markup) - str_len("]}};</script>")
    if youtube_metadata(markup as ptr<char>, truncated, id, &metadata) > 0:
        panic("accepted YouTube metadata beyond the input length")

    let cipher: string = mp4_format("\"signatureCipher\":\"s=mock&url=https%3A%2F%2Fr1.googlevideo.com%2Fvideoplayback%3Fid%3Dmock\"", "10000")
    expect_unavailable(player_script(player_response("OK", id, "formats", cipher)), id, "signature cipher only")
    let adaptive: string = player_script(player_response("OK", id, "adaptiveFormats", direct))
    if youtube_metadata(adaptive as ptr<char>, str_len(adaptive), id, &metadata) != 0 or metadata.media[0] != '\0' or (&metadata.title[0]) as string != title:
        panic("adaptive-only YouTube response must retain its title without a source")
    expect_unavailable(player_script(player_response("OK", id, "formats", mp4_format(url_field + ",\"drmFamilies\":[\"mock\"]", "10000"))), id, "protected format")
    expect_unavailable(player_script(player_response("OK", id, "formats", mp4_format(url_field + ",\"u\\u0072l\":\"duplicate\"", "10000"))), id, "duplicate URL")

    # One byte over the browser's 32 MiB media budget.
    let oversize: string = mp4_format(url_field, "33554433")
    expect_unavailable(player_script(player_response("OK", id, "formats", oversize)), id, "media over byte budget")
    let unrelated: string = mp4_format("\"url\":\"https://video.example.test/videoplayback?id=mock\"", "10000")
    expect_unavailable(player_script(player_response("OK", id, "formats", unrelated)), id, "non-Google media host")
    let lookalike: string = mp4_format("\"url\":\"https://r1.googlevideo.com.example.test/videoplayback?id=mock\"", "10000")
    expect_unavailable(player_script(player_response("OK", id, "formats", lookalike)), id, "lookalike media host")

fn main() -> i64:
    unsafe:
        check_urls()
        check_metadata()
    print("browser YouTube ok")
    return 0
