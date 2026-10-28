# Tally — auditor 3, round 2 (qc-gpu-collect-v1)

Target audited: `/home/richard/Documents/projects/this-installed-ubuntu/gpu/collect-qc-gpu-win.ps1` (fixed bytes, round 2). Claims re-voted: C3, C6 only, per round2-packet.md. Worked blind; no other tallies or verdict records read.

## Vote table

| Claim | Round 1 | Round 2 (this auditor) | Verdict driver |
|-------|---------|------------------------|----------------|
| C3 Coverage | FAIL | **REJECT** | Sibling .ini → 03-driver-packages-infs scan is still a no-op (wrong filter + `-File` at FileRepository root); qc8380 family excluded |
| C6 Correctness | FAIL | **ACCEPT** | All packets's C6 bullets verified present and sound |

## C3 — REJECT

Checked each bullet of the packet:

1. **Full binary copy of newest qcdx8380 package, 2000 MB guard — PASS.**
   L18 `$MaxFullCopyMB = 2000`; L118–128 sorts `$pkgInfo` by Version descending, copies recursively, logs skip when above guard. `$null` versions sort last in PowerShell, so a package with a parseable DriverVer beats one with a failed cast. OK.

2. **Firmware .mbn/.bin + INF/CAT/INI of ALL qcdx versions → 07-firmware — PASS with minor note.**
   L132–140 loops every `$gfxPkgs` dir, copies `*.mbn`, `qcdxkmbase*.bin`, `qcdx8380.inf`, `qcdx8380.cat`, `*.ini` into `07-firmware\<pkg>`. Minor: `.bin` capture is prefix-narrowed to `qcdxkmbase*` — any other firmware-named `.bin` in the packages would be missed (claim text says ".mbn/.bin").

3. **Sibling .ini registry-template files of qcd*/qcdx*/qc8380 families → 03-driver-packages-infs — FAIL (round-1 defect persists).**
   L141–144: `Get-ChildItem -Path $FileRepo -Filter $GfxSiblings -File` with `$GfxSiblings = 'qcd*8380.inf_arm64_*'` (L17), then Copy-Item to `03-driver-packages-infs`.
   - The filter matches names shaped like package directory names. FileRepository root contains those names only as **directories**; `-File` excludes them → enumeration returns nothing.
   - Registry-template `.ini` files are siblings of the INF **inside** each package dir (names like `qcdx8380.ini`), and `qcdx8380.ini` cannot match `qcd*8380.inf_arm64_*` (after `8380.` the pattern demands `inf_arm64_`). No `-Recurse`, no package-dir walk → these files are never enumerated.
   - Net effect: `03-driver-packages-infs` receives nothing from this scan — the "previously a no-op" condition is reproduced. Correct shape would be: enumerate family dirs (`-Directory -Filter`), then copy `*.ini` files from inside them to 03-driver-packages-infs (or `-Recurse -Filter *.ini`).
   - Additionally the literal `qcd` prefix excludes the `qc8380` family named in the claim.

4. **Registry exports, services, event logs, setupapi, dxdiag, hashes/versions, zip — PASS.**
   S8 (L148–175): Services/display-class/Enum ACPI/Qualcomm software/DriverDatabase reg exports. S9 services + `sc qc`. S10 wevtutil `epl` EVTX for System/Application/Kernel-PnP + 30-day QC-filtered JSON. S11 setupapi logs. S12 dxdiag with completion polling. S13 SHA256 checksums, file-versions CSV, zip. All present.

**C3 verdict: REJECT** — bullet 3 unfulfilled (decisive), bullet 2 partially narrowed (`.bin` prefix).

## C6 — ACCEPT

- **`[version]` cast guarded:** L107 `try { $ver = [version]... } catch { $ver = $null }` inside the per-package construct — a malformed DriverVer no longer throws out of S5; recorded with Version `$null`; S6 sort tolerates `$null`. S5/S6 not voided. ✔
- **`$pkgInfo` initialized before S5:** L96 `$pkgInfo = @()` before the S5 try block; S6 (L119) always sees an array. ✔
- **wevtutil:** L192–195 `$LASTEXITCODE -ne 0` → logged failure per channel, non-fatal; no `/ow` flag present; no `2>$null` stderr swallowing anywhere in the script (verified by scan). ✔
- **Transcript/zip ordering:** L243 `Stop-Transcript | Out-Null` runs before L245 `Compress-Archive`; S13 catch (L247–250) retries `Stop-Transcript` with a guarding try/catch that logs failure. No empty catch blocks anywhere (every catch writes log or sets `$isAdmin`). ✔
- **Elevation detection:** L47–52 try/catch, non-fatal, result logged at L52. ✔
- **Standalone rules (round-1 C1 facts, unchanged):** no param block (the only `param` is the function-level one at L22), no CLI switches, no interactivity/Read-Host, all identity/settings hardcoded at L11–19. ✔

**C6 verdict: ACCEPT.**

## Findings summary

1. **C3 FAIL** — sibling .ini → 03-driver-packages-infs scan (L141–144) still a no-op: `-File` + package-dir-shaped filter at FileRepository root matches nothing; .ini templates live inside package dirs and cannot match the filter (refs L17, L141–144).
2. **C3** — qc8380 family excluded by the literal `qcd` prefix in the filter.
3. **C3 minor** — `.bin` collection narrowed to `qcdxkmbase*.bin` (L136) vs claim's ".mbn/.bin".
4. C3 OK — full-copy guard/copy logic (L18, L118–128) correct.
5. C3 OK — registry/services/events/setupapi/dxdiag/hashes/versions/zip all present (S8–S13).
6. C6 OK — guarded `[version]` cast (L107), `$pkgInfo` pre-initialization (L96).
7. C6 OK — wevtutil `$LASTEXITCODE` check (L192–195), no `/ow`, no `2>$null`.
8. C6 OK — Stop-Transcript before zip (L243) + guarded retry (L249); no empty catches.
9. C6 OK — elevation detection non-fatal (L47–52); standalone rules intact.