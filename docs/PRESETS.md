# Presets

All presets share the same base: SDR 8-bit Rec.709 canvas (NV12 / Partial, SDR white 300),
canvas = output resolution, CBR stream with 2-second keyframes, AAC 160 kbps audio,
hybrid MP4 recording with tracks 1, 3 and 4, a 60-second replay buffer, Advanced output
mode. The catalogue lives in [`presets/presets.psd1`](../presets/presets.psd1).

## The list

| Preset | Canvas | FPS | Stream | Recording | Upload needed* |
|---|---|---|---|---|---|
| `1080p60` | 1920×1080 | 60 | H.264 6000 kbps | light HEVC CQ 22 | ~7 Mbps |
| `1080p30` | 1920×1080 | 30 | H.264 4500 kbps | light HEVC CQ 22 | ~5.5 Mbps |
| `720p60` | 1280×720 | 60 | H.264 4500 kbps | light HEVC CQ 22 | ~5.5 Mbps |
| `720p30` | 1280×720 | 30 | H.264 3000 kbps | light HEVC CQ 22 | ~4 Mbps |
| `youtube-1080p60` | 1920×1080 | 60 | HEVC 12 Mbps (H.264 17 Mbps on x264) | light HEVC CQ 22 | ~14 Mbps |
| `youtube-1440p60` | 2560×1440 | 60 | HEVC 24 Mbps (H.264 34 Mbps on x264) | light HEVC CQ 22 | ~28 Mbps |
| `record-1080p60` | 1920×1080 | 60 | H.264 6000 kbps | quality HEVC CQ 18 | – |
| `record-1440p60` | 2560×1440 | 60 | H.264 6000 kbps, scaled to 1080p | quality HEVC CQ 18 | – |
| `vertical` | 1080×1920 | 30 | H.264 6000 kbps | light HEVC CQ 22 | ~7 Mbps |

\* Video + audio + about 15 % headroom. Run a speed test; if your upload is below the
number, pick the next preset down.

## Where the numbers come from

- **Twitch** broadcasting guidelines: 1080p60 6000, 1080p30 4500, 720p60 4500, 720p30 3000
  kbps, CBR, 2 s keyframes, 2 B-frames, AAC up to 160 kbps.
- **Kick**: up to 8000 kbps, CBR, H.264 only, 2 s keyframes - the four Stream presets fit.
- **YouTube** live encoder settings: recommended HEVC/AV1 12 Mbps at 1080p60 and 24 Mbps at
  1440p60 (H.264: 17 and 34 Mbps), CBR, 2 s keyframes, Rec.709 8-bit for SDR. YouTube's own table asks
  about 30 % less bitrate for HEVC than for H.264, so the YouTube presets stream HEVC
  wherever the GPU has it.
- **Vertical**: TikTok and YouTube publish no exact vertical bitrate. 6000 kbps at
  1080×1920 30 fps is a middle value; lower it in **Settings → Output → Streaming** to
  4000 if your upload is tight.

## Recording modes

- **light** (stream presets): a second hardware encoder session that runs while you play
  and stream - HEVC Main 8-bit, CQ 22, preset P4 (NVENC) / balanced (AMF) / TU4 (Quick
  Sync), no B-frames. On x264 there is no second session: the recording shares the stream
  encoder so the CPU is not doubled.
- **quality** (record presets): HEVC Main 8-bit, CQ 18, preset P5 / quality / TU2, two
  B-frames where the GPU supports them (the installer asks the NVENC probe). x264: CRF 18
  veryfast.

Recordings land in OBS's default folder (your Videos folder) as hybrid MP4: a crash or
power cut leaves a playable file. OBS's file splitting is off; turn it on under
**Settings → Output → Recording → Automatic File Splitting** if you want it.

## Encoder families

| Family | Stream (H.264 / HEVC) | Record | Picked when |
|---|---|---|---|
| NVIDIA NVENC | `obs_nvenc_h264_tex` / `obs_nvenc_hevc_tex`, P5, hq, AQ on | HEVC (H.264 on cards without HEVC) | `obs-nvenc-test` reports NVENC |
| AMD AMF | `h264_texture_amf` / `h265_texture_amf`, quality | HEVC (or H.264) | `obs-amf-test` reports an AMD encoder |
| Intel Quick Sync | `obs_qsv11_v2` / `obs_qsv11_hevc`, TU2 | HEVC (or H.264) | `obs-qsv-test` reports an Intel encoder |
| x264 | `obs_x264`, veryfast, high | shares the stream encoder (light) | nothing else found |

Force one with `-Encoder nvenc|amf|qsv|x264`. Re-running the installer with a different
encoder re-applies the presets for it and keeps your account and hotkeys.

## Adding your own preset

Copy an entry in `presets/presets.psd1`, give it a new `Id` and a `Name` starting with
`OBS-Forge `, and run `.\Install.ps1 -Preset <your id>`. `Verify.ps1` and `Uninstall.ps1`
pick it up automatically; `tests\Run-Tests.ps1` checks the catalogue.
