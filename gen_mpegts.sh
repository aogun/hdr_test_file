#!/bin/bash

# mpegts 测试视频生成脚本
# 生成64色块测试图案YUV，再编码为mpegts

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

# 使用Python生成64色块测试图案
echo "正在生成64色块测试图案..."
python3 << PYEOF
import struct
import math

# 参数
WIDTH = $WIDTH
HEIGHT = $HEIGHT
FPS = $FPS
DURATION = $DURATION
SAMPLING = "$SAMPLING"
YUV_FILE = "$YUV_FILE"

# 8x8 = 64 blocks
GRID = 8
BLOCK_W = WIDTH // GRID
BLOCK_H = HEIGHT // GRID

# 字体大小（相对于色块大小）
FONT_SCALE = min(BLOCK_W, BLOCK_H) // 16

# YUV值: 使用64个不同的亮度值和固定色度
# 色块序号从0到63，对应Y值从16到235（ITU-R BT.601范围）
def get_yuv_values(idx):
    # Y: 16到235，均匀分布
    y = int(16 + (idx / 63.0) * (235 - 16))
    # U/V: 使用固定值来显示不同的色度变化
    u = 128 + int(math.sin(idx * math.pi / 32) * 40)
    v = 128 + int(math.cos(idx * math.pi / 32) * 40)
    return y, u, v

# 简单的位图字体（3x5数字）
DIGITS = {
    '0': [0x7C, 0x82, 0x82, 0x82, 0x7C],
    '1': [0x00, 0x84, 0xFE, 0x80, 0x00],
    '2': [0xC4, 0xA2, 0x92, 0x92, 0x8C],
    '3': [0x44, 0x82, 0x92, 0x92, 0x6C],
    '4': [0x30, 0x28, 0x24, 0xFE, 0x20],
    '5': [0x4E, 0x8A, 0x8A, 0x8A, 0x72],
    '6': [0x78, 0x94, 0x92, 0x92, 0x60],
    '7': [0x02, 0xE2, 0x12, 0x0A, 0x06],
    '8': [0x6C, 0x92, 0x92, 0x92, 0x6C],
    '9': [0x0C, 0x92, 0x92, 0x52, 0x3C],
}

def draw_char(frame, x, y, char, y_val, font_size):
    """在YUV frame上绘制字符"""
    if char not in DIGITS:
        return
    bitmap = DIGITS[char]
    for row in range(5):
        for col in range(3):
            if bitmap[row] & (0x80 >> col):
                # 绘制像素点
                for dy in range(font_size // 5):
                    for dx in range(font_size // 3):
                        px = x + col * (font_size // 3) + dx
                        py = y + row * (font_size // 5) + dy
                        if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                            frame[py][px] = y_val

def draw_text_centered(frame, bx, by, bw, bh, text, y_val, font_size):
    """在色块中心绘制文字"""
    # 计算文字宽度（估算）
    text_w = len(text) * (font_size // 3) * 3
    text_h = font_size
    start_x = bx + (bw - text_w) // 2
    start_y = by + (bh - text_h) // 2
    for i, char in enumerate(text):
        draw_char(frame, start_x + i * (font_size // 3) * 3, start_y, char, y_val, font_size)

# 生成YUV444帧
def generate_frame(frame_num):
    frame_y = [[128] * WIDTH for _ in range(HEIGHT)]
    frame_u = [[128] * WIDTH for _ in range(HEIGHT)]
    frame_v = [[128] * WIDTH for _ in range(HEIGHT)]

    for idx in range(64):
        row = idx // GRID
        col = idx % GRID
        y_val, u_val, v_val = get_yuv_values(idx)

        bx = col * BLOCK_W
        by = row * BLOCK_H

        # 填充色块
        for py in range(by, min(by + BLOCK_H, HEIGHT)):
            for px in range(bx, min(bx + BLOCK_W, WIDTH)):
                frame_y[py][px] = y_val
                frame_u[py][px] = u_val
                frame_v[py][px] = v_val

        # 在色块中心绘制文字
        text = str(idx)
        draw_text_centered(frame_y, bx, by, BLOCK_W, BLOCK_H, text, y_val, FONT_SCALE)
        # YUV值也显示在下方
        yuv_text = f"{y_val},{u_val},{v_val}"
        draw_text_centered(frame_y, bx, by + BLOCK_H // 2, BLOCK_W, BLOCK_H // 2, yuv_text[:5], y_val, FONT_SCALE // 2)

    return frame_y, frame_u, frame_v

# 写入YUV文件
total_frames = FPS * DURATION
with open(YUV_FILE, 'wb') as f:
    for frame_num in range(total_frames):
        frame_y, frame_u, frame_v = generate_frame(frame_num)
        # 写入Y平面
        for row in frame_y:
            f.write(bytes(row))
        # 写入U平面
        for row in frame_u:
            f.write(bytes(row))
        # 写入V平面
        for row in frame_v:
            f.write(bytes(row))

print(f"YUV生成完成: {total_frames}帧")
PYEOF

echo "YUV文件生成完成"

# 编码为mpegts
echo "正在编码为${CODEC} mpegts..."

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
