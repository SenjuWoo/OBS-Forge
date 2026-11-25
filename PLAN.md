# PLAN · OBS-Forge 0.2.0 (audit + presets)

Audit baseline @ cf9f9e8: `Install.ps1 -ConfigRoot <temp>` exit=0, `Verify.ps1` exit=0 (Windows
PowerShell 5.1), CI `verify` green on main and v0.1.0. `pwsh` is not installed locally; CI runs
only `pwsh`. Ground truth for every OBS key below: OBS 33.0.2 source at tag `33.0.2`
(143d46f) and the installed OBS 33.0.2 binaries.

Ranked by cost to the operator: broken/untrue first, then fragile, then slow, then untidy.

| ID | Task | Status | Depends on | Verify | Evidence |
|---|---|---|---|---|---|
| F1 | NVENC encoder JSON uses legacy keys `preset2`/`psycho_aq`; OBS 31+ `obs_nvenc_*` reads `preset`/`adaptive_quantization` | pending | – | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F2 | `Verify.ps1` crashes (null `.Substring`) once OBS rewrites `recordEncoder.json` | pending | – | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F3 | Scene collection has no Desktop Audio / Mic devices: switching to it gives a silent stream | pending | – | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F4 | "Centred label" is false: text items sit at the top-left corner | pending | – | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F5 | Docs claim recordings split every 15 min; `RecSplitFile` is never enabled | pending | – | `file:docs/SETTINGS.md` | - |
| F6 | `Verify.ps1` labels the *first* video reset in the log as "last canvas" | pending | F2 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F7 | `Verify.ps1` silently passes when `recordEncoder.json` is missing | pending | F2 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F8 | AMD / Intel / no-GPU users get NVENC encoders that do not exist on their PC; no capability probe | pending | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F9 | Release path incomplete: tag `v0.1.0` exists, no GitHub Release / zip; STATE "Next" is stale | pending | all | `cmd:gh release view v0.2.0` | - |
| F10 | CI runs only `pwsh`; users run Windows PowerShell 5.1. CI never tests uninstall/upgrade; checkout@v4 is two majors old | pending | T1 | `cmd:gh run list -L 1` | - |
| F11 | Re-install skips silently; `-Force` deletes the whole profile incl. the user's `service.json` (connected account / key) | pending | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F12 | No OBS version / install check; OBS 30 and older lack the `obs_nvenc_*` encoder IDs | pending | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| F13 | Profile names hard-coded in three scripts; adding a preset means editing all three | pending | P1 | `file:presets/presets.psd1` | - |
| F14 | New users must type a PowerShell command; no double-click launcher, no menu | pending | P2 | `file:Install.cmd` | - |
| P1 | Data-driven presets + encoder families (NVENC/AMF/QSV/x264) generated at install; marker file per profile | pending | – | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| P2 | Interactive menu installer, `-Preset/-Encoder/-List/-Launch`, `Install.cmd` | pending | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| P3 | New presets: 720p60, 720p30, YouTube 1080p60, YouTube 1440p60, Record 1080p60, Record 1440p60, Vertical 1080x1920 (+ vertical collection) | pending | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| P4 | Live scene ships a Game Capture (any fullscreen) so a new user only connects an account | pending | F3 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| T1 | `tests/Run-Tests.ps1` (no dependencies; 5.1 and 7) + `tests/Runtime-Smoke.ps1` (real OBS, real encode) | pending | P1 | `cmd:powershell -File tests/Run-Tests.ps1` | - |
| D1 | README / SETTINGS / HDR / PRESETS docs, CHANGELOG, version 0.2.0, STATE | pending | all | `file:README.md` | - |

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
- Left as is: `text_gdiplus_v2` (OBS 33 still loads it; v3 only changes rendering defaults).

**Risks.** OBS rewrites `basic.ini` and the encoder JSON on UI changes, so a user can drift;
`Verify.ps1` reports it. AMF/QSV presets are generated from OBS source keys but cannot be
runtime-proven on this NVIDIA-only machine.
