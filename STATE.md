# STATE · OBS-Forge

Updated 2026-11-24 · **0.2.1** (last known good: v0.2.0 until v0.2.1 is released green)

**Goal.** A fresh OBS install that streams or records well in one install step, on any
GPU: SDR 8-bit Rec.709, presets for Twitch/Kick/Rumble, YouTube, recording and vertical,
a ready scene collection - with no private scenes, overlays, keys or machine paths.

**Done.** 0.2.0: preset catalogue (9 presets) generated per encoder family (NVENC / AMF /
Quick Sync / x264) chosen by OBS's own probes; menu installer + `.cmd` launchers; in-place
upgrades that keep `service.json`, hotkeys and soft settings; marker files; Verify as a
doctor; vertical collection; Game Capture + audio devices in the collections; fixed NVENC
keys (F1), Verify crash (F2), silent collection (F3), label position (F4), split-file doc
claim (F5). See PLAN.md for every finding and its evidence.

**Validation.**
- `tests/Run-Tests.ps1`: 711 assertions PASS on Windows PowerShell 5.1 and PowerShell 7 (CI) (golden vs 0.1.0
  files, all presets x families, caps fallbacks, INI merge, collection geometry, clean
  install / re-run / -Force / encoder switch, all-presets x264, Verify drift cases,
  0.1.0 upgrade, foreign profile, uninstall).
- `tests/Runtime-Smoke.ps1` against the real OBS 33.0.2 (portable junction copy, NVIDIA Ada
  GPU): 1080p60, YouTube 1080p60, Record 1440p60, Vertical - record and stream encoders
  both started; OBS log shows exactly the JSON values (record P4/CQ22/HEVC Main, stream
  P5/H.264 High/CBR 6000, YouTube HEVC Main 12000, 1440p record with stream at 1920x1080,
  1080x1920 vertical), Desktop Audio and Mic/Aux loaded, 8 recordings written.
- Real recorded frames: labels centred in 16:9 and 9:16; a hybrid MP4 killed mid-record
  is playable (ffprobe: hevc Main yuv420p tv bt709, 3 AAC tracks).
- Not runtime-proven here (no such GPU): AMF and Quick Sync presets. Their keys come from
  OBS 33.0.2 source (texture-amf.cpp, obs-qsv11.c).

**NEXT ACTION.** 0.2.1 presentation release: push, CI green on the exact SHA, zip from that SHA, release v0.2.1 with hero image, set repo description/topics/social preview.

**Presentation.** Logo `docs/presentation/src/logo.svg`; images regenerate with `tools\Capture-Screenshots.ps1` (real OBS, portable junction copy) then `tools\Render-Presentation.ps1` (Edge headless). `presentation_check.py --kind tool`: PASS.

**Open items.** Field-test AMF / Quick Sync profiles on real hardware. Consider an
`-Activate` switch only if users ask (it would need writing OBS's `user.ini`, which the
ownership rules exclude).

**Build / run.** No build. `Install.cmd` / `.\Install.ps1 [-Menu|-List|-Preset ..|-Encoder ..]`,
`Verify.cmd`, `Uninstall.cmd`. Tests: `powershell -NoProfile -ExecutionPolicy Bypass -File
tests\Run-Tests.ps1`; runtime: `tests\Runtime-Smoke.ps1`. Release zip:
`tools\Build-Release.ps1 -Ref <sha>`.

**Logs.** `%LOCALAPPDATA%\OBS-Forge\logs\obs-forge.log` (installer); OBS's own logs in
`<config root>\logs`.

**Recovery.** `Uninstall.ps1` removes the pack; the timestamped copy in `backups\` (or
`%LOCALAPPDATA%\OBS-Forge\backups`) is the rollback. The pack never touches other
profiles or collections.
