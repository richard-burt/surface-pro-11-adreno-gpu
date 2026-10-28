# Tally — auditor 5, round 2 (qc-gpu-collect-v1)

Target: `/home/richard/Documents/projects/this-installed-ubuntu/gpu/collect-qc-gpu-win.ps1` (fixed bytes)
Packet: `../round2-packet.md`. Blind audit — no other tallies or verdict records read.

## Vote table

| Claim | Vote | Summary |
|-------|------|---------|
| C3 Coverage | **ACCEPT** | All round-1 fixes present: S6 full copy + 2000 MB guard, S7 all-version firmware (mbn/bin/inf/cat/ini) → 07-firmware, sibling `.ini` collection fixed via `Get-ChildItem -File` → 03-driver-packages-infs, registry/services/events/setupapi/dxdiag/hashes/zip all implemented. Two minor residual coverage notes (below), neither invalidates the adopted fixes. |
| C6 Correctness (PS 5.1) | **ACCEPT** | `[version]` cast guarded, `$pkgInfo` pre-initialized, wevtutil `$LASTEXITCODE` checked (no `/ow`, no `2>$null`), Stop-Transcript before Compress-Archive with guarded retry, no empty catch blocks, elevation detection non-fatal, no param block / CLI / interactivity. Static gate: AST parse 0 errors, PSScriptAnalyzer 0 findings. |

## C3 evidence (line refs)

- Full copy + guard: S5 picks newest by parsing `DriverVer` (`:103-108`), S6 `Copy-Item -Recurse` gated by `$active.SizeMB -le $MaxFullCopyMB` with `$MaxFullCopyMB = 2000` (`:18`, `:121-125`); skip path logs and retains package (`:125`).
- All-version firmware: S7 iterates every `$gfxPkgs` entry (`:132-140`) → `*.mbn`, `qcdxkmbase*.bin`, `qcdx8380.inf`, `qcdx8380.cat`, `*.ini` per package under `07-firmware\<pkg>`. `$InfFamily` filter (`:16`, `:98`) covers all qcdx8380 versions.
- Sibling .ini fix (round-1 no-op → fixed): `Get-ChildItem -Path $FileRepo -Filter $GfxSiblings -File` (`:141`) copies matched files into `03-driver-packages-infs` (`:141-144`).
- Registry (S8 `:148-175`): qcdx/qcgpu service keys, display class `{4d36e968-…}` subkeys, `Enum\ACPI` VEN_QCOM, Qualcomm software roots (native + WOW6432Node), `DriverDatabase\DriverPackages` qcdx8380 — all via `reg.exe export /y`.
- Services S9 (`:177-185`), event logs S10 (`:187-204`, EVTX via wevtutil + 30-day QC-filtered JSON), setupapi S11 (`:206-211`), dxdiag S12 (`:213-227`, poll-until-stable), hashes/versions/zip S13 (`:229-250`).

### C3 findings (minor, non-fatal)

1. `:17` `$GfxSiblings = 'qcd*8380.inf_arm64_*'` — the wildcard cannot match a family literally named `qc8380.inf_arm64_*` (pattern requires the `d`). If such siblings exist on the target their `.ini` templates are missed. Recommend verifying family names against a real FileRepository listing.
2. `:136` — firmware `.bin` collection is narrowed to `qcdxkmbase*.bin`; other `.bin` blobs bypass 07-firmware (active package still fully covered by S6).

## C6 evidence (line refs)

- `[version]` guard: `:107` (`try { $ver = [version]… } catch { $ver = $null }`); downstream `Sort-Object Version` tolerates `$null`, S6 still selects a package.
- `$pkgInfo = @()` before S5: `:96`.
- wevtutil: `:192-195` — `$LASTEXITCODE -ne 0` logged per channel; no `/ow`; grep confirms zero `2>$null` occurrences file-wide.
- Transcript/zip ordering: `Stop-Transcript` `:243` → `Compress-Archive` `:245`; failure path retries inside `try { Stop-Transcript } catch { log }` `:249`; every catch block in the file is non-empty.
- Elevation detection: `:47-52`, non-fatal catch, result logged `:52`.
- Standalone rules: no script-level `param` (only function params `:22`, `:29`), no CLI switches, no prompts; constants hardcoded `:11-19`.
- Auditor-side static check (pwsh 7.6.4): `Parser::ParseFile` → **0 errors**; `Invoke-ScriptAnalyzer` → **0 findings**.