# Tally — auditor 2, round 2 (qc-gpu-collect-v1)

Target: `collect-qc-gpu-win.ps1` (fixed bytes). Audited only against
`round2-packet.md` claims C3 and C6; no other tallies or verdict records read.

## Vote table

| Claim | Vote | Summary |
|-------|------|---------|
| C3 Coverage | **ACCEPT** | All four round-2 checklist items implemented in the fixed bytes |
| C6 Correctness | **ACCEPT** | All six round-2 checklist items implemented; PS 5.1 logic sound |

## C3 — Coverage (ACCEPT)

| Sub-claim | Evidence (line refs) | Verdict |
|-----------|----------------------|---------|
| Full binary copy of newest qcdx8380 package, 2000 MB guard | `$MaxFullCopyMB = 2000` (l.18); S6 picks newest via `Sort-Object Version -Descending` (l.119), size-guarded `Copy-Item -Recurse` (l.121-122), skip logged if over guard (l.125) | PASS |
| Firmware .mbn/.bin + INF/CAT/INI of ALL qcdx versions → 07-firmware | S7 loop over `$gfxPkgs` (every discovered package, l.132): `*.mbn` (l.135), `qcdxkmbase*.bin` (l.136), `qcdx8380.inf` (l.137), `.cat` (l.138), `*.ini` (l.139) | PASS |
| Sibling .ini registry-template files, `Get-ChildItem -File` | l.141-144: `Get-ChildItem -Filter 'qcd*8380.inf_arm64_*' -File` → copies each match into `03-driver-packages-infs` (l.143). Round-1 no-op fixed | PASS |
| Registry exports, services, event logs (EVTX+CSV), setupapi, dxdiag, hashes/versions, zip | S8 reg exports incl. Services/Class/Enum/Qualcomm/DriverDatabase (l.148-175); S9 `sc.exe qc` (l.177-185); S10 wevtutil epl + filtered Get-WinEvent (l.187-204); S11 setupapi.dev*.log (l.206-211); S12 dxdiag /t with size-stable wait loop (l.213-227); S13 SHA256 + file-versions CSV + Compress-Archive (l.229-250) | PASS |

Findings (informational, non-blocking):
1. `Copy-Item -Path '<pkg>\*.mbn' -Recurse` (l.135) matches the leaf wildcard only in the
   package root; `.mbn` files in subdirectories of older packages are not collected.
   Mitigated for the active package by S6's full recursive copy. INFO.
2. Filter `qcd*8380.inf_arm64_*` (l.17, l.141) requires the literal `qcd` prefix, so a
   literal `qc8380.inf_arm64_*` family name would not match; qcdx8380 and qcd<other>8380
   families are covered. INFO.
3. `.bin` collection scoped to the `qcdxkmbase*` prefix (l.136) rather than all `*.bin`;
   consistent with Adreno firmware naming. INFO.

## C6 — Correctness, PS 5.1 (ACCEPT)

| Sub-claim | Evidence | Verdict |
|-----------|----------|---------|
| `[version]` cast guarded, no void of S5/S6 | l.107: `try { $ver = [version]... } catch { $ver = $null }` — flow continues; S5/S6 unaffected | PASS |
| `$pkgInfo` initialized before S5 | l.96: `$pkgInfo = @()` ahead of the try block; catch path (l.115) leaves a safe empty array for S6 | PASS |
| wevtutil `$LASTEXITCODE` checked, no `/ow`, no `2>$null` swallow | l.192-195: exit code checked per channel, failures logged; grep confirms zero occurrences of `2>$null` and `/ow` in the file | PASS |
| Stop-Transcript before Compress-Archive; guarded retry; no empty catch | l.243 `Stop-Transcript` precedes l.245 `Compress-Archive`; l.249 guarded retry logs failure; scan of all 17 catch blocks finds none empty | PASS |
| Elevation detection present, non-fatal | l.47-52: WindowsPrincipal/IsInRole in try/catch, result logged with caveat | PASS |
| No param block/CLI/interactivity; settings hardcoded | No script-level param, no `$args`, no Read-Host; l.22 `param` is a scoped helper-function parameter (allowed); `$OutputRoot`, filter patterns, size guard all hardcoded constants | PASS |

Static analysis evidence (read-only check by auditor): AST parse of the fixed bytes →
0 errors; `Invoke-ScriptAnalyzer` → 0 findings.

## Result

```
auditor: 2    C3: ACCEPT    C6: ACCEPT    findings: 3 informational + 7 PASS notes
```