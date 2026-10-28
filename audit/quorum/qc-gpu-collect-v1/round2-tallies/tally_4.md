# tally_4.md — auditor 4, round 2 (qc-gpu-collect-v1)

## Vote table

| Claim | Vote |
|-------|------|
| C3 — Coverage | **ACCEPT** |
| C6 — Correctness (PS 5.1 logic) | **ACCEPT** |

## C3 — Coverage: ACCEPT

Evidence: audited the fixed bytes of `collect-qc-gpu-win.ps1` AND cross-checked
against the live driver store (`/run/media/richard/Local Disk/Windows/.../FileRepository`,
mounted read-only) — strongest possible coverage proof.

- **Full copy of newest package with 2000 MB guard** (lines 18, 119–127):
  newest-by-`[version]` package copied with `Copy-Item -Recurse` into
  `06-driverstore-active` only if `SizeMB -le 2000`. On-disk newest
  31.0.152.1 ≈ 493 MB → passes guard. ✔
- **Firmware + INF/CAT/INI of ALL qcdx versions → 07-firmware** (S7, 132–139):
  verified newest package contents on disk:
  - 7× `.mbn` (qcav1e8380, qcdxkmsuc8380, qcdxkmsucpurwa, qcvss8380,
    qcvss8380_pa) all matched by `*.mbn`; ✔
  - all 9 `.bin` present on disk match `qcdxkmbase*.bin` exactly
    (base, _63, _68, _110, _150, _pa, _pa_67, _pa_111, _pa_140); ✔
  - only `qcdx8380.inf` + `qcdx8380.cat` exist → explicit copies cover 100%. ✔
  - firmware files are top-level in the package dir (no nested .mbn/.bin),
    so wildcard `Copy-Item` matches them regardless of `-Recurse` nuance. ✔
- **Sibling .ini registry templates → 03-driver-packages-infs** (141–143):
  round-1 no-op CONFIRMED FIXED. FileRepository root contains exactly 6 loose
  FILES matching `qcd*8380.inf_arm64_*` — `qcdx8380.inf_arm64_<hash>.ini` ×5
  + `qcdpps8380.inf_arm64_602d28951530038a.ini`; `-Filter` glob + `-File`
  selects exactly these, excludes the package directories. ✔
- **Registry / services / event logs / setupapi / dxdiag / hashes / zip**:
  S8 (services, display class {4d36e968…}, ACPI enum VEN_QCOM, Qualcomm
  software, DriverDatabase qcdx8380), S9 (Get-Service + `sc.exe qc`),
  S10 (wevtutil epl + 30-day QC-filtered events), S11 (setupapi.dev*.log),
  S12 (dxdiag /t + stable-size polling), S13 (SHA256 checksums.csv,
  file-versions.csv, zip). ✔

## C6 — Correctness: ACCEPT

- `[version]` cast in try/catch, `$ver = $null` fallback (line 107); does not
  void S5/S6 (S5 logs failure, S6 handles nulls). ✔
- `$pkgInfo = @()` initialised before S5 (line 96) — S6 degrades to logged
  "no active package" instead of throwing. ✔
- wevtutil `$LASTEXITCODE` checked per channel (193–196); no `/ow`; grep shows
  zero `2>$null` in the file. ✔
- `Stop-Transcript` (243) before `Compress-Archive` (245); S13 catch retries
  `Stop-Transcript` in its own guarded try (249); no empty catch blocks
  (17 catch sites, all contain statements or a guard). ✔
- Elevation detection present and non-fatal (47–52). ✔
- No script `param` block (only the two helper-function param blocks), no CLI
  flags, no Read-Host/interactivity; settings hardcoded (lines 11–19). ✔

## Findings (minor, non-blocking)

- **F1**: S8 `reg.exe` exports don't check `$LASTEXITCODE`; non-elevated run
  silently omits DriverDatabase/display-class .reg files (only the elevation
  log line hints why). Suggest per-export exit-code logging in a future round.
- **F2**: `Sort-Object Version -Descending` (119): a newest package with an
  unparseable DriverVer would sort below an older parsed one and S6 would copy
  the wrong package. Mitigated: verified actual INF parses — `DriverVer =
  05/23/2026,31.0.152.1` matches the regex, UTF-16LE + `-Encoding Unicode` OK.
- **F3**: `qcd*8380` doesn't match `qca*` families (qcadc/qcadcm/qcadsprpc
  .ini, camera/DSP — not graphics); qcdpps8380 (display-adjacent) IS matched.
  Scope by-design, noted.

## File bytes audited

- Target: `/home/richard/Documents/projects/this-installed-ubuntu/gpu/collect-qc-gpu-win.ps1`
  (252 lines as read this round)
- Independent, blind; other tallies / verdict records NOT read.