#!/bin/bash

# 单色YUV mpegts 生成脚本
# 根据指定YUV值、采样格式、位深、编码类型生成无损mpegts文件
# 帧率固定24fps，GOP=1秒

set -eo pipefail

# 默认参数
Y_VAL=""
U_VAL=""
V_VAL=""
SAMPLING="yuv420"
BIT_DEPTH=8
CODEC="h264"
DURATION=5
RESOLUTION="1080p"
OUTPUT=""
FPS=24

usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -Y, --y-value <值>        Y 分量值（默认: 128 (8bit) / 512 (10bit)）"
    echo "  -U, --u-value <值>        U 分量值（默认: 128 (8bit) / 512 (10bit)）"
    echo "  -V, --v-value <值>        V 分量值（默认: 128 (8bit) / 512 (10bit)）"
    echo "  -s, --sampling <格式>     yuv444/yuv422/yuv420（默认: yuv420）"
    echo "  -b, --bit-depth <位深>    8 或 10（默认: 8）"
    echo "  -c, --codec <编码>        h264 或 h265（默认: h264）"
    echo "  -d, --duration <时长>     时长秒数（默认: 5）"
    echo "  -r, --resolution <分辨率> 4k/1080p/720p（默认: 1080p）"
    echo "  -o, --output <输出文件>   输出文件名（默认: auto）"
    echo "  -h, --help                显示帮助"
    exit 1
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -Y|--y-value)    Y_VAL="$2"; shift 2 ;;
        -U|--u-value)    U_VAL="$2"; shift 2 ;;
        -V|--v-value)    V_VAL="$2"; shift 2 ;;
        -s|--sampling)   SAMPLING="$2"; shift 2 ;;
        -b|--bit-depth)  BIT_DEPTH="$2"; shift 2 ;;
        -c|--codec)      CODEC="$2"; shift 2 ;;
        -d|--duration)   DURATION="$2"; shift 2 ;;
        -r|--resolution) RESOLUTION="$2"; shift 2 ;;
        -o|--output)     OUTPUT="$2"; shift 2 ;;
        -h|--help)       usage ;;
        *) echo "未知选项: $1"; usage ;;
    esac
done

# 验证枚举参数
case $SAMPLING in
    yuv444|yuv422|yuv420) ;;
    *) echo "错误: sampling 必须是 yuv444/yuv422/yuv420"; exit 1 ;;
esac

case $BIT_DEPTH in
    8|10) ;;
    *) echo "错误: bit-depth 必须是 8 或 10"; exit 1 ;;
esac

case $CODEC in
    h264|h265) ;;
    *) echo "错误: codec 必须是 h264 或 h265"; exit 1 ;;
esac

case $RESOLUTION in
    4k|1080p|720p) ;;
    *) echo "错误: resolution 必须是 4k/1080p/720p"; exit 1 ;;
esac

# 根据位深设置YUV默认值和范围上限
if [[ $BIT_DEPTH == 10 ]]; then
    DEFAULT_VAL=512
    MAX_VAL=1023
else
    DEFAULT_VAL=128
    MAX_VAL=255
fi

[[ -z "$Y_VAL" ]] && Y_VAL=$DEFAULT_VAL
[[ -z "$U_VAL" ]] && U_VAL=$DEFAULT_VAL
[[ -z "$V_VAL" ]] && V_VAL=$DEFAULT_VAL

# 验证YUV值范围
for name in Y U V; do
    var="${name}_VAL"
    val="${!var}"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val < 0 || val > MAX_VAL )); then
        echo "错误: ${name} 值 '$val' 无效或超出 ${BIT_DEPTH}-bit 范围 [0, $MAX_VAL]"
        exit 1
    fi
done

# 分辨率映射
case $RESOLUTION in
    4k)    WIDTH=3840; HEIGHT=2160 ;;
    1080p) WIDTH=1920; HEIGHT=1080 ;;
    720p)  WIDTH=1280; HEIGHT=720 ;;
esac

# 像素格式映射
if [[ $BIT_DEPTH == 8 ]]; then
    case $SAMPLING in
        yuv444) PIX_FMT="yuv444p" ;;
        yuv422) PIX_FMT="yuv422p" ;;
        yuv420) PIX_FMT="yuv420p" ;;
    esac
else
    case $SAMPLING in
        yuv444) PIX_FMT="yuv444p10le" ;;
        yuv422) PIX_FMT="yuv422p10le" ;;
        yuv420) PIX_FMT="yuv420p10le" ;;
    esac
fi

# 编码器
case $CODEC in
    h264) ENCODER="libx264" ;;
    h265) ENCODER="libx265" ;;
esac

# 无损编码参数（数组形式，避免 word-splitting 歧义）
case $CODEC in
    h264) LOSSLESS_ARGS=(-qp 0) ;;
    h265) LOSSLESS_ARGS=(-x265-params lossless=1) ;;
esac

# 生成默认输出文件名
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="color_Y${Y_VAL}_U${U_VAL}_V${V_VAL}_${SAMPLING}_${BIT_DEPTH}bit_${CODEC}_${DURATION}s.ts"
fi

TOTAL_FRAMES=$((FPS * DURATION))
GOP=$FPS  # GOP = 1 秒

echo "=== 单色 YUV mpegts 生成 ==="
echo "分辨率: ${WIDTH}x${HEIGHT}"
echo "帧率:   ${FPS} fps"
echo "GOP:    ${GOP} (每秒1个I帧)"
echo "时长:   ${DURATION}s (${TOTAL_FRAMES} 帧)"
echo "采样:   ${SAMPLING} (${PIX_FMT})"
echo "位深:   ${BIT_DEPTH}-bit"
echo "YUV值:  Y=${Y_VAL}, U=${U_VAL}, V=${V_VAL}"
echo "编码:   ${CODEC} (无损)"
echo "输出:   ${OUTPUT}"
echo ""

# 通过Python生成raw YUV流，直接pipe给ffmpeg，避免临时文件
echo "正在生成并编码..."
python3 -c "
import sys

Y, U, V = $Y_VAL, $U_VAL, $V_VAL
W, H = $WIDTH, $HEIGHT
BIT = $BIT_DEPTH
SAMP = '$SAMPLING'
N = $TOTAL_FRAMES

if SAMP == 'yuv444':
    cw, ch = W, H
elif SAMP == 'yuv422':
    cw, ch = W // 2, H
else:
    cw, ch = W // 2, H // 2

if BIT == 8:
    y_plane = bytes([Y]) * (W * H)
    u_plane = bytes([U]) * (cw * ch)
    v_plane = bytes([V]) * (cw * ch)
else:
    # 10-bit：每个样本2字节小端，低10位存储实际值
    y_plane = Y.to_bytes(2, 'little') * (W * H)
    u_plane = U.to_bytes(2, 'little') * (cw * ch)
    v_plane = V.to_bytes(2, 'little') * (cw * ch)

frame = y_plane + u_plane + v_plane
out = sys.stdout.buffer
for _ in range(N):
    out.write(frame)
" | ffmpeg -hide_banner -loglevel error \
    -f rawvideo -pix_fmt "$PIX_FMT" -s "${WIDTH}x${HEIGHT}" -r "$FPS" -i - \
    -c:v "$ENCODER" \
    -g "$GOP" \
    -bf 0 \
    "${LOSSLESS_ARGS[@]}" \
    -preset ultrafast \
    -f mpegts \
    -y "$OUTPUT"

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
