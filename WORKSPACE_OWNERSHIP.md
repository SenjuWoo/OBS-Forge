# Workspace ownership

- Project: OBS-Forge — preconfigured OBS Studio profiles, a generic scene collection and
  install/verify scripts for a fresh OBS install.
- Project root: `.` (this file's directory; one owner shared by every agent).
- Active source: `.`. No snapshots; versions are Git tags.
- Repository: public GitHub `SenjuWoo/OBS-Forge`, MIT. Original work, no third-party code.
- Publication intent: public. Keep it free of personal data: no names, machine paths,
  stream keys, tokens, account IDs, private scenes or overlays.
- Read-only inputs: none at runtime. The pack writes only into the OBS configuration
  folder the operator points it at (`%APPDATA%\obs-studio` by default).
- Managed outside this folder (written by `Install.ps1` / `Uninstall.ps1`, always after a
  backup into `backups\`): `%APPDATA%\obs-studio\basic\profiles\OBS-Forge 1080p60`,
  `...\OBS-Forge 1080p30`, `...\basic\scenes\OBS-Forge.json`.
- Never modified: any other profile, any other scene collection, `global.ini`, `user.ini`.
- Secrets: none stored here, ever.
- Recovery: `Uninstall.ps1` restores nothing but removes only this pack's files; the
  timestamped copy in `backups\` is the rollback.