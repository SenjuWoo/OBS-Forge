# PLAN · OBS-Forge 0.1.0

| ID | Task | Status | Depends on | Verify | Evidence |
|---|---|---|---|---|---|
| P1 | Profile pair (1080p60 / 1080p30), SDR 8-bit Rec.709, NVENC H.264 + light HEVC | complete | – | `file:profiles/OBS-Forge 1080p60/basic.ini` | `ColorFormat=NV12`, `ColorSpace=709`, `ColorRange=Partial` |
| P2 | Generic scene collection (4 scenes, no branding, no URLs) | complete | P1 | `file:scenes/OBS-Forge.json` | loaded in OBS 33.0.2: Starting Soon, Live, BRB, Ending |
| P3 | `Install.ps1` with backup + readback, `-ConfigRoot`, `-Force` | complete | P1,P2 | `cmd:powershell -File Install.ps1 -ConfigRoot <temp>` | exit=0, 6 files written, readback 60/6000 and 30/4500 |
| P4 | `Verify.ps1` colour/encoder/log check | complete | P1 | `cmd:powershell -File Verify.ps1 -ConfigRoot <temp>` | exit=0, 9 ok lines incl. `last canvas NV12 / Rec. 709/Partial` |
| P5 | `Uninstall.ps1` removes only pack files, backs up | complete | P3 | `cmd:powershell -File Uninstall.ps1 -ConfigRoot <temp> -Force` | exit=0, backup written, only pack files removed |
| P6 | Public docs: README, SETTINGS, HDR, CHANGELOG, LICENSE, ownership | complete | P1–P5 | `file:README.md` | MIT, no personal data |
| P7 | Publish public GitHub repo and push | complete | P6 | `cmd:git log -1 --format=%h` | tag `v0.1.0` |

**Decisions.** SDR 8-bit only (the stream chain is SDR; the two NVENC errors come from an
HDR canvas under the 8-bit encoder). NVENC by default, with a documented switch for
AMD/Intel. No overlays/alerts/chat: those are private to the author's channel.

**Risks.** OBS rewrites `basic.ini` on UI changes, so a user can drift; `Verify.ps1`
detects it. A future OBS version may rename keys; the verifier fails loudly instead of
guessing.