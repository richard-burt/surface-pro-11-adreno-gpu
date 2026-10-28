# Tally — auditor 2 — qc-gpu-collect-v1 (round 1)

Target: `collect-qc-gpu-win.ps1` (workspace root), read in full (L1–L240).

## Votes

| Claim | Verdict | Summary of evidence |
|-------|---------|---------------------|
| C1 Standalone payload | **ACCEPT** | No script-level param block, no CLP switches, no `$args`, no Read-Host/prompt. Only function-scope `param()` in Write-CollectLog (L22) and Save-CimJson (L29). All settings hardcoded: L11, L16, L17, L18, L19. No secrets handled. |
| C2 Runtime (PS 5.1 / Win11 ARM64) | **ACCEPT** | `#Requires -Version 5.1` (L9). Cmdlets all stock (Get-CimInstance, Get-WinEvent, Get-Service, Compress-Archive L233, Get-FileHash L221, Start-Transcript L45). Externals all Windows-shipped: reg.exe (L146+), pnputil.exe (L80, 82), driverquery.exe (L84), wevtutil.exe (L184), sc.exe (L175), dxdiag.exe (L205). `-in` operator (L72) is PS 3.0+. No PS7-only syntax. |
| C3 Coverage of "every aspect" | **REJECT** | Core aspects present (system S1, PnP S2, display S3, DriverStore S4–S6, registry S8 incl. DriverDatabase L162, services S9, events S10, setupapi S11, dxdiag S12, manifest/hash/zip S13), but: (1) sibling-family collection is a silent no-op (see finding F1); (2) `.ini` files never collected (only .mbn/.bin/.inf/.cat at L126–129); (3) DriverDatabase filter `^qcdx8380` (L163) skips sibling package keys; (4) firmware globs are single-level, missing .mbn/.bin in package subdirectories (L126–127). |
| C4 Robustness | **ACCEPT** | Per-section try/catch that logs and continues (S1–S13); no empty catch; transcript L45/L240; zip failure retains raw folder (L236). Weakness: SilentlyContinue + unconditional "OK" logs can mask empty results (e.g. L92, L126–129, L155) — acceptable for a partial-output collector. |
| C5 Safety | **ACCEPT** | All writes confined to C:\QC-GPU-Collect (tree + zip L232). No network cmdlets, no credential access, no registry writes (reg.exe export = read), no Remove-Item/deletion, no destructive ops. `Copy-Item -Force` is destination-only. |
| C6 Correctness | **REJECT** | Actual misbehavior found: sibling-filter no-op (L132–137), non-existent WMI class `Win32_UEFIEnvironmentVariable` (L55, real class is plural `Win32_UEFIEnvironmentVariables`), S5→S6 cross-section `$pkgInfo` dependency causing silent "no active package" on S5 partial failure (L110), PS 5.1 Compress-Archive large-archive risk (L233). Unicode INF read (L97) is itself correct for DriverStore UTF-16LE INFs. |

## Independent findings (numbered, cited)

- **F1 (C3/C6, L131–137 — key finding).** `$GfxSiblings = 'qcd*8380.inf_arm64_*'` collection can never copy anything: `Get-ChildItem -Filter $fam` at top-level FileRepository matches package *directories*, but `Where-Object { -not $_.PSIsContainer }` (L133) drops every directory. Nothing is copied; "S7 ... OK" is logged unconditionally (L138).
- **F2 (C3).** No `.ini` collection anywhere; "INF/CAT/INI" as claimed is unmet (INIs only reach output incidentally via the S6 whole-package copy of the newest version).
- **F3 (C6/C2, L80–85).** Native tools' failures don't throw; if pnputil/driverquery fail (elevation on some builds), the .txt is empty/partial yet S4 logs "OK". Same pattern elsewhere (wevtutil `2>$null` L184).
- **F4 (C3).** Firmware `*.mbn` / `qcdxkmbase*.bin` copied only from package roots; subdirectory blobs missed.
- **F5 (C6, L55).** `Win32_UEFIEnvironmentVariable` is not a real class (correct: `Win32_UEFIEnvironmentVariables`); SilentlyContinue hides the invalid-class error, S1 logs OK with empty output.
- **F6 (C6, L110).** S6 reads `$pkgInfo` produced inside S5's try; a mid-loop throw (e.g. bad `[version]` cast L99) leaves it `$null` → "no active package identified" instead of surfacing the real error.
- **F7 (C6, L233).** PS 5.1 Compress-Archive has documented large-archive failure modes (>2 GB); workload (up to 2000 MB package + full EVTX exports) can trip it — caught, raw folder retained, so partial-output requirement still holds.
- **F8 (C6, L187).** `-MaxEvents 3000` truncates before the client-side `Where-Object`; QC events older than the newest 3000 System events are unreachable — minor coverage note.
- **F9 (C6 positive check).** Unicode INF encoding (L97) correct for DriverStore INFs; DriverVer regex and 4-segment `[version]` cast sound; `MatchInfo.Matches` usage sound.

Standing rule honored: no other tally files read.

**Votes: C1 ACCEPT, C2 ACCEPT, C3 REJECT, C4 ACCEPT, C5 ACCEPT, C6 REJECT.**