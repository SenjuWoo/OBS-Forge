# STATE · OBS-Forge

Updated 2026-11-24 · **0.1.0**

**Goal.** A fresh OBS install that streams well in one install step: SDR 8-bit Rec.709,
H.264 High, a light HEVC recording session, and a generic scene collection — with no
private scenes, overlays, keys or machine paths.

**Done.** Two profiles (`OBS-Forge 1080p60`, `OBS-Forge 1080p30`), the `OBS-Forge`
scene collection (Starting Soon, Live, BRB, Ending), `Install.ps1` / `Verify.ps1` /
`Uninstall.ps1`, `docs/SETTINGS.md`, `docs/HDR.md`, MIT licence, README.

**Validation.** `Install.ps1` into a clean config root wrote both profiles and the
collection and read back `60 fps, 6000 kbps, NV12/709/Partial` and `30 fps, 4500 kbps`.
OBS 33.0.2 in portable mode loaded the collection (4 scenes), 1920×1080@60, with no
`NVENC` / `Rec. 2100` errors in the log. `Verify.ps1` passed against that install
(including the log scan and the HDR display line). `Uninstall.ps1` removed only the
pack's files and left a timestamped backup.

**Next.** Publish the first tag after any README/CI tweak; add a GitHub Actions check that
runs `Verify.ps1` against a fixture config root if the repo grows.

**Build / run.** No build. `.\Install.ps1`, `.\Verify.ps1`, `.\Uninstall.ps1` from the
repo root; `-ConfigRoot <path>` targets a portable or custom OBS config folder.

**Recovery.** `Uninstall.ps1` removes the pack; the timestamped copy in `backups\` is the
rollback. The pack never touches other profiles or collections.