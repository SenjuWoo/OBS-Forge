# Changelog

## 0.2.0 (2026-11-24)

New

- **Presets**: 1080p60, 1080p30, 720p60, 720p30, YouTube 1080p60, YouTube 1440p60,
  Record 1080p60, Record 1440p60 and Vertical 1080x1920, from one catalogue
  (`presets/presets.psd1`). Twitch and YouTube bitrates from their own guidelines.
- **Every GPU**: the installer asks OBS's own encoder probes and writes settings for
  NVIDIA NVENC, AMD AMF, Intel Quick Sync or x264. `-Encoder` forces a family.
- **Double-click install**: `Install.cmd` shows a menu; `Verify.cmd` and `Uninstall.cmd`
  next to it. `-List`, `-Preset`, `-Launch` (opens OBS on the profile without editing
  OBS's own config).
- **Ready to stream**: the Live scene has a Game Capture (any fullscreen app); both
  collections have Desktop Audio and Mic/Aux. New `OBS-Forge Vertical` collection.
- **Safe upgrades**: re-running the installer upgrades older OBS-Forge profiles in place
  and keeps your connected account, hotkeys and settings you changed. Each profile gets an
  `obs-forge.json` marker.

Fixed

- NVENC settings used the pre-OBS-31 keys `preset2` / `psycho_aq`, which the current
  `obs_nvenc_*` encoders ignore: the recording ran preset P5 instead of P4. Now `preset` /
  `adaptive_quantization`; proven by a real NVENC encode in OBS 33.0.2.
- The scene collection had no audio devices, so switching to it gave a silent stream.
- The Starting Soon / BRB / Ending labels sat in the top-left corner instead of the centre.
- `Verify.ps1` crashed once OBS rewrote `recordEncoder.json`, reported the first instead of
  the last canvas in the log, and passed silently when the record encoder file was missing.
- Docs claimed recordings split every 15 minutes; splitting was never enabled. Docs now say
  hybrid MP4 survives a crash and how to turn splitting on.
- `-Force` used to delete the whole profile, including your connected account.

Changed

- `Verify.ps1` checks every OBS-Forge profile, whether this PC has the encoder a profile
  uses, the OBS version, the collections' audio devices, and reports `warn` for drift.
- `Uninstall.ps1` finds profiles by marker, also removes the vertical collection,
  `-Preset` / `-KeepScenes`.
- CI runs the test suite under Windows PowerShell 5.1 and PowerShell 7, installs every
  preset, verifies, uninstalls and builds the release zip.

## 0.1.0 (2026-11-24)

- First release: `OBS-Forge 1080p60` and `OBS-Forge 1080p30` profiles, pinned to SDR 8-bit
  Rec.709 (NV12 / Partial) with an H.264 High stream encoder and a light HEVC Main
  recording encoder.
- Generic `OBS-Forge` scene collection: Starting Soon, Live, BRB, Ending.
- `Install.ps1` (backs up and replaces only its own files), `Verify.ps1` (read-only colour,
  encoder and log check), `Uninstall.ps1` (removes only its own files).
- Docs: settings table and the HDR/SDR explanation with the two NVENC errors.
