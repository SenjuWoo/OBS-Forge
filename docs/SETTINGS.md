# Settings, value by value

Every key the pack writes for the `1080p60` NVENC preset, and why. Other presets change
the canvas, FPS, bitrate and encoder ids (see [PRESETS.md](PRESETS.md)); the rest is the
same. OBS rewrites these files when you change something in the UI; `Verify.ps1` tells you
when a profile has drifted away from the pack.

Keys were checked against the OBS 33.0.2 source. Since OBS 31 the NVENC encoders
(`obs_nvenc_*`) read `preset` and `adaptive_quantization`; the older `preset2` / `psycho_aq`
keys are only translated for the pre-31 encoder ids, so OBS-Forge 0.1.0's record preset P4
was silently ignored (it ran P5). 0.2.0 writes the current keys and upgrades old installs.

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
| `RecTracks` | `13` | Bit mask: tracks 1, 3 and 4 - programme, plus two spare tracks. |
| `RecFormat2` | `hybrid_mp4` | MP4 that stays playable after a crash or power cut. |
| `RecRB` / `RecRBTime` | `true` / 60 | 60 s replay buffer (start it from the Controls dock). |
| `RecSplitFileTime` | 15 | OBS's own default. Splitting stays **off** (`RecSplitFile` is not set): hybrid MP4 already survives a crash. |
| `UseRescale` / `RescaleRes` | `false` (`record-1440p60`: `true` / `1920x1080`) | Stream scaled on the GPU while recording keeps the full canvas. |
| `FFOutputToFile` | `false` | No separate FFmpeg output; the standard recording is enough. |

## `streamEncoder.json`

| Key | Value | Why |
|---|---|---|
| `rate_control` | `CBR` | Constant bitrate is what the ingest expects. |
| `bitrate` | 6000 / 4500 | Twitch's 1080p ceiling is 6000; 4500 is the safe profile. |
| `keyint_sec` | 2 | Twitch recommends 2 s. |
| `preset` | `p5` | NVENC preset (P1 fastest … P7 slowest); P5 is OBS's default and Twitch's "Quality". |
| `tune` | `hq` | Higher quality per bit. |
| `multipass` | `disabled` | One pass; two passes cost GPU. |
| `profile` | `high` | Widest player support for H.264. |
| `bf` | 2 | Two B-frames, as Twitch and YouTube recommend. HEVC streams use 2 only where the NVENC probe reports HEVC B-frames (Turing and newer). |
| `lookahead` | `false` | Look-ahead adds latency and GPU. |
| `adaptive_quantization` | `true` | Adaptive quantization keeps dark gradients clean. |

## `recordEncoder.json`

| Key | Value | Why |
|---|---|---|
| `rate_control` | `CQP` | Constant quality; file size follows the content. |
| `cqp` | 22 | Visually clean for a stream recording. 20 is a master, 24 is smaller. |
| `preset` | `p4` | One step faster than the stream preset: this session runs while you play. (Record presets: `p5`, CQ 18.) |
| `profile` | `main` | 8-bit HEVC. Never `main10` on an SDR canvas. |
| `bf` | 0 | No B-frames: cheapest for the second session. (Record presets: 2 where supported.) |
| `multipass` | `qres` | Quarter-resolution motion search, faster than full. |

## `[Output]`

| Key | Value | Why |
|---|---|---|
| `Mode` | `Advanced` | Needed for separate stream and record encoders. |
| `DynamicBitrate` | `true` | Drops bitrate instead of dropping frames when upload dips. |
| `Reconnect` / `MaxRetries` | `true` / 25 | Survives a short network blip. |
| `LowLatencyEnable` | `false` | Normal latency is more stable for a mixed-destination stream. |

## Other encoders

AMD AMF, Intel Quick Sync and x264 get the equivalent settings: CBR at the same bitrate,
2 s keyframes, H.264 `high` / HEVC `main` (8-bit), and for recording CQP 22 (light) or 18
(quality). The exact JSON per family is in [PRESETS.md](PRESETS.md) and
`lib/OBSForge.psm1` (`New-ForgeStreamSettings`, `New-ForgeRecordSettings`).

## `obs-forge.json`

A small marker file in each profile folder: pack version, preset id, encoder family and
what was written. `Verify.ps1` compares against it, `Uninstall.ps1` uses it to find only
the pack's profiles, and the installer uses it to upgrade in place. OBS ignores it.

## Scene collection

`OBS-Forge` (16:9) and `OBS-Forge Vertical` (9:16) have four scenes - Starting Soon, Live,
BRB, Ending - each a dark background with a centred label. Live has a **Game Capture**
set to *Capture any fullscreen application*, fitted to the canvas, instead of a label.
Both collections include **Desktop Audio** and **Mic/Aux** on your default Windows
devices (0.1.0 had none, so the stream was silent until you added them).

Items are stored with OBS's canvas-relative coordinates, so the 16:9 collection lines up
on the 720p, 1080p and 1440p presets alike.

Nothing in the collection phones home, loads a URL, or references a local path.