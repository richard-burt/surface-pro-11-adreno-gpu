# tally_3 — qc-gpu-collect-v1 (round 1, auditor 3, blind)

Target: `collect-qc-gpu-win.ps1` (workspace root, 240 lines)

## Vote table

| Claim | Vote | Key evidence (lines) |
|-------|------|----------------------|
| C1 Standalone payload | ACCEPT | No `param()` block, no `$args`, no Read-Host/prompts; only function-level `param` at 22/29 (legit). All settings are hardcoded constants (11–19). Standalone rule honored. |
| C2 Runtime | ACCEPT | `#Requires -Version 5.1` at line 9. All cmdlets in-box: Get-CimInstance, Get-WinEvent, Get-Service, Compress-Archive (Microsoft.PowerShell.Archive, in-box 5.1), Get-FileHash, Start/Stop-Transcript, Select-String; `-in` (72) OK in 5.1. Externals reg.exe/pnputil.exe/driverquery.exe/wevtutil.exe/sc.exe/dxdiag.exe all ship with Windows. Native stderr redirect `2>$null` (184) OK in 5.1. |
| C3 Coverage | **REJECT** | Sibling-family collection dead code (131–137): filter `qcd*8380.inf_arm64_*` in FileRepository matches directories only, but line 133 excludes containers ⇒ 0 adjacent-family packages/INFs collected, contradicting claim ("driver packages + INF/CAT/INI", "adjacent families"). `.ini` files absent for non-active versions (S7 copies only .mbn/.bin/.inf/.cat, lines 126–129). Firmware non-recursive (126–127): nested .mbn/.bin missed. Everything else in the claim present: system S1, PnP S2, display/GPU S3, packages S5, active copy S6, registry S8 (services/class/ACPI/Qualcomm/DriverDatabase), services S9, event logs S10, setupapi S11, dxdiag S12, manifest/zip S13. |
| C4 Robustness | ACCEPT | All 13 sections (S1–S13) + Save-CimJson wrapped in try/catch that logs and continues (57, 66, 76, 87, 106, 119, 139, 168, 178, 193, 200, 216, 235–237); no empty catch. Transcript started (45) and stopped (240). Partial output preserved on every failure; size guard for full copy (18, 112). |
| C5 Safety | ACCEPT | All writes inside `C:\QC-GPU-Collect`: New-Item 43, Out-File/Add-Content targets under $Out, Copy-Item destinations 113/124–135/198 under $Out, zip 232–233 under $OutputRoot. reg.exe export (146/151/155/159/165), sc.exe qc (175), wevtutil epl (184), pnputil/driverquery (80–85) are read-only. No Remove-Item, no registry writes (only Get-* and reg EXPORT), no network cmdlets, no credential access, nothing destructive. |
| C6 Correctness | **REJECT** | The 131–137 `Where-Object { -not $_.PSIsContainer }` is a genuine no-op behavior bug (C3's main defect is a logic bug). Additional: line 97 Unicode-only INF parse ⇒ $null Version ⇒ arbitrary "newest" pick at 110 if parse fails (no fallback); Compress-Archive (233) can fail wholesale because transcript.log/collect.log are still being written; wevtutil/reg stderr swallowed so section logs 'OK' on silent failures (167, 184); line 55 Win32_UEFIEnvironmentVariable is not a stock root\cimv2 class (empty/‘null’ JSON, logged OK); dxdiag async start with no failure detection (205–215). Not bugs (checked and cleared): S6 `$pkgInfo` cross-section scope ($null-safe, 90 vs 110); Sort-Object over $null/[version]; Copy-Item into existing dirs lands as subfolder (113, 128, 198); single-item `.Count` intrinsic property (105); `[&\\]`/`[\\\s]` regex escapes (155, 159); checksums/versions CSVs written after $files enumeration so self-hashing excluded (220–231); dxdiag stability polling logic correct. |

## Findings (with refs)

1. **MAJOR** — `collect-qc-gpu-win.ps1:131-137`: sibling-family (`qcd*8380.inf_arm64_*`) collection collects nothing; `-not $_.PSIsContainer` excludes the driver-package directories the filter matches. Fix to `$_.PSIsContainer` (or add `-Directory` + per-package copy).
2. **Coverage** — `:126-129` + S7 comment ("INIs"): `.ini` never copied for non-active packages; only the active package full copy (S6, 113) would contain them.
3. **Coverage** — `:126-127`: firmware `.mbn`/`.bin` copied top-level only, non-recursive; `qcdxkmbase*` prefix may miss other `.bin`.
4. **Risk** — `:97` `-Encoding Unicode` assumption for DriverVer; ANSI/UTF-8 INF ⇒ $null Version ⇒ arbitrary copy target at `:110`.
5. **Risk** — `:233` Compress-Archive over still-open transcript.log/collect.log can fail the entire zip (PS 5.1 behavior); raw folder retained + logged, but final zip may vanish. Suggest Stop-Transcript before S13 or excluding logs.
6. **Minor** — `:184` (`2>$null`) and reg exports `:146,151,155,159,165` (no stderr capture/success check): silent export failures misreported by `:167` 'registry exports OK'.
7. **Minor** — `:55` `Win32_UEFIEnvironmentVariable` not a standard root\cimv2 class on stock Win11; SilentlyContinue masks it (empty JSON, 'OK' logged).
8. **Minor** — `:205-215` dxdiag failure undetectable; worst case 'dxdiag OK (0 bytes)' after 300 s.
9. **Minor** — No admin/elevation check; pnputil /enum-drivers, DriverStore reads, registry exports, System-log reads typically need elevation; silent partial output otherwise.

## Summary

4 ACCEPT (C1, C2, C4, C5) / 2 REJECT (C3, C6). Decisive defect: S7 adjacent-family collection is dead code (`-not $_.PSIsContainer` excludes the package directories), plus non-active-version `.ini` and nested firmware gaps under C3; Unicode-only INF version parsing, open-file zip risk, and swallowed reg/wevtutil errors under C6.