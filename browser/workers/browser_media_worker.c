/* Decode an already-open media file or bounded fMP4 appends. VOLT owns the network and UI. */
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <seccomp.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/intreadwrite.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>

enum { MEDIA_INPUT_LIMIT = 32 * 1024 * 1024, MAX_W = 960, MAX_H = 540, AUDIO_RATE = 48000, MAX_AUDIO = 8192 };
enum { PACKET_VIDEO = 1, PACKET_AUDIO, PACKET_END, PACKET_DURATION, PACKET_NEED_INPUT, PACKET_STREAM_MUXED };
enum { APPEND_LIMIT = 1024 * 1024 };

struct input { int64_t size, pos; };
struct stream_input {
    uint8_t *bytes;
    size_t size, pos, total;
    uint32_t tracks[2];
    int track_count, finished;
};
struct decoder {
    AVCodecContext *codec;
    AVStream *stream;
    int index;
    int64_t next_ms;
};
struct output {
    AVFrame *frame;
    struct SwsContext *scale;
    SwrContext *resample;
    AVChannelLayout audio_layout;
    int audio_format, audio_rate;
    int64_t origin;
    int video_seen, audio_seen, streaming, muxed, origin_set;
    unsigned char video[MAX_W * MAX_H * 4];
    unsigned char audio[MAX_AUDIO * 4];
};

static int isolate(int streaming) {
    const struct rlimit memory = {1536u * 1024 * 1024, 1536u * 1024 * 1024};
    const struct rlimit cpu = {45, 45}, core = {0, 0};
    if (setrlimit(RLIMIT_AS, &memory) || setrlimit(RLIMIT_CPU, &cpu) || setrlimit(RLIMIT_CORE, &core) ||
        prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || prctl(PR_SET_DUMPABLE, 0, 0, 0, 0)) return -1;
    scmp_filter_ctx filter = seccomp_init(SCMP_ACT_KILL_PROCESS);
    if (!filter) return -1;
    const int syscalls[] = {SCMP_SYS(brk), SCMP_SYS(munmap), SCMP_SYS(mremap), SCMP_SYS(madvise),
                            SCMP_SYS(clock_gettime), SCMP_SYS(gettimeofday), SCMP_SYS(futex),
                            SCMP_SYS(sched_getaffinity), SCMP_SYS(getrandom), SCMP_SYS(exit),
                            SCMP_SYS(exit_group), SCMP_SYS(rt_sigreturn)};
    int result = 0;
    for (size_t i = 0; i < sizeof(syscalls) / sizeof(*syscalls) && !result; i++) {
        result = seccomp_rule_add(filter, SCMP_ACT_ALLOW, syscalls[i], 0);
    }
    if (!result) result = seccomp_rule_add(filter, SCMP_ACT_ALLOW, SCMP_SYS(mmap), 2,
                                           SCMP_A2(SCMP_CMP_MASKED_EQ, PROT_EXEC, 0),
                                           SCMP_A3(SCMP_CMP_MASKED_EQ, MAP_ANONYMOUS, MAP_ANONYMOUS));
    if (!result) result = seccomp_rule_add(filter, SCMP_ACT_ALLOW, SCMP_SYS(mprotect), 1, SCMP_A2(SCMP_CMP_MASKED_EQ, PROT_EXEC, 0));
    if (!result && streaming) result = seccomp_rule_add(filter, SCMP_ACT_ALLOW, SCMP_SYS(read), 1, SCMP_A0(SCMP_CMP_EQ, 0));
    if (!result && !streaming) result = seccomp_rule_add(filter, SCMP_ACT_ALLOW, SCMP_SYS(pread64), 1, SCMP_A0(SCMP_CMP_EQ, 1));
    if (!result) result = seccomp_rule_add(filter, SCMP_ACT_ALLOW, SCMP_SYS(write), 1, SCMP_A0(SCMP_CMP_EQ, 0));
    if (!result) result = seccomp_load(filter);
    seccomp_release(filter);
    return result;
}

static void write_all(const void *buffer, size_t n) {
    const unsigned char *p = buffer;
    while (n) {
        ssize_t count = write(0, p, n);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) _exit(1);
        p += count;
        n -= (size_t)count;
    }
}

static void send_packet(int kind, int64_t size, int w, int h, int64_t ms, const void *data) {
    const int64_t header[5] = {kind, size, w, h, ms};
    write_all(header, sizeof(header));
    if (size) write_all(data, (size_t)size);
}

static int read_exact(void *data, size_t size) {
    uint8_t *p = data;
    while (size) {
        ssize_t n = read(0, p, size);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        p += n;
        size -= (size_t)n;
    }
    return 0;
}

