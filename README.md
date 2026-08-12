# AUTO-UPDATES (Black Corps Loader)

This repo feeds the loader **CHECK FOR UPDATES** button.

Loader reads:
```
https://raw.githubusercontent.com/justinkhakhyuu/AUTO-UPDATES/main/updates/manifest.json
```

---

## Folder map (what goes where)

```
AUTO-UPDATES/
├── updates/
│   └── manifest.json          ← IN GIT (loader fetches this from main)
│
├── release-assets/            ← LOCAL ONLY (not committed — see .gitignore)
│   ├── brutal-1.0.0/
│   │   ├── Client.dll                    ← YOU replace / drop here
│   │   └── libTERMINALX999Cheats.so      ← YOU replace / drop here
│   └── lite-1.0.0/
│       └── Client.dll                    ← YOU replace / drop here
│
└── Scripts/
    └── Update-ManifestHashes.ps1         ← fills sha256 in manifest after build
```

**GitHub Releases** (website UI) — binaries live here, NOT in the repo tree:

| Tag | Upload these assets |
|-----|---------------------|
| `brutal-1.0.0` | `Client.dll`, `libTERMINALX999Cheats.so` |
| `lite-1.0.0` | `Client.dll` only |

---

## First-time setup

1. Build your internals (brutal + lite).
2. Copy files into `release-assets/<tag>/` folders (see `DROP_FILES_HERE.txt` in each).
3. GitHub → **Releases** → **Create a new release**:
   - Tag: `brutal-1.0.0` → upload brutal files
   - Tag: `lite-1.0.0` → upload lite `Client.dll`
4. Run:
   ```powershell
   cd "d:\FREE FIRE PROJECTS\DEV\AUTO-UPDATES"
   .\Scripts\Update-ManifestHashes.ps1 -Channel brutal -Version 1.0.0
   .\Scripts\Update-ManifestHashes.ps1 -Channel lite -Version 1.0.0
   ```
5. Commit + push `updates/manifest.json` to `main`.

---

## Publishing a new version (example brutal 1.0.1)

1. Drop new files in `release-assets/brutal-1.0.1/`
2. Create GitHub release tag `brutal-1.0.1` and upload assets
3. `.\Scripts\Update-ManifestHashes.ps1 -Channel brutal -Version 1.0.1`
4. Push manifest.json

Only change the channel you updated. Lite and brutal are independent.

---

## Where loader installs files

| Channel | Downloaded to (next to loader exe) |
|---------|-------------------------------------|
| brutal | `internal/brutal/Client.dll` |
| brutal | `internal/brutal/Libraries/libTERMINALX999Cheats.so` |
| lite | `internal/lite/Client.dll` |

Static (never OTA): `cimgui.dll`, `AotBst.dll`, `libinjectEmulator.so`

---

## Private repo

Set on the PC running the loader:
```
BLACK_CORPS_GITHUB_TOKEN=ghp_xxxxxxxx
```
