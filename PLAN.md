# PLAN · OBS-Forge 0.2.0 (audit + presets)

Audit baseline @ cf9f9e8: `Install.ps1 -ConfigRoot <temp>` exit=0, `Verify.ps1` exit=0 (Windows
PowerShell 5.1), CI `verify` green on main and v0.1.0. `pwsh` is not installed locally; CI runs
only `pwsh`. Ground truth for every OBS key below: OBS 33.0.2 source at tag `33.0.2`
(143d46f) and the installed OBS 33.0.2 binaries.

Ranked by cost to the operator: broken/untrue first, then fragile, then slow, then untidy.

| ID | Task | Status | Depends on | Verify | Evidence |
|---|---|---|---|---|---|
| F1 | NVENC encoder JSON uses legacy keys `preset2`/`psycho_aq`; OBS 31+ `obs_nvenc_*` reads `preset`/`adaptive_quantization` | complete | – | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); cmd:tests/Runtime-Smoke.ps1 -Preset 1080p60,youtube-1080p60,record-1440p60,vertical @ 1452263 exit=0 (OBS 33.0.2 log) - record ran preset p4, aq true |
| F2 | `Verify.ps1` crashes (null `.Substring`) once OBS rewrites `recordEncoder.json` | complete | – | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI) - verify catches drift without crashing |
| F3 | Scene collection has no Desktop Audio / Mic devices: switching to it gives a silent stream | complete | – | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); cmd:tests/Runtime-Smoke.ps1 -Preset 1080p60,youtube-1080p60,record-1440p60,vertical @ 1452263 exit=0 (OBS 33.0.2 log) - Desktop Audio + Mic/Aux loaded |
| F4 | "Centred label" is false: text items sit at the top-left corner | complete | – | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); real recorded frame: label centred (16:9 and 9:16) |
| F5 | Docs claim recordings split every 15 min; `RecSplitFile` is never enabled | complete | – | `file:docs/SETTINGS.md` | file:docs/SETTINGS.md + docs/PRESETS.md; killed hybrid MP4 playable (ffprobe hevc Main bt709) |
| F6 | `Verify.ps1` labels the *first* video reset in the log as "last canvas" | complete | F2 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI) - reports the last reset |
| F7 | `Verify.ps1` silently passes when `recordEncoder.json` is missing | complete | F2 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI) - missing record JSON fails |
| F8 | AMD / Intel / no-GPU users get NVENC encoders that do not exist on their PC; no capability probe | complete | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); this PC: obs-nvenc-test nvenc_supported=true -> NVENC |
| F9 | Release path incomplete: tag `v0.1.0` exists, no GitHub Release / zip; STATE "Next" is stale | complete | all | `cmd:gh release view v0.2.0` | cmd:gh release view v0.2.0 @ 2a0e6c5 (CI success on that SHA) - asset OBS-Forge-0.2.0.zip sha256 fd703e01c0eeec3df081f992a13614c236e9fdf09d9ee9504dc5172602a522f5, downloaded bytes match; install -Preset all + Verify from the downloaded zip exit=0 |
| F10 | CI runs only `pwsh`; users run Windows PowerShell 5.1. CI never tests uninstall/upgrade; checkout@v4 is two majors old | complete | T1 | `cmd:gh run list -L 1` | cmd:gh run view 45523148564 @ d86b95e conclusion=success (verify (powershell) + verify (pwsh): Tests PASS 711, install all, Verify PASS, uninstall clean, zip built) |
| F11 | Re-install skips silently; `-Force` deletes the whole profile incl. the user's `service.json` (connected account / key) | complete | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI) - upgrade from 0.1.0 keeps account, hotkeys, settings |
| F12 | No OBS version / install check; OBS 30 and older lack the `obs_nvenc_*` encoder IDs | complete | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); Verify prints ok OBS 33.0.2 |
| F13 | Profile names hard-coded in three scripts; adding a preset means editing all three | complete | P1 | `file:presets/presets.psd1` | file:presets/presets.psd1 @ 1452263 |
| F14 | New users must type a PowerShell command; no double-click launcher, no menu | complete | P2 | `file:Install.cmd` | cmd:Install.cmd / Verify.cmd / Uninstall.cmd from the 0.2.0 zip @ 1452263 exit=0 |
| P1 | Data-driven presets + encoder families (NVENC/AMF/QSV/x264) generated at install; marker file per profile | complete | – | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI) |
| P2 | Interactive menu installer, `-Preset/-Encoder/-List/-Launch`, `Install.cmd` | complete | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); -Menu with piped input exit=0 |
| P3 | New presets: 720p60, 720p30, YouTube 1080p60, YouTube 1440p60, Record 1080p60, Record 1440p60, Vertical 1080x1920 (+ vertical collection) | complete | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); cmd:tests/Runtime-Smoke.ps1 -Preset 1080p60,youtube-1080p60,record-1440p60,vertical @ 1452263 exit=0 (OBS 33.0.2 log) |
| P4 | Live scene ships a Game Capture (any fullscreen) so a new user only connects an account | complete | F3 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); cmd:tests/Runtime-Smoke.ps1 -Preset 1080p60,youtube-1080p60,record-1440p60,vertical @ 1452263 exit=0 (OBS 33.0.2 log) - game_capture loaded |
| T1 | `tests/Run-Tests.ps1` (no dependencies; 5.1 and 7) + `tests/Runtime-Smoke.ps1` (real OBS, real encode) | complete | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | cmd:powershell -File tests/Run-Tests.ps1 @ 1452263 exit=0 (707 assertions; 711 @ d86b95e on 5.1 and 7 in CI); cmd:tests/Runtime-Smoke.ps1 -Preset 1080p60,youtube-1080p60,record-1440p60,vertical @ 1452263 exit=0 (OBS 33.0.2 log) |
| D1 | README / SETTINGS / HDR / PRESETS docs, CHANGELOG, version 0.2.0, STATE | complete | all | `file:README.md` | file:README.md, docs/PRESETS.md, docs/SETTINGS.md, docs/HDR.md, CHANGELOG.md @ d86b95e |