static size_t box_size(const uint8_t *p, size_t n, const char *type) {
    if (n < 8 || (type && memcmp(p + 4, type, 4))) return 0;
    uint32_t size = AV_RB32(p);
    return size >= 8 && size <= n ? size : 0;
}

static const uint8_t *unique_child(const uint8_t *parent, size_t n, const char *type, size_t *length) {
    const uint8_t *found = NULL;
    for (size_t at = 8; at < n;) {
        const uint8_t *box = parent + at;
        size_t size = box_size(box, n - at, NULL);
        if (!size) return NULL;
        if (!memcmp(box + 4, type, 4)) {
            if (found) return NULL;
            found = box;
            *length = size;
        }
        at += size;
    }
    return found;
}

static int track_index(const struct stream_input *in, uint32_t id) {
    for (int i = 0; i < in->track_count; i++) {
        if (in->tracks[i] == id) return i;
    }
    return -1;
}

static int read_tracks(const uint8_t *moov, size_t size, struct stream_input *in) {
    size_t n;
    if (!unique_child(moov, size, "mvex", &n)) return 0;
    for (size_t at = 8; at < size;) {
        const uint8_t *box = moov + at;
        size_t length = box_size(box, size - at, NULL);
        if (!length) return 0;
        if (!memcmp(box + 4, "trak", 4)) {
            if (in->track_count == 2) return 0;
            const uint8_t *tkhd = unique_child(box, length, "tkhd", &n);
            if (!tkhd || n < 24 || tkhd[8] > 1) return 0;
            size_t offset = tkhd[8] ? 28 : 20;
            if (n < offset + 4) return 0;
            uint32_t id = AV_RB32(tkhd + offset);
            if (!id || track_index(in, id) >= 0) return 0;
            in->tracks[in->track_count++] = id;
        }
        at += length;
    }
    return in->track_count;
}

static uint32_t fragment_track(const uint8_t *traf, size_t n) {
    size_t length;
    const uint8_t *tfhd = unique_child(traf, n, "tfhd", &length);
    if (!tfhd || length < 16 || tfhd[8] != 0) return 0;
    int samples = 0;
    for (size_t at = 8; at < n;) {
        const uint8_t *box = traf + at;
        size_t run = box_size(box, n - at, NULL);
        if (!run) return 0;
        if (!memcmp(box + 4, "trun", 4)) {
            if (run < 16 || box[8] > 1) return 0;
            if (AV_RB32(box + 12)) samples = 1;
        }
        at += run;
    }
    return samples ? AV_RB32(tfhd + 12) : 0;
}

static int valid_fragment(const uint8_t *moof, size_t size, const struct stream_input *in) {
    unsigned int seen = 0;
    for (size_t at = 8; at < size;) {
        const uint8_t *box = moof + at;
        size_t length = box_size(box, size - at, NULL);
        if (!length) return 0;
        if (!memcmp(box + 4, "traf", 4)) {
            int index = track_index(in, fragment_track(box, length));
            if (index < 0 || (seen & (1u << index))) return 0;
            seen |= 1u << index;
        }
        at += length;
    }
    return seen != 0;
}

/* shortcut: accept whole 32-bit box pairs until arbitrary MSE appends are supported. */
static int read_append(void *opaque, uint8_t *data, int n) {
    struct stream_input *in = opaque;
    if (in->finished) return AVERROR_EOF;
    if (in->pos == in->size) {
        int64_t size;
        send_packet(PACKET_NEED_INPUT, 0, 0, 0, 0, NULL);
        if (read_exact(&size, sizeof(size)) || size < 0 || size > APPEND_LIMIT ||
            (uint64_t)size > MEDIA_INPUT_LIMIT - in->total) _exit(1);
        if (!size) {
            if (!in->total) _exit(1);
            in->finished = 1;
            return AVERROR_EOF;
        }
        if (read_exact(in->bytes, (size_t)size)) _exit(1);
        size_t first = box_size(in->bytes, (size_t)size, in->total ? "moof" : "ftyp");
        if (!first || (size_t)size - first < 8 ||
            box_size(in->bytes + first, (size_t)size - first, in->total ? "mdat" : "moov") != (size_t)size - first) _exit(1);
        if (!in->total) {
            if (!read_tracks(in->bytes + first, (size_t)size - first, in)) _exit(1);
        } else if ((size_t)size - first == 8 || !valid_fragment(in->bytes, first, in)) _exit(1);
        in->size = (size_t)size;
        in->pos = 0;
        in->total += (size_t)size;
    }
    size_t count = in->size - in->pos;
    if (count > (size_t)n) count = (size_t)n;
    memcpy(data, in->bytes + in->pos, count);
    in->pos += count;
    return (int)count;
}

