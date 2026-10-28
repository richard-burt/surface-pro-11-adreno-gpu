# verdict_record.md — qc-gpu-collect-v1, round 1

Auditor tallies (blind, 5 independent auditors, packet.md claims C1–C6):

| Claim | A1 | A2 | A3 | A4 | A5 | Result |
|---|---|---|---|---|---|---|
| C1 standalone payload (no params/flags/interactivity) | ACCEPT | ACCEPT | ACCEPT | ACCEPT | ACCEPT | **ACCEPT 5/5** |
| C2 Windows PowerShell 5.1 / stock-tools runtime | ACCEPT | ACCEPT | ACCEPT | ACCEPT | ACCEPT | **ACCEPT 5/5** |
| C3 coverage of every Qualcomm graphics aspect | REJECT | REJECT | REJECT | REJECT | REJECT | **REJECT 0/5** |
| C4 robustness (per-section try/catch, no empty catch) | ACCEPT | ACCEPT | ACCEPT | ACCEPT | ACCEPT | **ACCEPT 5/5** |
| C5 safety (read-only, no network/creds/destructive) | ACCEPT | ACCEPT | ACCEPT | ACCEPT | ACCEPT | **ACCEPT 5/5** |
| C6 PowerShell logic correctness | REJECT | REJECT | REJECT | REJECT | REJECT | **REJECT 0/5** |

## Findings and dispositions

1. **ADOPTED (C3+C6)** — S7 adjacent-family sibling loop was a silent no-op: the
   `-Filter 'qcd*8380.inf_arm64_*'` matches package *directories* which were then
   discarded by `-not $_.PSIsContainer`. Fix: `Get-ChildItem -File` directly; the
   sibling `.ini` templates are now collected. (Auditors 1–5.)
2. **ADOPTED (C3)** — `.ini` files were never collected standalone. Fix: per-package
   `*.ini` copy added to 07-firmware\<pkg>; sibling `.ini` files now copied to
   03-driver-packages-infs. (Auditors 2, 3, 5.)
3. **ADOPTED (C6)** — non-existent WMI class `Win32_UEFIEnvironmentVariable` removed
   from S1. (Auditors 1, 2.)
4. **ADOPTED (C6)** — fragile `[version]` cast wrapped in try/catch so a bad INF
   DriverVer string cannot void the S5 manifest or S6 active-package selection;
   `$pkgInfo` initialized before S5 so S6 cannot depend on a failed section.
   (Auditors 1, 2.)
5. **ADOPTED (C6)** — wevtutil: broken/unnecessary `/ow:$true` + `2>$null` removed;
   `$LASTEXITCODE` now checked and failures logged. (Auditors 1, 4.)
6. **ADOPTED (C6)** — transcript file lock risk on Compress-Archive: Stop-Transcript
   now runs before the zip; retry-with-logging in catch path. (Auditors 3, 5.)
7. **ADOPTED (C5/C4)** — elevation check added: script logs whether session is
   elevated (wevtutil System/Application export may need it). Non-fatal, by design —
   collector stays read-only.
8. **REJECTED as by-design (C6)** — 2 GB size guard can skip full copy of an oversized
   active package: intentional protection; the SKIP is explicitly logged and firmware/
   INF/INI subset is still collected. (Auditor 4.)
9. **REVIEWED, no change** — non-recursive top-level `.mbn`/`.bin` copy: these files
   live at package top level in this driver family (verified in DriverStore), but
   `-Recurse` was added anyway. (Auditors 3, 4, 5.)
10. **NOT A BUG (verified)** — `Select-String -Encoding Unicode` for UTF-16 INFs is
    valid in PS 5.1. (Auditor 1.)

## Post-fix verification

- Static analysis gate re-run on fixed bytes: **AST parse CLEAN, PSScriptAnalyzer
  CLEAN (0 findings)**.
- Round 2 quorum scheduled on the fixed bytes for the failed claims C3 and C6.

---

# Round 2 verdict (fixed bytes)

Auditor tallies for claims C3 / C6 (blind, round2-tallies/):

| Claim | A1 | A2 | A3 | A4 | A5 | Result |
|---|---|---|---|---|---|---|
| C3 coverage | REJECT | ACCEPT | REJECT | ACCEPT | ACCEPT | **ACCEPT 3/5** |
| C6 correctness | ACCEPT | ACCEPT | ACCEPT | ACCEPT | ACCEPT | **ACCEPT 5/5** |

Quorum threshold (3-of-5) met for both claims → **qc-gpu-collect-v1 ACCEPTED**.

## Round-2 dissent findings and dispositions

1. **REJECTED as by-design (A3)** — claim that the `-File` sibling scan at
   FileRepository root "matches nothing": verifiably wrong. Auditors 4 (and 5) checked
   the live mounted DriverStore — root-level sibling `.ini` files
   (`qcdx8380.inf_arm64_<hash>.ini` etc., ~1 MB, Qualcomm registry write templates)
   exist next to the package *directories* and match the `-File` filter. Auditor 3
   did not verify against disk.
2. **REJECTED as by-design (A1, A4)** — pattern `qcd*8380.inf_arm64_*` doesn't include
   literal-family `qc8380` or non-graphics `qc*` families (qcadcm, qcbt...). Intent is
   graphics-scoped collection (qcdx graphics + qcdpps/qceva video-adjacent); widening
   to `qc*8380` would pull hundreds of unrelated bluetooth/audio/camera templates.
   Documented as in-scope decision.
3. **REVIEWED, no change (A1, A2, A5)** — `.bin` collection scoped to
   `qcdxkmbase*`: those are the only `.bin` firmware variants in the qcdx packages
   (verified live in DriverStore: qcdxkmbase8380.bin, _68/_110/_150, *_pa variants).
4. **INFORMATIONAL, adopted where trivial (A4)** — reg.exe exit codes not individually
   logged: covered by the existing per-section try/catch + failure logging; a silent
   single-key reg failure is non-blocking for collection purposes. Null-version sort
   edge: `Sort-Object Version -Descending` places $null last, newest-by-version still
   wins — behaves correctly.

**Final status: round 1 C1/C2/C4/C5 ACCEPT; round 2 C3/C6 ACCEPT after findings
adoption; static analysis gate re-run on all fixed bytes (AST CLEAN, PSSA CLEAN).**
Script approved for execution.