# Tally — auditor 1 — qc-gpu-collect-v1 (round 1)

Target: `collect-qc-gpu-win.ps1` (workspace root). Blind review, no other tallies read.

## Votes

| Claim | Vote | Evidence |
|---|---|---|
| C1 Standalone payload | **ACCEPT** | No script-level param block, no `$args`/CLI switch reads, no Read-Host/prompt anywhere. Function `param()`s at lines 22, 29 are internal, not CLI. Identity/settings hardcoded at lines 11-19, 16-17. |
| C2 Runtime | **ACCEPT** | `#Requires -Version 5.1` line 9. Only CIM cmdlets, Get-WinEvent, Get-Service, Compress-Archive, Get-FileHash, Start-Transcript, built-ins; externals reg.exe/pnputil.exe/driverquery.exe/wevtutil.exe/sc.exe/dxdiag.exe all ship with Windows. Verified: `Select-String -Encoding Unicode` (line 97) **is** valid in PS 5.1 (5.1 docs list `-Encoding` with `unicode` value). |
| C3 Coverage of "every aspect" | **REJECT** | Most elements present: system (S1), PnP (S2), display (S3), packages/INF/CAT (S5/S7), full newest copy (S6), firmware all versions (S7), registry services/display-class/ACPI-enum/Qualcomm/DriverDatabase (S8), services (S9), events (S10), setupapi (S11), dxdiag (S12), manifests+zip (S13). BUT: the sibling-family INF collection (lines 131-137) is a dead no-op — FileRepository contains only directories, and the `-not $_.PSIsContainer` filter discards them, so no adjacent `qcd*8380.inf` package is ever copied. No `.ini` collection for non-active versions (only `.mbn`, `.bin`, `.inf`, `.cat`, lines 126-129). Adjacent Qualcomm services missed by `^qcdx|^qcgpu` filters (lines 143-144, 172). |
| C4 Robustness | **ACCEPT** | Per-section try/catch S1-S13, every catch logs via Write-CollectLog, no empty catch; transcript lines 45/240; partial output retained (S13 catch even says "raw folder retained"). Caveats logged as findings: native exit codes never checked so tool failures log as "OK"; wevtutil System/Application export requires elevation and stderr is 2>$null-suppressed (line 184). |
| C5 Safety | **ACCEPT** | All writes confined to `C:\QC-GPU-Collect` (lines 11, 43, 232): logs, exports, Copy-Item dests, dxdiag /t target, zip. No network calls, no credential access (transcript contains no secrets), reg.exe export/add-content/Out-File only read HKLM, no deletes, no destructives; -Force only overwrites inside the output tree. |
| C6 Correctness | **REJECT** | (1) Lines 131-137 sibling loop is actual misbehavior — silently copies nothing (see C3). (2) Line 99 `[version]` cast kills the whole S5 manifest/S6 selection if DriverVer has >4 dotted segments (Qualcomm uses 5-part versions like 31.0.83.x.yyyy; try/catch scope is the entire section). Verified non-bugs: `-Encoding Unicode` on Select-String is fine in 5.1; `@($Data).Count` line 33 fine (PS 3+ intrinsic Count); `$pkgInfo` undefined after S5 failure is guarded at S6 line 111; `Join-Path $Out '*'` zip path excludes itself (zip is in parent). Minor: `/ow:$true` expands to `/ow:True` (docs say lowercase true); dxdiag stability break (line 211) can fire mid-write; PS 5.1 UTF8 BOM / Export-Csv ASCII encoding interop; manifests don't self-hash (line 220 snapshot taken before CSVs written). |

## Findings (with line refs)

1. **BLOCKER** — lines 131-137: sibling INF-family collection is a no-op; `-not $_.PSIsContainer` excludes the directories that `-Filter 'qcd*8380.inf_arm64_*'` matches in FileRepository, so `03-driver-packages-infs` gets nothing from it.
2. lines 126-129: no `.ini` capture for all versions (only inside the newest-package full copy, if at all).
3. line 99: `[version]` cast is fragile (5-segment Qualcomm DriverVer throws) and S5 has no per-package fault isolation → whole manifest lost.
4. lines 80-85, 146-175, 184: native exit codes unchecked → sections log "OK" regardless of tool failure.
5. line 184: `System`/`Application` EVTX export silently fails without elevation (no admin check, stderr suppressed).
6. lines 143-144, 172: `^qcdx|^qcgpu` filters miss adjacent Qualcomm services (qcsubsys etc.).
7. line 184: `/ow:$true` → `/ow:True`; use lowercase `true`.
8. lines 32, 223: PS 5.1 UTF8-BOM JSON / ASCII CSV interop nit; line 220-223: checksums.csv/file-versions.csv not self-hashed; transcript.log hash may be skipped if file locked.
9. lines 207-214: dxdiag done-detection can break mid-write if stalled 5 s at a stable nonzero size.

## Summary

C1 ACCEPT, C2 ACCEPT, C3 REJECT, C4 ACCEPT, C5 ACCEPT, C6 REJECT — blocker: sibling INF-collection loop (lines 131-137) is a silent no-op; runner-up: fragile `[version]` cast (line 99) that can void the whole manifest/active-package selection.