static int read_media(void *opaque, uint8_t *data, int n) {
    struct input *in = opaque;
    if (n > in->size - in->pos) n = (int)(in->size - in->pos);
    if (n <= 0) return AVERROR_EOF;
    ssize_t count;
    do count = pread(1, data, (size_t)n, (off_t)in->pos); while (count < 0 && errno == EINTR);
    if (count <= 0) return count == 0 ? AVERROR_EOF : AVERROR(errno);
    in->pos += count;
    return (int)count;
}

static int64_t seek_media(void *opaque, int64_t off, int mode) {
    struct input *in = opaque;
    if (mode == AVSEEK_SIZE) return in->size;
    mode &= ~AVSEEK_FORCE;
    int64_t base = 0;
    if (mode == SEEK_CUR) base = in->pos;
    else if (mode == SEEK_END) base = in->size;
    else if (mode != SEEK_SET) return AVERROR(EINVAL);
    if (off < -base || off > in->size - base) return AVERROR(EINVAL);
    return in->pos = base + off;
}

static int deny_open(AVFormatContext *s, AVIOContext **pb, const char *url, int flags, AVDictionary **opts) {
    (void)s; (void)pb; (void)url; (void)flags; (void)opts;
    return AVERROR(EACCES);
}

static void select_stream(AVFormatContext *media, enum AVMediaType kind, struct decoder *out) {
    out->index = av_find_best_stream(media, kind, -1, -1, NULL, 0);
    if (out->index >= 0) out->stream = media->streams[out->index];
}

static int open_decoder(struct decoder *out) {
    if (!out->stream) return -1;
    AVCodecParameters *p = out->stream->codecpar;
    switch (p->codec_id) {
    case AV_CODEC_ID_H264: case AV_CODEC_ID_VP8: case AV_CODEC_ID_VP9: case AV_CODEC_ID_AV1:
    case AV_CODEC_ID_THEORA: case AV_CODEC_ID_AAC: case AV_CODEC_ID_OPUS: case AV_CODEC_ID_VORBIS:
        break;
    default: return -1;
    }
    const AVCodec *codec = avcodec_find_decoder(p->codec_id);
    if (!codec) return -1;
    out->codec = avcodec_alloc_context3(codec);
    if (!out->codec || avcodec_parameters_to_context(out->codec, p) < 0) return -1;
    out->codec->thread_count = 1;
    out->codec->max_pixels = 4194304;
    return avcodec_open2(out->codec, codec, NULL);
}

static int64_t frame_time(struct decoder *d, struct output *o, int duration) {
    int64_t pts = o->frame->best_effort_timestamp;
    int64_t time = d->next_ms;
    if (pts != AV_NOPTS_VALUE) {
        pts = av_rescale_q(pts, d->stream->time_base, (AVRational){1, 1000});
        /* Keep muxed tracks on the same timeline; VOLT chooses its origin. */
        if (o->muxed && pts != AV_NOPTS_VALUE) time = pts;
        else if (o->streaming && pts != AV_NOPTS_VALUE) {
            if (!o->origin_set) {
                o->origin = av_sat_sub64(pts, d->next_ms);
                o->origin_set = 1;
            }
            time = av_sat_sub64(pts, o->origin);
        } else if (pts >= -86400000 && pts <= 86400000) time = pts - o->origin;
    }
    if (time < 0 && !o->muxed) time = 0;
    if (time < -86400000 || time > 86400000) _exit(1);
    d->next_ms = time + duration;
    return time;
}

static int video_frame(struct decoder *d, struct output *o) {
    AVFrame *f = o->frame;
    int w = f->width, h = f->height;
    if (w < 1 || h < 1 || w > 4096 || h > 4096 || (int64_t)w * h > 4194304) return -1;
    if (w > MAX_W) { h = (h * MAX_W + w / 2) / w; w = MAX_W; }
    if (h > MAX_H) { w = (w * MAX_H + h / 2) / h; h = MAX_H; }
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    o->scale = sws_getCachedContext(o->scale, f->width, f->height, f->format, w, h, AV_PIX_FMT_BGRA,
                                    SWS_BILINEAR, NULL, NULL, NULL);
    if (!o->scale) return -1;
    uint8_t *planes[4] = {o->video};
    int strides[4] = {w * 4};
    if (sws_scale(o->scale, (const uint8_t *const *)f->data, f->linesize, 0, f->height, planes, strides) != h) return -1;
    int64_t duration = av_rescale_q(f->duration, d->stream->time_base, (AVRational){1, 1000});
    if (duration < 1 || duration > 1000) duration = 33;
    o->video_seen = 1;
    send_packet(PACKET_VIDEO, (int64_t)w * h * 4, w, h, frame_time(d, o, (int)duration), o->video);
    return 0;
}

