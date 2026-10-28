# Tally — auditor 5 — qc-gpu-collect-v1 (round 1)

Target: `collect-qc-gpu-win.ps1` (240 lines, reviewed in full).

## Votes

| Claim | Vote | Basis |
|-------|------|-------|
| C1 Standalone payload | ACCEPT | No top-level param block (only function-level `param([string]$Message)` at lines 22, 29, which is a function signature, not a CLI switch), no `$args`, no Read-Host/prompt anywhere; all identity/settings hardcoded (lines 11–19). `#Requires -Version 5.1` at line 9. |
| C2 Runtime | ACCEPT | All cmdlets used (Get-CimInstance, ConvertTo-Json, Out-File, Select-String, Get-WinEvent, Get-Service, Compress-Archive, Get-FileHash, Start-Transcript, …) are built into stock PS 5.1; external tools (pnputil, reg, driverquery, wevtutil, sc, dxdiag) are all inbox Windows binaries. Minor unverified point: `/ow:$true` value casing for wevtutil (see finding 5). |
| C3 Coverage | REJECT | Core coverage present (system S1, PnP S2, display S3, packages S5/S6, firmware S7, registry S8, services S9, events S10, setupapi S11, dxdiag S12, hashes/zip S13), BUT: `.ini` files and secondary INFs are never collected for any but the newest package (incidental full copy); the adjacent-family INF/CAT loop is a no-op (finding 1); firmware copy is non-recursive for older packages (finding 4); plausible miss of `QCOMxxx` ACPI keys (finding 6). |
| C4 Robustness | ACCEPT | Every section S1–S13 wrapped in try/catch with logging (lines 57, 66, 76, 87, 106, 119, 139, 168, 178, 193, 200, 216, 235); Save-CimJson has its own guard (lines 31–36); transcript started (line 45); zip failure retains raw folder (line 236); no empty catch blocks. |
| C5 Safety | ACCEPT | All writes confined to `C:\QC-GPU-Collect` (New-Item line 43, Copy-Item lines 113, 126–129, 135, 198, reg.exe export lines 146–165, wevtutil line 184, dxdiag `/t` line 205, Compress-Archive line 233, transcript line 45). No network, no credential access, no registry writes, no Remove-Item or destructive ops. |
| C6 Correctness | REJECT | The S7 adjacent-family loop behaves opposite to its intent (finding 1) — an actual collector misbehavior; plus INF-encoding assumption risk (finding 3) and smaller logic nits (findings 5, 7, 8). |

## Findings (independent, with line refs)

1. **S7 sibling loop is a no-op (C3/C6, main finding).** Lines 131–137: `Get-ChildItem -Path $FileRepo -Filter 'qcd*8380.inf_arm64_*'` matches FileRepository package *directories*, then `Where-Object { -not $_.PSIsContainer }` (line 133) excludes directories — nothing is ever copied. Section comment promises INF/CAT/INI of "ALL versions & adjacent families"; code delivers neither for siblings.
2. **.ini and secondary INFs never collected (C3).** No copy of `*.ini` or e.g. `qcdx8380umd.inf` anywhere; only S6's full copy of the single newest package could incidentally include them.
3. **INF encoding assumption (C6).** Line 97 `Select-String -Encoding Unicode`; if the DriverStore INF is ANSI, DriverVer parse fails → Version $null → S6 "newest" selection (line 110) may pick an arbitrary package. Unverified for the exact qcdx8380 INF.
4. **Firmware copy non-recursive (C3 minor).** Lines 126–127 copy `*.mbn` / `qcdxkmbase*.bin` from package root only; firmware in subdirs of older packages missed.
5. **wevtutil `/ow:$true` (C6 minor).** Line 184 expands to `/ow:True`; docs show lowercase `true|false`. Failure would be silent (`2>$null | Out-Null`) and drop the .evtx exports. Case-sensitivity unverified.
6. **ACPI enum filter may miss the GPU (C3 minor).** Line 154 `'^VEN_QCOM'`; ARM Adreno instances often enumerate as `QCOMxxxx`. Suggest `^(VEN_QCOM|QCOM)`. Low confidence, device-dependent.
7. **Zip vs. open transcript (C4/C6 minor).** Line 233 compresses while `transcript.log` is still open via Start-Transcript; PS 5.1 Compress-Archive can fail file-in-use → zip lost (logged, raw folder kept).
8. **Single bad version aborts S5 (C6 minor).** Line 99 `[version]` cast inside the `$pkgInfo` build; one malformed DriverVer aborts the whole try block and loses package-manifest.json for all packages.

Not bugs (checked and cleared): `$x.Count` on scalars in PS 5.1 is intrinsic; `Join-Path` leaf with `\` yields valid paths since `02-display` exists; `Test-Path ('Registry::' + $root)` correct; `null / 1MB` → 0; `Sort-Object Version -Descending` treats `$null` as smallest; `-in 'Display','Monitor','...'` valid; function-level `param()` compatible with the standalone rule; `#Requires` after comment header is valid.