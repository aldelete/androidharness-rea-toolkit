# rea-android-toolkit

Offline toolkit that makes REA's Ghidra / JADX / decompiler stack run on **Android arm64**
inside the app's Linux container. One download, no root, no Termux required.

## What it contains
| Component | Purpose |
|---|---|
| Ghidra 12.2 (full) | analysis engine |
| `decompile` arm64 bionic build | the binary Ghidra upstream does not ship for Android |
| OpenJDK 25 (bionic) | runtime for Ghidra |
| jadx-headless-mcp 0.7.1 | Java/Kotlin decompilation MCP |
| Node 26.13 + npm | runtime for REA, bundled so nothing is fetched |
| `rea-agents-6.9.0.tgz` | pinned official npm tarball |
| `rea-patch/` | Android-compatible `dist` + container env defaults |

## Install (inside the app)
The app downloads `rea-toolkit-<version>.tar.gz`, verifies its SHA-256, extracts it with
GNU tar and runs `toolkit/install.sh` with `PREFIX` set to its own files dir. Every
build-time path is stored as `@PREFIX@`, so any application id works.

Manual run:
```bash
PREFIX=/data/user/0/<your.id>/files/linux bash toolkit/install.sh
PREFIX=/data/user/0/<your.id>/files/linux bash toolkit/verify.sh
```

## Notes
- The installer is idempotent and creates `*.orig` backups before touching REA files.
- `bin/ps` becomes a toybox shim; the original is kept as `bin/ps.procps`.
- Verify with `sha256sum rea-toolkit-1.0.0.tar.gz` against `SHA256SUMS`.