static int audio_frame(struct decoder *d, struct output *o) {
    AVFrame *f = o->frame;
    int rate = f->sample_rate;
    if (rate < 8000 || rate > 192000 || f->ch_layout.nb_channels < 1 || f->ch_layout.nb_channels > 8 || f->nb_samples < 0 || f->nb_samples > MAX_AUDIO) return -1;
    if (!o->resample) {
        AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
        o->audio_format = f->format;
        o->audio_rate = rate;
        if (av_channel_layout_copy(&o->audio_layout, &f->ch_layout) < 0 ||
            swr_alloc_set_opts2(&o->resample, &stereo, AV_SAMPLE_FMT_S16, AUDIO_RATE, &o->audio_layout,
                                f->format, rate, 0, NULL) < 0 || swr_init(o->resample) < 0) return -1;
    } else if (f->format != o->audio_format || rate != o->audio_rate ||
               av_channel_layout_compare(&f->ch_layout, &o->audio_layout)) return -1;
    uint8_t *out[] = {o->audio};
    int size = swr_convert(o->resample, out, MAX_AUDIO, (const uint8_t **)f->extended_data, f->nb_samples);
    if (size < 0) return -1;
    if (size) {
        o->audio_seen = 1;
        send_packet(PACKET_AUDIO, size * 4, 0, 0, frame_time(d, o, size * 1000 / AUDIO_RATE), o->audio);
    }
    return 0;
}

static int drain_audio(struct decoder *d, struct output *o) {
    if (!o->resample) return 0;
    uint8_t *out[] = {o->audio};
    for (int i = 0; i < 16; i++) {
        int size = swr_convert(o->resample, out, MAX_AUDIO, NULL, 0);
        if (size <= 0) return size;
        if (d->next_ms < -86400000 || d->next_ms > 86400000) return -1;
        o->audio_seen = 1;
        send_packet(PACKET_AUDIO, size * 4, 0, 0, d->next_ms, o->audio);
        d->next_ms += size * 1000 / AUDIO_RATE;
    }
    return -1;
}

static int decode(struct decoder *d, struct output *o, const AVPacket *p, int video) {
    if (avcodec_send_packet(d->codec, p) < 0) return -1;
    for (;;) {
        int status = avcodec_receive_frame(d->codec, o->frame);
        if (status == AVERROR(EAGAIN) || status == AVERROR_EOF) return 0;
        if (status < 0) return -1;
        status = video ? video_frame(d, o) : audio_frame(d, o);
        av_frame_unref(o->frame);
        if (status < 0) return status;
    }
}

static int protected_stream(const struct decoder *d) {
    if (!d->stream) return 0;
    const AVCodecParameters *p = d->stream->codecpar;
    return p->codec_tag == MKTAG('e', 'n', 'c', 'v') || p->codec_tag == MKTAG('e', 'n', 'c', 'a') ||
           av_packet_side_data_get(p->coded_side_data, p->nb_coded_side_data, AV_PKT_DATA_ENCRYPTION_INIT_INFO) ||
           av_packet_side_data_get(p->coded_side_data, p->nb_coded_side_data, AV_PKT_DATA_ENCRYPTION_INFO);
}

