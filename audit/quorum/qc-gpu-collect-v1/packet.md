# Quorum packet — qc-gpu-collect-v1 (round 1)

Blind quorum review per standing rule. Target artifact:

`screenshot-free target`: `collect-qc-gpu-win.ps1` (workspace root)

Context: standalone Windows PowerShell collector script that will be run manually under
Windows 11 (ARM64, dual-boot of this machine) to collect all Qualcomm Adreno graphics
driver data (DriverStore packages, registry, firmware blobs, logs) for offline analysis
on the Ubuntu side. Standing rules: standalone payload (no param block/CLI switches/
interactivity; identity/settings hardcoded), no password or secret handling.

## Claims to audit (vote ACCEPT or REJECT per claim, cite evidence line numbers, list independent findings)

- **C1 Standalone payload**: no param block, no CLI flags/switches read, no args
  dependency, no interactivity gates (Read-Host, prompts); all identity/settings are
  hardcoded constants.
- **C2 Runtime**: correct for stock Windows PowerShell 5.1 on Windows 11 ARM64 without
  non-default modules: only CIM cmdlets, Get-WinEvent, Get-Service, Compress-Archive,
  built-ins, and external tools shipped with Windows (reg.exe, pnputil.exe,
  driverquery.exe, wevtutil.exe, sc.exe, dxdiag.exe). #Requires -Version 5.1 present.
- **C3 Coverage of "every aspect of the Qualcomm graphics + driver"**: system, PnP
  devices, display/GPU, driver packages + INF/CAT/INI, newest-package binary copy,
  firmware .mbn/.bin of all versions, registry (services, display class, ACPI enum,
  Qualcomm software, DriverDatabase), services, event logs, setupapi logs, dxdiag,
  hashes/versions manifest, final zip.
- **C4 Robustness**: per-section try/catch that logs and continues; no empty catch;
  transcript; collection still produces usable partial output on failures.
- **C5 Safety**: read-only collection (no writes outside C:\QC-GPU-Collect), no network
  calls, no credential/secret access, no registry writes, no deletion, no destructive
  or dangerous operations.
- **C6 Correctness**: PowerShell logic bugs (encoding of INFs as Unicode, version
  parsing, path handling, PS 5.1 syntax compliance, splatting, operator usage) — look
  for actual misbehavior of the collector.

## Output contract (write BOTH files, then reply with a one-line summary)

- `tallies/tally_N.json`: `{"auditor":"N","votes":{"C1":"ACCEPT|REJECT",...,"C6":"..."},"findings":["..."]}`
- `tallies/tally_N.md`: human-readable vote table + findings with line refs.

You are auditor N per your instruction index. Work alone; do not read other tallies.