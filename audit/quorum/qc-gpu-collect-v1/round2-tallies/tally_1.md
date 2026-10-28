# Quorum tally — qc-gpu-collect-v1, round 2 — Auditor 1

Packet: `../round2-packet.md`. Target audited: `../../../../../collect-qc-gpu-win.ps1` (fixed bytes, round-2). Worked alone; no other tallies or verdict records read.

## Vote table

| Claim | Vote | Summary |
|-------|------|---------|
| C3 Coverage | **REJECT** | Most of the claimed coverage is present, but the sibling-family pattern misses a family the claim names (`qc8380`) and `.bin` firmware is filtered narrower than claimed. |
| C6 Correctness (PS 5.1) | **ACCEPT** | All packet-specified fixes verified in the bytes; no empty catches, no unguarded casts, transcript/zip ordering correct, standalone rules intact. |

## C3 — Coverage: REJECT

Packet checklist, line refs into `collect-qc-gpu-win.ps1`:

- **Full binary copy of newest qcdx8380 package, guard 2000 MB** — OK. S5 builds `$pkgInfo` (lines 95–115), S6 sorts by Version desc, picks first, copies to `06-driverstore-active` only if `SizeMB -le $MaxFullCopyMB` (lines 117–128; guard = 2000 at line 18). Guard works; skip is logged (line 125).
- **Firmware .mbn/.bin + INF/CAT/INI of ALL qcdx versions → 07-firmware** — PARTIAL. S7 loops all `$gfxPkgs` (lines 132–140): `*.mbn` (line 135) covers all; **finding F2**: `.bin` limited to `qcdxkmbase*.bin` (line 136) — claim says ".mbn/.bin" without a narrower filter; `qcdx8380.inf/.cat/*.ini` per version OK (lines 137–139).
- **Sibling .ini registry-template files of qcd*/qcdx*/qc8380 families → 03-driver-packages-infs** — FAIL per claim text. S7 second block uses `-File` exactly as the packet prescribes (lines 141–144), **but** `$GfxSiblings = 'qcd*8380.inf_arm64_*'` (line 17) cannot match literal `qc8380...`: the `d` in `qcd*8380` is required, so `qc8380.inf_arm64_*` is excluded (**F1** — direct miss on a family named in the claim). Observation (**F3**): on a standard system FileRepository top level holds only directories, so a top-level `-File` scan can still return nothing; package-internal `*.ini` go to 07-firmware only (line 139), never to 03-driver-packages-infs as the claim routes them. Flagged as residual risk since the packet itself prescribes `-File` as the fix.
- **Registry exports, services, event logs, setupapi, dxdiag, hashes/versions, zip** — OK. S8 registry (lines 148–175, incl. services/class/enum/Qualcomm/DriverDatabase), S9 services (177–185), S10 EVTX + filtered CSV (187–204), S11 setupapi (206–211), S12 dxdiag with poll loop (213–227), S13 checksums + file-versions + zip (229–250).

**Why REJECT:** claim C3 as written is not fully satisfied — F1 is a provable byte-level miss on a claim-named family; F2 is partial against the claim wording.

## C6 — Correctness (PS 5.1 logic): ACCEPT

- **`[version]` cast guarded, no void of S5/S6** — OK: try/catch sets `$ver = $null`, inside S5's try (line 107).
- **`$pkgInfo` initialized before S5** — OK: `$pkgInfo = @()` at line 96, before the try; S6 (117–128) handles empty/null `$active`.
- **wevtutil `$LASTEXITCODE` checked, no `/ow`, no `2>$null` swallow** — OK: `$LASTEXITCODE -ne 0` logged per channel (lines 193–195); no `/ow` anywhere; no `2>$null` anywhere in the file.
- **Stop-Transcript before Compress-Archive; guarded retry; no empty catch** — OK: `Stop-Transcript` at line 243 precedes Compress-Archive (line 245); catch block retries Stop-Transcript inside try/catch and logs failure (line 249). All catch blocks checked (lines 34–36, 51, 62, 71, 81, 92, 115, 128, 146, 175, 185, 204, 211, 227, 247–250) — every one logs or assigns; none empty.
- **Elevation detection present, non-fatal** — OK: lines 47–52, catch sets `$isAdmin = $false` and logs.
- **No param block / CLI switches / interactivity; settings hardcoded** — OK: script-level param block absent (the only `param()` is inside the `Write-CollectLog` function, line 22, which is fine); all constants hardcoded lines 11–19; `#Requires -Version 5.1` present (line 9).
- Minor, non-blocking (**C6/F1**): with all versions null, the "newest" pick (line 119) is enumeration-order based; `$null` sorts last under `-Descending`, so any real version beats null — soundness unaffected.