int main(int argc, char **argv) {
    const int combined = argc == 2 && !strcmp(argv[1], "--combined");
    const int streaming = argc == 2 && !strcmp(argv[1], "--stream-fmp4");
    if (argc != 1 && !combined && !streaming) return 1;
    struct input in = {0};
    const char *format = NULL;
    if (streaming) format = "mov";
    else {
        struct stat st;
        uint8_t magic[12];
        if (fstat(1, &st) || !S_ISREG(st.st_mode) || st.st_size < (off_t)sizeof(magic) || st.st_size > MEDIA_INPUT_LIMIT ||
            pread(1, magic, sizeof(magic), 0) != sizeof(magic)) return 1;
        in.size = st.st_size;
        if (!memcmp(magic, "\x1a\x45\xdf\xa3", 4)) format = "matroska";
        else if (!memcmp(magic + 4, "ftyp", 4)) format = "mov";
        else if (!memcmp(magic, "OggS", 4)) format = "ogg";
    }
    if (!format || (combined && !strcmp(format, "ogg"))) return 1;
    const AVInputFormat *container = av_find_input_format(format);
    if (!container) return 1;
    av_log_set_level(AV_LOG_QUIET);
    if (isolate(streaming)) return 1;
    av_max_alloc(64u * 1024 * 1024);
    struct stream_input stream = {0};
    AVFormatContext *media = avformat_alloc_context();
    uint8_t *buffer = av_malloc(32768);
    if (!media || !buffer) return 1;
    if (streaming) {
        stream.bytes = av_malloc(APPEND_LIMIT);
        if (!stream.bytes) return 1;
        media->pb = avio_alloc_context(buffer, 32768, 0, &stream, read_append, NULL, NULL);
    } else media->pb = avio_alloc_context(buffer, 32768, 0, &in, read_media, NULL, seek_media);
    if (!media->pb) return 1;
    media->flags |= AVFMT_FLAG_CUSTOM_IO;
    media->io_open = deny_open;
    media->probesize = 1048576;
    media->max_analyze_duration = 1000000;
    media->max_streams = streaming ? 2 : 16;
    if (avformat_open_input(&media, NULL, container, NULL) < 0) return 1;
    /* The supported containers describe their codecs in their headers. Avoid a
       second, implicit decode with libavformat's unconstrained default contexts. */
    struct decoder video = {0}, audio = {0};
    select_stream(media, AVMEDIA_TYPE_VIDEO, &video);
    select_stream(media, AVMEDIA_TYPE_AUDIO, &audio);
    const int muxed = streaming && stream.track_count == 2;
    if (streaming && (media->nb_streams != (unsigned)stream.track_count || !video.stream ||
                      track_index(&stream, (uint32_t)video.stream->id) < 0 ||
                      video.stream->codecpar->codec_id != AV_CODEC_ID_H264 || protected_stream(&video))) return 1;
    if (muxed && (!audio.stream || audio.stream->id == video.stream->id ||
                  track_index(&stream, (uint32_t)audio.stream->id) < 0 ||
                  audio.stream->codecpar->codec_id != AV_CODEC_ID_AAC || protected_stream(&audio))) return 1;
    if (combined) {
        if (!video.stream || !audio.stream || protected_stream(&video) || protected_stream(&audio)) return 1;
        const enum AVCodecID v = video.stream->codecpar->codec_id, a = audio.stream->codecpar->codec_id;
        if (!strcmp(format, "mov")) {
            if (v != AV_CODEC_ID_H264 || a != AV_CODEC_ID_AAC) return 1;
        } else if ((v != AV_CODEC_ID_VP8 && v != AV_CODEC_ID_VP9) || (a != AV_CODEC_ID_OPUS && a != AV_CODEC_ID_VORBIS)) return 1;
    }
    if (open_decoder(&video) < 0) return 1;
    if (open_decoder(&audio) < 0) {
        if (combined || muxed) return 1;
        audio.index = -1;
    }
    struct output *out = calloc(1, sizeof(*out));
    AVPacket *packet = av_packet_alloc();
    if (!out || !packet || !(out->frame = av_frame_alloc())) return 1;
    out->streaming = streaming;
    out->muxed = muxed;
    if (!streaming && media->start_time > -86400000000LL && media->start_time < 86400000000LL) out->origin = media->start_time / 1000;
    if (muxed) send_packet(PACKET_STREAM_MUXED, 0, 0, 0, 0, NULL);
    if (media->duration > 0 && media->duration <= 86400000000LL) send_packet(PACKET_DURATION, 0, 0, 0, media->duration / 1000, NULL);
    int status;
    while ((status = av_read_frame(media, packet)) >= 0) {
        if ((combined || streaming) && (protected_stream(&video) || protected_stream(&audio) ||
                         av_packet_get_side_data(packet, AV_PKT_DATA_ENCRYPTION_INFO, NULL) ||
                         av_packet_get_side_data(packet, AV_PKT_DATA_ENCRYPTION_INIT_INFO, NULL))) return 1;
        if (packet->stream_index == video.index && decode(&video, out, packet, 1) < 0) return 1;
        if (packet->stream_index == audio.index && decode(&audio, out, packet, 0) < 0) return 1;
        av_packet_unref(packet);
    }
    if (status != AVERROR_EOF || ((combined || streaming) && (protected_stream(&video) || protected_stream(&audio))) ||
        decode(&video, out, NULL, 1) < 0) return 1;
    if (audio.index >= 0 && (decode(&audio, out, NULL, 0) < 0 || drain_audio(&audio, out) < 0)) return 1;
    if (combined && (!out->audio_seen || !out->video_seen)) return 1;
    if (streaming && (!stream.finished || !out->video_seen || (muxed && !out->audio_seen))) return 1;
    send_packet(PACKET_END, 0, 0, 0, 0, NULL);
    return 0;
}
