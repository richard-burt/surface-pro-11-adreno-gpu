# Plan of Attack — Qualcomm Adreno Linux Graphics Driver

## Objective
Get a working graphics driver (GPU acceleration under Mesa/Vulkan/GL) for Adreno
(a740 / "X1-85", DT compatible `qcom,adreno-43050c01`) on this Ubuntu 26.04 install
running on a Surface Pro 11 (X1E-80100, custom qcom-x1e kernel), using the Windows 11
Qualcomm graphics driver on the dual-boot partition as the reference corpus, analyzed
with the REA MCP reverse-engineering toolchain.

## Current state (verified 2026-10-28)

| Component | Windows 11 side | Ubuntu side |
|---|---|---|
| GPU | ACPI\VEN_QCOM&DEV_0C36 "QC_Device_X185", driver qcdxkm8380.sys, versions 31.0.38.06 → 31.0.152.1 | `qcom,adreno-43050c01` node at 3d00000.gpu, bound to `adreno` driver, **no render card** |
| Display | Qualcomm DPP / DirectDisplay stack | msm_dpu works (card1, eDP + 2x DP) — desktop already renders via dpu |
| Firmware | qcdxkmbase8380*.bin (per speed-bin), qcdxkmsuc8380.mbn (+ purwa), qcvss8380.mbn | /lib/firmware/qcom/* legacy Adreno a2xx–a530 blobs present; x1e80100 a740 set status TBD |
| Userspace | qcdx12arm64xum8380.dll (D3D12 UMD), OpenCL, Vulkan-capable compiler cores, `libqcdx12arm64wslum.so` (Linux ELF!) | Mesa (turnip/freedreno) status TBD |

## Strategy — three independent knowledge streams converge
1. **Upstream Linux/Mesa**: a740 is generation-7 Adreno; upstream `adreno` DRM +
   turnip already contain a740 support. Our failure is likely **firmware presence/naming**
   or a DT/zap detail on this custom kernel — cheapest path to a working driver first.
2. **Windows driver binary analysis (REA)**: qcdxkm8380.sys (KMD), libgsluser.dll,
   D3D12 UMD, compiler cores, firmware .mbn/.bin parsing — establishes register/UCI/GMU
   details, chip-bin → firmware mapping, MMU/IOMMU config, power/OPP behavior.
3. **Registry/INI templates + collector telemetry**: the driver package .ini files are
   literal registry write templates (clocks, IOMMU, GMU, bin overrides) — decode once,
   reuse forever.

## Phase breakdown
- **P0 Recon** (done): machine/Soc/GPU IDs both OSes; DriverStore inventory.
- **P1 Windows collection**: run `collect-qc-gpu-win.ps1` under Windows 11 →
  zip with everything (devices, registry, INIs, INFs, binaries, firmware, dxdiag,
  event logs, setupapi) → copy into workspace.
- **P2 REA decompilation**: priority order:
  1. `libqcdx12arm64wslum.so` — Linux ELF, WSL D3D12 UMD; parse directly on Ubuntu.
  2. `qcdxkm8380.sys` — ARM64 PE KMD: IOCTL table, structure layouts, FW-load path.
  3. `libgsluser.dll` — Graphics Stack Layer ABI (KGSL-analog).
  4. Firmware blobs .mbn/.bin — ELF/pil-header parse, map vs. linux-firmware naming.
  5. Compiler cores (qcgpu*compilercore*) — shader ISA reference.
- **P3 Linux diagnostics**: dmesg of adreno probe, firmware audit
  (a740_zap.mbn / GMU gen7 bins), kernel config check, DT zap-shader + nvmem speed-bin.
- **P4 Build the driver**: fix firmware → adreno render node up → Mesa turnip/zink →
  Wayland compositor on GPU.
- **P5 Validation**: vulkaninfo/ glmark2/ weston; regressions; final docs.

## Success criteria
- `/dev/dri` exposes an adreno card with render node; Vulkan + GL apps run on GPU;
  desktop compositor uses it; reboot-stable.

## Standing rules honored
- todo.md/history.md as source of truth; static analysis + quorum gates on scripts;
  credentials via Bitwarden MCP only.

## Status addendum (Session 2, 2026-10-28)
- P3 executed: GPU probes fine; firmware all present; **P4 stock goal already met**
  (GL 4.6 freedreno + Vulkan 1.4.335 turnip, "Adreno X1-85", verified via
  eglinfo/vulkaninfo/glxinfo; card1+renderD128 is the combined DPU+GPU msm card).
- The single-card assumption in "Success criteria" was corrected: no separate GPU
  card is expected on this kernel.
- REA decompilation (P2) continues as reference work; highest-value targets now:
  OpenCL runtime (OpenCL.dll / libqcdx12arm64wslum.so) and video encode/decode
  (qcvidenc MFTs, qcav1e8380.mbn) — the feature gaps vs. the working open stack.
- P1 collector still pending user execution under Windows 11.