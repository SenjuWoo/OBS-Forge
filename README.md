# OBS-Forge

Preconfigured OBS Studio settings for a fresh install. Pick a profile, connect your
account, add your game, go live. No overlays to wire, no colour roulette, no HDR
surprises.

The profiles are pinned to **SDR 8-bit Rec.709** with an **8-bit H.264** stream
encoder, which is what Twitch, Kick and Rumble actually ingest. Recording is a light
second NVENC session so it does not eat the GPU your game wants.

## What you get

| Profile | Canvas / output | FPS | Video bitrate | Use it when |
|---|---|---|---|---|
| `OBS-Forge 1080p60` | 1920×1080 | 60 | 6000 kbps | You have a 1080p60-capable PC and upload |
| `OBS-Forge 1080p30` | 1920×1080 | 30 | 4500 kbps | Slower upload, older GPU, or a 30 fps game |

Both ship with:

- **Video:** NV12 / Rec.709 / Partial range, SDR white level 300.
- **Stream:** NVIDIA NVENC H.264 High, CBR, 2 s keyframes, 2 B-frames, look-ahead off,
  adaptive quantization on, dynamic bitrate on, AAC 160 kbps.
- **Recording:** NVENC HEVC Main (8-bit), CQ 22, P4, no B-frames, hybrid MP4, replay
  buffer 60 s.
- **Scenes:** a generic `OBS-Forge` collection with Starting Soon, Live, BRB and Ending.

## Install

1. Install **OBS Studio 33 or newer** and a current NVIDIA driver.
2. **Close OBS.**
3. In PowerShell, from this folder:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install.ps1
   ```

4. Open OBS → **Profile** menu → `OBS-Forge 1080p60` (or `1080p30`).
5. **Settings → Stream** → pick your service → **Connect Account**.
6. Add your game capture to the **Live** scene, then **Start Streaming**.

The installer writes only inside `%APPDATA%\obs-studio`, backs up anything it replaces
into `backups\`, and never touches profiles or collections it does not own.

Portable OBS or a custom config folder:

```powershell
.\Install.ps1 -ConfigRoot 'D:\Portable\obs-studio'
```

## Verify

```powershell
.\Verify.ps1
```

Read-only. It checks that both profiles are `NV12 / 709 / Partial`, that the encoders
are H.264 High and HEVC Main, and that the newest OBS log has no
`does not support 8-bit output of Rec. 2100` / `Cannot perform 10-bit encode` errors.
Exit code 0 means pass.

## Why SDR and not HDR

Short version: **the stream chain is SDR**. Twitch, Kick and Rumble ingest H.264 8-bit;
YouTube is the only destination that takes HDR, and only as a second HEVC Main10 encode
at 9–12 Mbps. An HDR canvas under an 8-bit stream encoder does not start — that is the
`Cannot perform 10-bit encode on this encoder` error. Windows HDR can stay on; OBS
tone-maps an HDR source down to the SDR canvas.

Full explanation, including the exact log lines and what each knob does:
[docs/HDR.md](docs/HDR.md) and [docs/SETTINGS.md](docs/SETTINGS.md).

## What is not in here

No overlays, alerts, chat box, channel art, stream keys, account tokens or personal
scenes. Those are private to the author's channel. This pack is the settings layer only.

## Requirements

- Windows 10/11, OBS Studio 33+.
- NVIDIA GPU for the included NVENC presets. On AMD or Intel, switch
  **Settings → Output → Encoder** to your hardware encoder (or `x264`); the colour and
  scene settings stay valid.
- 6000 kbps upload for the 60 fps profile, 4500 kbps for the 30 fps one.

## Uninstall

```powershell
.\Uninstall.ps1
```

Removes only the two `OBS-Forge` profiles and the `OBS-Forge` scene collection, after a
backup. Your own profiles are untouched.

## License

MIT. See [LICENSE](LICENSE).