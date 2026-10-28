# Surface Pro 11 Adreno GPU — Linux driver project + Qualcomm Windows driver RE corpus

Research project on the **Microsoft Surface Pro 11th Edition (OLED)** — Snapdragon
**X1E-80100** (12-core) — running Ubuntu 26.04.1 aarch64 with a Qualcomm X1E kernel
(`7.2.9-jg-0sp11v2-qcom-x1e`), dual-booting Windows 11.

## Outcome

The project's original goal — a working Linux graphics driver for the Adreno X1-85 —
is **already satisfied by the stock open-source stack**, and was validated by benchmark:

| Component | Stack | Result |
|---|---|---|
| Kernel GPU driver | `adreno`/`msm` + GMU (upstream Linux msm/drm) | GPU + GMU bound, zap shader + GMU fw (v4.3.17) loaded |
| OpenGL 4.6 / GLES 3.2 | Mesa **freedreno** (Mesa 26.0.8) | glmark2-es2-wayland score **5636**, all scenes clean |
| Vulkan 1.4.335 | Mesa **turnip** | `vkcube` clean, "Adreno X1-85, IntegratedGpu" |
| DVFS | devfreq `3d00000.gpu` | 300 MHz idle → 1.25 GHz peak → clean decay |
| Stability | stress + dmesg audit | zero GPU MMU faults / hangs / timeouts |

Suspend/resume stability could not be validated: the test system has `sleep.target`
masked (deliberate policy) and the custom kernel rejects suspend with `-EIO` even at
the `pm_test=freezer` stage — machine never suspends, so the GPU-resume failure mode
cannot manifest there.

## Repository contents

- [`analysis/rea-notes.md`](analysis/rea-notes.md) — the reference corpus:
  reverse-engineering findings (Ghidra/REA) of Qualcomm's Windows Adreno driver
  stack for this SoC, organized for Linux-side reuse:
  - `libqcdx12arm64wslum.so` — WSL D3D12 UMD (native Linux-ABI ELF): A7x gen7 +
    A8x gen8 backends, QNGC compiler DDI, OpenCL via D3D12 meta-commands
  - `qcdxkm8380.sys` — WDDM kernel miniport (WDF/DMF): Venus VED video-encode
    HFI embedded, GMU firmware delivered via WMI/blob at 0x40030000/0x40060000
  - `libgsluser.dll` — 229-export KGSL-ABI mirror over D3DKMT (pluggable ioctl
    ops table — same code family drives `/dev/kgsl-3d` on Linux)
  - `OpenCL_adreno.dll` + full OpenCL dependency chain, including
    `qcclarm64xcompiler.dll` = Qualcomm's internal Clang/LLVM fork
  - firmware blob mapping (`qcdxkmbase8380*.bin` = SEC/protection base images;
    GMU/SQE firmware not shipped as files on Windows), INF/registry decode
- [`collect-qc-gpu-win.ps1`](collect-qc-gpu-win.ps1) — standalone Windows 11
  collector (PowerShell 5.1, no params/switches) used to gather the full driver
  package, firmware, registry templates, event logs and dxdiag from the Windows side
- [`plan.md`](plan.md) — the plan of attack (phases 0–5) as executed
- [`audit/quorum/qc-gpu-collect-v1/`](audit/quorum/qc-gpu-collect-v1/) — blind
  quorum-review records for the collector script (5 auditors, 3-of-5 per claim)

## Key facts for anyone driving an Adreno X1E on Linux

- ACPI id `QCOM\DEV_0C36`, device name `QC_Device_X185`; on the Linux side the DT
  compatible is `qcom,adreno-43050c01` (a740 family). Windows-internal chip-family
  encodings observed: `0x88` (gen7) / `0x9a` (gen8); revision switch in
  `A7xInit(`0x60c312 → caps 0x180, 0x60c5xx → 0x300).
- Interconnect/PM counterparts found in the Windows KMD map 1:1 to Linux:
  `GPU_RPMH_CPRF` (rpmh rails), `ICBID_MASTER_GFX3D`/`ICBID_SLAVE_GFX3D_CFG`
  (icc paths), QTimer timestamps.
- Real Linux gaps vs. the Qualcomm stack (as shipped on Windows): **OpenCL**
  (no ICD for Adreno on Ubuntu 26.04) and **video encode/decode APIs**
  (AV1/H264/HEVC encode via Venus HFI exists on Windows only).

## Hardware reference

- Machine: Surface Pro 11th Edition (OLED), X1E-80100, 16 GB
- GPU: Adreno X1-85 (Adreno 43050c01 / gen7 "X185")

*No proprietary code or binaries are included in this repository — only
reverse-engineering notes, tooling and methodology.*