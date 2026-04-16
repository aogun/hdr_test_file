# gen_color_mpegts.sh - 单色 YUV MPEGTS 生成脚本

## 概述

Bash 脚本，根据指定的 YUV 值、采样格式、位深、编码类型生成**无损压缩**的 MPEGTS 视频文件。所有帧填充同一个 YUV 常量值。

固定配置：
- 帧率：24 fps
- GOP：每秒 1 个 I 帧（GOP = 24）
- 编码：无损压缩

## 依赖

- Python 3（生成 raw YUV 数据，通过管道传给 ffmpeg）
- FFmpeg（libx264 / libx265，需支持 10-bit 编码）

## 命令行参数

| 参数 | 短选项 | 长选项 | 默认值 | 说明 |
|------|--------|--------|--------|------|
| Y 分量 | `-Y` | `--y-value` | 128 / 512 | 随位深变化 |
| U 分量 | `-U` | `--u-value` | 128 / 512 | 随位深变化 |
| V 分量 | `-V` | `--v-value` | 128 / 512 | 随位深变化 |
| 采样格式 | `-s` | `--sampling` | yuv420 | yuv444 / yuv422 / yuv420 |
| 位深 | `-b` | `--bit-depth` | 8 | 8 或 10 |
| 编码 | `-c` | `--codec` | h264 | h264 或 h265 |
| 时长 | `-d` | `--duration` | 5 | 秒 |
| 分辨率 | `-r` | `--resolution` | 1080p | 4k / 1080p / 720p |
| HDR模式 | `-m` | `--mode` | sdr | sdr / pq / hlg |
| 输出 | `-o` | `--output` | 自动生成 | 输出文件路径 |

默认输出文件名：`color_Y{y}_U{u}_V{v}_{采样}_{位深}bit_{模式}_{编码}_{时长}s.ts`

## YUV 值范围

| 位深 | 范围 | 默认值（中值灰） |
|------|------|------------------|
| 8-bit  | 0 ~ 255  | 128 |
| 10-bit | 0 ~ 1023 | 512 |

## 像素格式映射

| 采样 + 位深 | FFmpeg pix_fmt |
|-------------|----------------|
| yuv420 + 8  | yuv420p        |
| yuv422 + 8  | yuv422p        |
| yuv444 + 8  | yuv444p        |
| yuv420 + 10 | yuv420p10le    |
| yuv422 + 10 | yuv422p10le    |
| yuv444 + 10 | yuv444p10le    |

10-bit 格式每个样本占 2 字节（小端），低 10 位存储实际值。

## 无损编码参数

| 编码器 | 参数 | 说明 |
|--------|------|------|
| libx264 | `-qp 1 -profile:v <high/high10/high422/high444>` | 对单色填充为 bit-exact，避免 Lossless profile 的兼容性问题 |
| libx265 | `-x265-params lossless=1:colorprim=...:transfer=...:colormatrix=...:range=limited` | 真无损，兼容 Main/Main10/Rext profile |

### 为什么 H.264 不使用 `-qp 0`

`-qp 0` 触发 x264 的 lossless 模式，强制使用 **High 4:4:4 Lossless** profile（PPS 中 `transform_bypass_mode_flag=1`）。大量硬件/软件 H.264 解码器不支持该 profile，报错如：

```
h264d_sps: ERROR: Not support high 4:4:4 lossless mode
```

改用 `-qp 1`（最小非零 QP）后：
- 对单色填充的块，DCT 系数仅 DC 项非零且为整数，quantization step=1 不丢失信息 → bit-exact
- 不触发 Lossless 模式 → profile 按 pix_fmt 走标准分支（High/High422/High 4:4:4 Predictive）
- 兼容主流解码器

### H.264 Profile 映射

| 采样 + 位深 | `-profile:v` | 实际 Profile（preset ultrafast） |
|-------------|-------------|----------------------------------|
| yuv420 + 8  | high    | Constrained Baseline ~ High |
| yuv420 + 10 | high10  | High 10 |
| yuv422 + 任意 | high422 | High 4:2:2 |
| yuv444 + 任意 | high444 | High 4:4:4 Predictive |

## HDR 模式色彩元数据映射

每个模式向码流的 VUI 写入以下元数据（`ffmpeg -color_primaries/-color_trc/-colorspace/-color_range`）：

| 模式 | color_primaries | color_trc | color_space (matrix) | 典型位深 |
|------|-----------------|-----------|----------------------|----------|
| sdr  | bt709           | bt709          | bt709    | 8 或 10  |
| pq   | bt2020          | smpte2084      | bt2020nc | 10       |
| hlg  | bt2020          | arib-std-b67   | bt2020nc | 10       |

- `color_range` 统一为 tv（limited range）
- PQ/HLG 与 8-bit 组合会打印警告（标准推荐 10-bit）
- H.265 除 ffmpeg VUI 参数外，同时通过 `-x265-params` 再写入一次，确保元数据被嵌入到 HEVC 码流的 VPS/SPS 中
- H.264 的 VUI 元数据通过 ffmpeg 的 `-color_*` 选项传递给 libx264

## 处理流程

```
参数解析/验证
    ↓
Python 生成单帧 YUV 字节（三个平面按采样格式分配尺寸）
    ↓
Python 循环 N 次写入 stdout
    ↓
管道传给 FFmpeg → 按 pix_fmt 读取 rawvideo → 无损编码
    ↓
输出 MPEGTS 文件
```

相比临时文件方式，管道流避免了磁盘写入，对长时长视频更高效。

## YUV 数据生成

对于每一帧：

1. 计算色度平面尺寸：
   - yuv444：`W × H`
   - yuv422：`W/2 × H`
   - yuv420：`W/2 × H/2`
2. 根据位深生成一个样本的字节序列：
   - 8-bit：`bytes([V])`（1 字节）
   - 10-bit：`V.to_bytes(2, 'little')`（2 字节小端）
3. 重复样本填充三个平面，依次写入
4. 所有帧内容相同，循环写入 `FPS × DURATION` 次

## 验证过的组合

**基础采样/位深矩阵（720p 各 1 秒）**：解码后 YUV 值与输入精确匹配

| 采样 | 位深 | 编码 | Profile | 结果 |
|------|------|------|---------|------|
| yuv420 | 8  | h264 | High 4:4:4 Predictive | PASS |
| yuv422 | 10 | h264 | High 4:4:4 Predictive | PASS |
| yuv444 | 10 | h265 | Rext                  | PASS |
| yuv420 | 8  | h265 | Main                  | PASS |

**HDR 模式矩阵**：ffprobe 读取到的色彩元数据与预期完全一致

| 模式 | 编码 | primaries | trc | matrix | range |
|------|------|-----------|-----|--------|-------|
| sdr | h265 | bt709  | bt709        | bt709    | tv |
| pq  | h265 | bt2020 | smpte2084    | bt2020nc | tv |
| hlg | h265 | bt2020 | arib-std-b67 | bt2020nc | tv |
| pq  | h264 | bt2020 | smpte2084    | bt2020nc | tv |

注：H.264 无损模式（`-qp 0`）会强制使用 High 4:4:4 Predictive profile，这是 x264 的固有行为。H.265 无损模式 profile 跟随 pix_fmt 正常选择。
