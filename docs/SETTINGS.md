# Settings, value by value

Every key the pack writes, and why. OBS rewrites these files when you change something in
the UI; `Verify.ps1` tells you when a profile has drifted away from the pack.

## `[Video]`

| Key | Value | Why |
|---|---|---|
| `BaseCX` / `BaseCY` | 1920 / 1080 | Canvas = output. A 1440p canvas downscaled to 1080p costs GPU for no viewer benefit. |
| `OutputCX` / `OutputCY` | 1920 / 1080 | 1080p is what every destination ingests cleanly. |
| `FPSCommon` | 60 (or 30) | 60 for the main profile, 30 for the light one. |
| `ScaleType` | `bicubic` | Cheap and sharp enough at 1:1; Lanczos costs GPU for nothing here. |
| `ColorFormat` | `NV12` | 8-bit 4:2:0 — the only format the H.264 stream encoder can output. |
| `ColorSpace` | `709` | Rec.709 is the SDR standard every player expects. `sRGB` also works; Rec.2100 does not (see HDR.md). |
| `ColorRange` | `Partial` | TV range (16–235). Full range gets crushed by most players. |
| `SdrWhiteLevel` | 300 | The nit level that maps to SDR white when OBS tone-maps an HDR source. Raise if HDR games look washed out, lower if they look dark. |
| `HdrNominalPeakLevel` | 1000 | Only used for HDR output, which these profiles do not do. Harmless. |

## `[AdvOut]` — stream

| Key | Value | Why |
|---|---|---|
| `Encoder` | `obs_nvenc_h264_tex` | H.264 8-bit. Twitch/Kick/Rumble ingest it everywhere; AV1/HEVC are not accepted at 1080p. |
| `RecEncoder` | `obs_nvenc_hevc_tex` | HEVC is a second NVENC session, used only for recording. |
| `RecTracks` | `13` | Tracks 1, 3 and 4: programme, plus two spare language tracks. |
| `RecRB` / `RecRBTime` | `true` / 60 | 60 s replay buffer. |
| `RecSplitFileTime` | 15 | Split recordings every 15 minutes so a crash loses less. |
| `FFOutputToFile` | `false` | No separate FFmpeg output; the standard recording is enough. |

## `streamEncoder.json`

| Key | Value | Why |
|---|---|---|
| `rate_control` | `CBR` | Constant bitrate is what the ingest expects. |
| `bitrate` | 6000 / 4500 | Twitch's 1080p ceiling is 6000; 4500 is the safe profile. |
| `keyint_sec` | 2 | Twitch recommends 2 s. |
| `preset2` | `p5` | NVENC's balanced preset (P1 fastest … P7 slowest). |
| `tune` | `hq` | Higher quality per bit. |
| `multipass` | `disabled` | One pass; two passes cost GPU. |
| `profile` | `high` | Widest player support for H.264. |
| `bf` | 2 | Two B-frames, free quality on Ada. |
| `lookahead` | `false` | Look-ahead adds latency and GPU. |
| `psycho_aq` | `true` | Adaptive quantization keeps dark gradients clean. |

## `recordEncoder.json`

| Key | Value | Why |
|---|---|---|
| `rate_control` | `CQP` | Constant quality; file size follows the content. |
| `cqp` | 22 | Visually clean for a stream recording. 20 is a master, 24 is smaller. |
| `preset2` | `p4` | One step faster than the stream preset: this session runs while you play. |
| `profile` | `main` | 8-bit HEVC. Never `main10` on an SDR canvas. |
| `bf` | 0 | No B-frames: cheapest for the second session. |
| `multipass` | `qres` | Quarter-resolution motion search, faster than full. |

## `[Output]`

| Key | Value | Why |
|---|---|---|
| `Mode` | `Advanced` | Needed for separate stream and record encoders. |
| `DynamicBitrate` | `true` | Drops bitrate instead of dropping frames when upload dips. |
| `Reconnect` / `MaxRetries` | `true` / 25 | Survives a short network blip. |
| `LowLatencyEnable` | `false` | Normal latency is more stable for a mixed-destination stream. |

## Scene collection

`OBS-Forge` has four scenes — Starting Soon, Live, BRB, Ending — each a dark background
with a centred label (Live has no label so gameplay fills the frame). Add your game
capture, mic and camera to Live; the other three are placeholders you can restyle.

Nothing in the collection phones home, loads a URL, or references a local path.