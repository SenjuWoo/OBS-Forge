# OBS-Forge

Ready-made OBS Studio setups for streaming and recording. Pick what you want - Twitch,
YouTube, recording, vertical - and the installer writes OBS profiles tuned for the
encoder your PC actually has, plus a scene collection that already captures your game,
your desktop audio and your mic. Connect your account and go live.

Every profile is **SDR 8-bit Rec.709** (NV12 / Partial range), which is what Twitch, Kick,
Rumble and YouTube ingest, so there are no washed-out colours and no HDR encoder errors.

## Install (2 minutes)

1. Install **OBS Studio 31 or newer** (33 is tested) and update your graphics driver.
2. **Close OBS.**
3. Download the latest `OBS-Forge-<version>.zip` from
   [Releases](https://github.com/SenjuWoo/OBS-Forge/releases), unzip it anywhere.
4. Double-click **`Install.cmd`**, type the numbers of the presets you want (or just press
   Enter for the recommended 1080p60 + 1080p30), press Enter again to use the detected
   encoder.
5. Let it open OBS, or open it yourself. If the Auto-Configuration Wizard pops up on
   OBS's very first start, **Cancel** it - it would overwrite these settings.
6. **Settings → Stream** → pick your service → **Connect Account** (or paste your key).
7. Start your game in fullscreen - the **Live** scene captures it - and hit
   **Start Streaming**.

To switch later: **Profile** menu (resolution / bitrate / encoder) and **Scene
Collection** menu (`OBS-Forge`, or `OBS-Forge Vertical` for 9:16).

## Presets

| Preset | Profile in OBS | Canvas | FPS | Stream | For |
|---|---|---|---|---|---|
| `1080p60` ★ | OBS-Forge 1080p60 | 1920×1080 | 60 | 6000 kbps H.264 | Twitch / Kick / Rumble |
| `1080p30` ★ | OBS-Forge 1080p30 | 1920×1080 | 30 | 4500 kbps H.264 | slower upload or 30 fps games |
| `720p60` | OBS-Forge 720p60 | 1280×720 | 60 | 4500 kbps H.264 | smooth motion on a slower line |
| `720p30` | OBS-Forge 720p30 | 1280×720 | 30 | 3000 kbps H.264 | weak PC or slow upload |
| `youtube-1080p60` | OBS-Forge YouTube 1080p60 | 1920×1080 | 60 | 12 Mbps HEVC | YouTube Live |
| `youtube-1440p60` | OBS-Forge YouTube 1440p60 | 2560×1440 | 60 | 24 Mbps HEVC | YouTube Live at 1440p |
| `record-1080p60` | OBS-Forge Record 1080p60 | 1920×1080 | 60 | – | high-quality recordings |
| `record-1440p60` | OBS-Forge Record 1440p60 | 2560×1440 | 60 | (1080p if you stream) | high-quality 1440p recordings |
| `vertical` | OBS-Forge Vertical 1080x1920 | 1080×1920 | 30 | 6000 kbps H.264 | TikTok / Shorts / vertical live |

★ = installed when you choose nothing. Details, bitrate sources and upload needs:
[docs/PRESETS.md](docs/PRESETS.md).

**Encoders.** The installer runs the same encoder probes OBS uses and picks NVIDIA NVENC,
then AMD AMF, then Intel Quick Sync, then x264 on the CPU. Each preset gets settings for
that encoder; HEVC presets fall back to H.264 (at YouTube's H.264 bitrate) where HEVC is not
available. Streaming and recording use separate hardware encoders, so recording costs
almost nothing while you play.

## Command line

```powershell
.\Install.ps1                                   # recommended presets, auto encoder
.\Install.ps1 -Menu                             # the menu Install.cmd shows
.\Install.ps1 -List                             # presets + the encoder this PC would use
.\Install.ps1 -Preset 720p60,youtube-1080p60    # pick presets
.\Install.ps1 -Preset all -Encoder amf          # force an encoder family
.\Install.ps1 -Launch                           # open OBS on the first preset afterwards
.\Install.ps1 -ConfigRoot 'D:\OBS\config\obs-studio'   # portable OBS
```

From a plain PowerShell window prefix with
`powershell -ExecutionPolicy Bypass -File`; the `.cmd` launchers do that for you.

## What the installer touches

- Writes only `basic\profiles\OBS-Forge *` and `basic\scenes\OBS-Forge*.json` inside the
  OBS config folder (`%APPDATA%\obs-studio` by default). Never another profile, another
  collection, `global.ini` or `user.ini`.
- Backs up anything it changes into `backups\` next to the scripts (or
  `%LOCALAPPDATA%\OBS-Forge\backups` if that folder is read-only). Backups can contain
  your stream key - keep them private.
- **Upgrading** (run the new installer over an old install) keeps your connected account
  (`service.json`), hotkeys, audio devices and other settings you changed; it re-applies
  the video and encoder settings. Your scene collection is never replaced unless you pass
  `-Force` (an old collection only gets its missing Desktop Audio / Mic added).

## Check it

Double-click **`Verify.cmd`** (or `.\Verify.ps1`). Read-only. It checks every OBS-Forge
profile (colour format, canvas, encoder settings, whether this PC really has that
encoder), the scene collections' audio devices, and the newest OBS log for encoder and
HDR errors. `ok` = fine, `warn` = changed in OBS or worth knowing, `FAIL` = will break the
stream. Exit code 0 means pass.

## Why SDR and not HDR

The stream chain is SDR: Twitch, Kick and Rumble ingest 8-bit H.264, and YouTube only
takes HDR as a separate HEVC Main10 encode. An HDR canvas under an 8-bit encoder fails with
`Cannot perform 10-bit encode on this encoder`. Windows HDR can stay on; OBS tone-maps an
HDR game down to the SDR canvas. Full story: [docs/HDR.md](docs/HDR.md). Every key the
pack writes: [docs/SETTINGS.md](docs/SETTINGS.md).

## What is not in here

No overlays, alerts, chat widgets, channel art, stream keys or account tokens. The scene
collection is a plain starting point (Starting Soon, Live, BRB, Ending) to restyle.

## Uninstall

Double-click **`Uninstall.cmd`** (or `.\Uninstall.ps1`). Removes only OBS-Forge profiles
and collections, after a backup. `-Preset <id>` removes one profile, `-KeepScenes` keeps
the collections.

## Requirements

- Windows 10/11, OBS Studio 31+ (33 tested), Windows PowerShell 5.1 (built in) or
  PowerShell 7.
- A GPU with a hardware video encoder (NVIDIA NVENC, AMD AMF, Intel Quick Sync) for the
  hardware presets - the installer asks OBS's own probes which one you have. Without one,
  the presets use x264 on the CPU.
- Upload speed: see the preset table in [docs/PRESETS.md](docs/PRESETS.md).

## License

MIT. See [LICENSE](LICENSE).