## Decisions

Findings, with evidence:

- **F1** `profiles/*/streamEncoder.json:5,11`, `recordEncoder.json:5,11` write `preset2`, `psycho_aq`.
  OBS 33 `plugins/obs-nvenc/nvenc-properties.c:16,21` reads `preset` and `adaptive_quantization`;
  `nvenc-compat.c:20-23` maps `preset2`→`preset` only for the pre-31 `jim_*`/`ffmpeg_nvenc` IDs.
  The pack uses `obs_nvenc_h264_tex`/`obs_nvenc_hevc_tex`, so the record encoder runs the default
  P5, not the documented P4. Stream P5 and AQ on match the defaults by luck.
- **F2** `Verify.ps1:49` `$J.preset2.Substring(1)`. Reproduced: a `recordEncoder.json` without
  `preset2` → `You cannot call a method on a null-valued expression`, exit 1, no report.
- **F3** `frontend/widgets/OBSBasic_SceneCollections.cpp:1007-1012,1259-1264`: global audio
  devices load only from `DesktopAudioDevice1`/`AuxAudioDevice1` keys; `scenes/OBS-Forge.json`
  has neither.
- **F4** `scenes/OBS-Forge.json` text items `align: 5` (left|top), `pos 0,0`, `bounds_type 0`.
- **F5** `frontend/utility/AdvancedOutput.cpp:819-833`: split only when `AdvOut/RecSplitFile`
  is true; the pack never sets it (`RecSplitFileTime=15` is OBS's own default).
  Decision: keep splitting off (hybrid MP4 already survives a crash) and correct the docs.
- **F6** `Verify.ps1:69-71` `-match` returns the first hit.
- **F9** `gh release list` empty; `git tag` = `v0.1.0`.
- **F10** `.github/workflows/verify.yml` `shell: pwsh` only; `actions/checkout` latest is v7.0.1.
- **F11** `Install.ps1:57-63`.
- Encoder IDs and keys used by P1, all from OBS 33.0.2 source: NVENC `obs_nvenc_{h264,hevc,av1}_tex`
  (`rate_control` CBR/CQP/VBR/CQVBR, `preset` p1-p7, `tune`, `multipass`, `profile`, `bf`,
  `lookahead`, `adaptive_quantization`); AMF `h264_texture_amf`/`h265_texture_amf`
  (`rate_control`, `bitrate`, `cqp`, `keyint_sec`, `preset` quality/balanced/speed, `profile`, `bf`);
  QSV `obs_qsv11_v2`/`obs_qsv11_hevc` (`rate_control` CBR/VBR/CQP/ICQ, `target_usage` TU1-TU7,
  `cqp`, `profile`, `bframes`); x264 `obs_x264` (`rate_control` CBR/CRF, `preset`, `profile`, `crf`).
- Capability probe: OBS ships `obs-nvenc-test.exe`, `obs-amf-test.exe`, `obs-qsv-test.exe` in
  `bin\64bit`; their INI output is the same probe OBS itself uses. Fallback: GPU names from WMI.
- Not changed: SDR 8-bit design, profile names `OBS-Forge 1080p60`/`1080p30`, their bitrates,
  the scene collection name, the "never touch global.ini/user.ini" rule.
- Found during runtime proof: libobs unescapes `\\`, `\r`, `\n` in INI values
  (`libobs/util/config-file.c` `unescape`), so a raw `C:\...\rec` path breaks
  ("Recording stopped because of bad output path"). The installer passes existing values
  through unchanged and its template has no backslashes; the smoke test writes `/` paths.
- Text labels had `style: Bold` but `flags: 0` (not bold); now `flags: 1` (OBS_FONT_BOLD).
- Left as is: `text_gdiplus_v2` (OBS 33 still loads it; v3 only changes rendering defaults).

**Risks.** OBS rewrites `basic.ini` and the encoder JSON on UI changes, so a user can drift;
`Verify.ps1` reports it. AMF/QSV presets are generated from OBS source keys but cannot be
runtime-proven on this NVIDIA-only machine.

## 0.2.1 · presentation

| ID | Task | Status | Depends on | Verify | Evidence |
|---|---|---|---|---|---|
| V1 | Logo (SVG + 512 px PNG), 1280x640 social card | complete | – | `file:docs/presentation/logo.png` | rendered with Edge headless; checked at 64 px |
| V2 | Real OBS screenshots: main window, Output, Advanced settings; 16:9 hero | complete | – | `cmd:tools/Capture-Screenshots.ps1` | exit=0; values visible match the pack (NVENC CBR 6000/2 s/P5/bf 2, NV12/709/Limited/300) |
| V3 | README rewrite: hero, badges, gallery, troubleshooting | complete | V1,V2 | `cmd:python TOOLS/presentation_check.py . --kind tool` | Result: PASS |
| V4 | Release v0.2.1 so screenshots match the download (slate background) | pending | V3 | `cmd:gh release view v0.2.1` | - |
| V5 | Repo description, topics, homepage, social preview | pending | V1 | `cmd:gh repo view --json description,repositoryTopics` | - |

- `$PSScriptRoot` is empty in a param default under Windows PowerShell 5.1 (observed:
  `Split-Path` bound an empty string in `tools/Capture-Screenshots.ps1`); `Build-Release.ps1`
  had the same latent bug, hidden because CI always passed `-OutDir`.
- Qt ignores a UI Automation `Select` on the Settings page list; a posted WM_LBUTTONDOWN/UP
  at the item centre switches pages without moving the real mouse.