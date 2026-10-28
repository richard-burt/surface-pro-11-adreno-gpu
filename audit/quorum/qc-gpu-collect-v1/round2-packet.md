# Quorum packet — qc-gpu-collect-v1, round 2

Round 2 audits the FIXED bytes of `collect-qc-gpu-win.ps1` after adoption of round-1
findings (see verdict_record.md). Only claims C3 and C6 (the round-1 failures) are
re-voted. You are one of 5 blind auditors; work alone, do not read other tallies.

## Claims to re-audit

- **C3 Coverage**: does the script now collect every aspect of the Qualcomm graphics
  stack + driver? Check specifically:
  - full binary copy of the newest qcdx8380 package (size guard at 2000 MB)
  - firmware .mbn/.bin + INF/CAT/INI of ALL qcdx versions → 07-firmware
  - sibling .ini registry-template files of qcd*/qcdx*/qc8380 families →
    03-driver-packages-infs (previously a no-op, now `Get-ChildItem -File`)
  - registry exports, services, event logs, setupapi, dxdiag, hashes/versions, zip
- **C6 Correctness**: PowerShell 5.1 logic soundness after fixes:
  - `[version]` cast guarded (try/catch, no void of S5/S6)
  - `$pkgInfo` initialized before S5
  - wevtutil `$LASTEXITCODE` checked, no `/ow`, no `2>$null` swallow
  - Stop-Transcript before Compress-Archive; guarded Stop-Transcript retry; no empty
    catch blocks
  - elevation detection present and non-fatal
  - no param block/CLI/interactivity, settings hardcoded (unchanged round-1 C1 facts)

## Output contract

Write BOTH files under `tallies/`:
- `tally_N.json`: `{"auditor":"N","claims":{"C3":"ACCEPT|REJECT","C6":"ACCEPT|REJECT"},"findings":["..."]}`
- `tally_N.md`: vote table + findings with line refs.

Target: `/home/richard/Documents/projects/this-installed-ubuntu/gpu/collect-qc-gpu-win.ps1`