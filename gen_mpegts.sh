#!/bin/bash

# mpegts 测试视频生成脚本
# 生成YUV原始视频，再编码为mpegts

set -e

usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -f, --fps <帧率>        帧率 (默认: 30)"
    echo "  -c, --codec <编码类型>  h264 或 h265 (默认: h264)"
    echo "  -r, --resolution <分辨率> 4k, 1080p, 720p (默认: 1080p)"
    echo "  -d, --duration <时长>   时长秒数 (默认: 10)"
    echo "  -s, --sampling <采样格式> yuv444, yuv422, yuv420 (默认: yuv420)"
    echo "  -o, --output <输出文件>  输出文件名 (默认: auto)"
    echo "  -h, --help              显示帮助"
    exit 1
}

# 默认参数
FPS=30
CODEC="h264"
RESOLUTION="1080p"
DURATION=10
SAMPLING="yuv420"
OUTPUT=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--fps)
            FPS="$2"
            shift 2
            ;;
        -c|--codec)
            CODEC="$2"
            shift 2
            ;;
        -r|--resolution)
            RESOLUTION="$2"
            shift 2
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -s|--sampling)
            SAMPLING="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "未知选项: $1"
            usage
            ;;
    esac
done

# 验证参数
case $CODEC in
    h264|h265) ;;
    *) echo "错误: codec 必须是 h264 或 h265"; exit 1 ;;
esac

case $RESOLUTION in
    4k|1080p|720p) ;;
    *) echo "错误: resolution 必须是 4k, 1080p, 或 720p"; exit 1 ;;
esac

case $SAMPLING in
    yuv444|yuv422|yuv420) ;;
    *) echo "错误: sampling 必须是 yuv444, yuv422, 或 yuv420"; exit 1 ;;
esac

# 分辨率映射
case $RESOLUTION in
    4k)    WIDTH=3840; HEIGHT=2160 ;;
    1080p) WIDTH=1920; HEIGHT=1080 ;;
    720p)  WIDTH=1280; HEIGHT=720 ;;
esac

# 采样格式映射 (ffmpeg像素格式)
case $SAMPLING in
    yuv444) PIX_FMT="yuv444p" ;;
    yuv422) PIX_FMT="yuv422p" ;;
    yuv420) PIX_FMT="yuv420p" ;;
esac

# 编码器映射
case $CODEC in
    h264) ENCODER="libx264" ;;
    h265) ENCODER="libx265" ;;
esac

# 生成默认输出文件名
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="test_${RESOLUTION}_${CODEC}_${FPS}fps_${DURATION}s_${SAMPLING}.mpegts"
fi

# 创建临时目录
TEMP_DIR=$(mktemp -d)
YUV_FILE="${TEMP_DIR}/input.yuv"

echo "=== mpegts 测试视频生成 ==="
echo "分辨率: ${WIDTH}x${HEIGHT}"
echo "帧率: ${FPS} fps"
echo "编码: ${CODEC}"
echo "时长: ${DURATION}s"
echo "采样格式: ${SAMPLING} (${PIX_FMT})"
echo "输出文件: ${OUTPUT}"
echo ""

# 使用testsrc2生成测试图案YUV
echo "正在生成测试YUV..."
ffmpeg -hide_banner -loglevel error \
    -f lavfi -i "testsrc2=size=${WIDTH}x${HEIGHT}:rate=${FPS}:duration=${DURATION}" \
    -f lavfi -i "sine=frequency=1000:sample_rate=48000:duration=${DURATION}" \
    -pix_fmt $PIX_FMT \
    -c:v rawvideo -c:a aac \
    -y "${TEMP_DIR}/test_src.mp4" 2>/dev/null || true

# 提取YUV
ffmpeg -hide_banner -loglevel error \
    -i "${TEMP_DIR}/test_src.mp4" \
    -pix_fmt $PIX_FMT \
    -c:v rawvideo \
    -y "$YUV_FILE" 2>/dev/null

# 获取实际帧数
FRAME_COUNT=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of default=nokey=1:noprint_wrappers=1 "$YUV_FILE" 2>/dev/null || echo "")
if [[ -z "$FRAME_COUNT" ]]; then
    FRAME_COUNT=$((FPS * DURATION))
fi

echo "YUV文件生成完成 (${FRAME_COUNT}帧)"

# 编码为mpegts
echo "正在编码为${CODEC} mpegts..."

# H.264/H.265 编码参数:
# - gfpsycle=1: 关键帧间隔1秒
# - bf 0: 无B帧
# - qp 0: 固定QP为0（最好质量）
case $CODEC in
    h264)
        ffmpeg -hide_banner -loglevel error \
            -f rawvideo -pix_fmt $PIX_FMT -s ${WIDTH}x${HEIGHT} -r $FPS -i "$YUV_FILE" \
            -c:v $ENCODER \
            -g $FPS \
            -bf 0 \
            -qp 0 \
            -preset ultrafast \
            -f mpegts \
            -y "$OUTPUT"
        ;;
    h265)
        ffmpeg -hide_banner -loglevel error \
            -f rawvideo -pix_fmt $PIX_FMT -s ${WIDTH}x${HEIGHT} -r $FPS -i "$YUV_FILE" \
            -c:v $ENCODER \
            -g $FPS \
            -bf 0 \
            -qp 0 \
            -preset ultrafast \
            -f mpegts \
            -y "$OUTPUT"
        ;;
esac

# 清理临时文件
rm -rf "$TEMP_DIR"

if [[ -f "$OUTPUT" ]]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    echo ""
    echo "=== 完成 ==="
    echo "输出文件: $OUTPUT"
    echo "文件大小: $SIZE"
else
    echo "错误: 生成失败"
    exit 1
fi
