# Tally — auditor 4 — qc-gpu-collect-v1 (round 1)

Target: `collect-qc-gpu-win.ps1` (workspace root), read in full (240 lines).
Blind review; no other tallies consulted.

## Vote table

| Claim | Vote | Summary |
|-------|------|---------|
| C1 Standalone payload | ACCEPT | No param block at script level (only function-level `param`, lines 22/29), no args/CLI switches, no Read-Host or prompts; `$OutputRoot`, `$InfFamily`, `$GfxSiblings`, `$MaxFullCopyMB` hardcoded (lines 11-18). dxdiag `/t` is non-interactive. |
| C2 Runtime | ACCEPT | `#Requires -Version 5.1` present (line 9). All cmdlets are PS 5.1 built-ins (Get-CimInstance, ConvertTo-Json, Out-File, Get-ChildItem, Select-String, Copy-Item, Start/Stop-Transcript, Get-WinEvent, Get-Service, Get-FileHash, Export-Csv, Compress-Archive, Measure-Object, Sort-Object, Start-Sleep). Externals: pnputil.exe, driverquery.exe, reg.exe, sc.exe, wevtutil.exe, dxdiag.exe — all ship with Windows 11 ARM64. No non-default modules. |
| C3 Coverage | **REJECT** | Most sections present (system S1, PnP S2, display S3, drivers S4, manifest S5, newest-copy S6, registry S8, services S9, event logs S10, setupapi S11, dxdiag S12, hash/zip S13), but three enumerated coverage elements fail: (a) adjacent/sibling *families* never copied — the S7 loop is a no-op (see F1); (b) INI files not collected for any version standalone (claim text explicitly lists INF/CAT/INI); (c) firmware .mbn/.bin copied only from package top level (non-recursive wildcard), and the newest-package full copy is skipped above 2000 MB. |
| C4 Robustness | ACCEPT | Every section wrapped in try/catch that logs via Write-CollectLog and continues (lines 57/66/76/87/106/119/139/168/178/193/200/216/235-237); no empty catch; transcript started (line 45); `$gfxPkgs`/`$pkgInfo` pre-initialized (lines 90-95) and S6 handles null/empty via `if ($active -and ...)`. Minor transcript gaps noted (F11). |
| C5 Safety | ACCEPT | All writes land under `C:\QC-GPU-Collect` ($Out or $OutputRoot): Out-File, Add-Content, transcript, reg.exe export /y, dxdiag /t $dxPath, Copy-Item destinations, Compress-Archive destination (lines 232-233). No Remove-Item, no registry writes/imports, no network cmdlets, no credential/secret access, no interactivity. Read-only elsewhere. |
| C6 Correctness | **REJECT** | One real misbehavior (F1: sibling-collection filter makes S7 silently collect nothing) plus wevtutil `/ow:$True` casing stderr-masked, unchecked native exit codes, and INF-encoding assumption — all degrade or silently void parts of the collection. |

## Findings (line references)

1. **BUG — S7 sibling loop no-op (lines 131-137).** `Where-Object { -not $_.PSIsContainer }` excludes the directories that match filter `'qcd*8380.inf_arm64_*'`; FileRepository has no loose matching files, so the adjacent-family INF/CAT copy never executes and nothing is logged. Fix: match the sibling intent — `-Directory` and copy the directories (or their contents) into `03-driver-packages-infs`.
2. **Coverage gap — no INI collection (lines 126-129).** Only `*.mbn`, `qcdxkmbase*.bin`, `qcdx8380.inf`, `qcdx8380.cat` copied per package; INIs exist only inside the newest-package full copy, and even that is size-gated.
3. **Coverage gap — non-recursive firmware copy (lines 126-127).** `Copy-Item -Path (Join-Path $p.FullName '*.mbn')` is top-level only; blobs in subfolders are missed. `-Recurse` with `-Filter`, or a recursive variant, would close it.
4. **Coverage risk — 2 GB guard (lines 18, 112-117).** If the active qcdx8380 package exceeds 2000 MB the full binary copy is skipped with only a log line; on a modern Adreno package this defeats "newest-package binary copy".
5. **Risk — wevtutil `/ow:$true` (line 184).** Parses to `/ow:True`; documented casing is `true|false`. With `2>$null` discarding stderr and `$LASTEXITCODE` unchecked, a rejected flag yields a silently missing .evtx.
6. **Robustness — native exit codes unchecked (S4, S8, S9, S10, S12).** try/catch does not capture native-tool failures; per-key reg.exe exports can fail invisibly.
7. **Minor — INF encoding assumption (line 97).** `Select-String -Encoding Unicode` (UTF-16LE) silently produces no match on an ANSI INF → Version `$null`, degraded newest selection, no warning.
8. **Minor — no elevation check.** Win32_UEFIEnvironmentVariable and DriverStore/registry reads need admin; non-admin runs produce partial output with no elevation-state log.
9. **Minor — transcript hashed while live (lines 220-221).** Get-FileHash may fail on the open transcript.log and is swallowed (`-ErrorAction SilentlyContinue`); also checksums.csv / file-versions.csv exclude themselves by construction — by design, documented.
10. **Minor — ACPI filter may undermatch (line 154).** `^VEN_QCOM` is environment-dependent; verify actual `Enum\ACPI` key naming on the target hardware.
11. **Minor — transcript lifecycle (lines 45, 240).** Start-Transcript unguarded (already-running case) and Stop-Transcript not in `finally`; a terminating crash leaves transcription active and the transcript footless.

## Verdict record

- C3 and C6 rejected on the concrete, evidence-cited defects above (F1, F2-F4 for C3; F1+F5+F6+F7 for C6).
- Remaining claims accepted with the minor findings recorded; none of the findings involves unsafe writes outside `C:\QC-GPU-Collect` or non-vault secret handling.
- If F1 (sibling filter) and F5 (`/ow:true` + exit-code checks) are fixed, a re-run of this packet round would be warranted for C3/C6.