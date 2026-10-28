# REA notes — libqcdx12arm64wslum.so (WSL D3D12 UMD)

Session 4, 2026-10-28. REA/Ghidra 12.1.4, ARM64 ELF, image base 0x100000.
SHA-256 f9fe6e3f93e320fc92b0b057c68d730ce58833248392dafec354b9ca17576cb6.
Source: tmp/06-driverstore-active/qcdx8380.inf_arm64_97b66cecb1490986/ (v31.0.152.1, 2026-05-23).
Analysis snapshot: analysis/rea-snapshots/wslum-snapshot.bin (reopen with same
path + profile to reuse the analysis DB).

## Identity
- Full D3D12 **user-mode driver** (WDDM DDI form), packaged as a Linux ELF (.so)
  for WSL. It does NOT touch /dev/* or ioctl directly — 17,000+ strings show the
  WDDM interface (D3D12DDI_*), DXGI IIDs, GUID_DXGKDDI_POWER_CLOCK*. In WSL the
  dxg para-virtual kernel layer (Microsoft side, /dev/dxg via glibc D3D12 loader)
  is the kernel counterpart.
- 16,243 procedures, 13,457 defined strings (~6.7 MB).

## Backend selection
- Contains a complete **A7x gen7 HW backend**: `A7xFactory::Create(DxAdapter)`,
  `A7xDevice`, `A7xBinLibInterface`, `A7xOverrideHwCaps` — plus an
  **A8x backend** (`A8xDevice`, `A8xBinLibInterface`) — generation beyond
  X1-85 shipped in the same binary.
- `A7xInit(P21DxHwFactoryCreateData)` @ 0x2f2910 (thunk at 0x281c20): creates
  A7xFactory, fills DXHW Caps blob; chip-revision switch on 32-bit id:
  `0x60c312` → caps 0x180; range `0x60c510`–`0x60c520` (0x60c510/11/12/520)
  → caps 0x300; fallback 0x400000004 / 4. (These are HW revision encodings,
  not the ACPI/DT 43050c01 id — worth mapping later.)

## Compiler interface (QNGC)
- QNGC = Qualcomm Next-Gen Compiler DDI: `D3D12OpenCompilerDDI`,
  `DxCompilerPlugin::Create` (D3D12DDIARG_COMPILER_OPEN_DDI),
  `DxCompiler::LinkPipeline`, `QNGC_LINKPIPELINE_RESULT`,
  `QNGC_COMPILECOMPUTEPIPELINE`, mesh pipeline link support.
- Compiler core is a separate artifact loaded at runtime:
  - `DxAdapter::LoadCompilerDll` @ 0x29209c:
    `Win32LoadLibraryWithAsicIdFromCurrDir("qcgpuarm64compilercore", 0)`
    fallback `"qcdxarm64compiler", 1`.
  - Compiler-plugin path `DxCompilerPluginAdapter::LoadCompilerDll` @ 0x2965e4
    loads `qcgpuarm64compilercore` from current dir.
  - Package ships `qcgpuarm64compilercore.so` (and .DLL variants per arch).
- Rich `QCC_METADATA_ADRENO_*` shader metadata deserialization:
  descriptor groups, shader binaries, register usage per fiber,
  cbuffer/sampler/texture/UAV usage, binning specifics, A6X/*A7X metadata.

## OpenCL exposure (gap-relevant)
- NO public cl* client API in this UMD. OpenCL surfaces only as D3D12
  **meta-commands**: `DxMetaCmdGEMMOpenCL`, `DxMetaCmdProgramCLKernelMgr`
  (`FillQNGCMetadata`, `QNGC_COMPILECOMPUTEPIPELINE`),
  `DxMetaCmdGEMMOpenCL::EnumerateMetaCommand*`. So Windows OpenCL on Adreno
  rides the separate OpenCL.dll / OpenCL_adreno.dll stack in the package, not
  the D3D12 UMD. Linux OpenCL path research (todo Phase 4) should target
  OpenCL_adreno.dll + libgsluser.dll rather than this .so.

## Video decode (feature surface)
- D3D12 video decode profiles present: JPEG_VLD 420/422/444, MJPEG,
  AV1_VLD_12BIT_PROFILE2_420 (+ more in LD_* list), plus AV1/H264/HEVC encode
  MFT DLLs shipped separately (qcvidenc*mft*).
  → turnip/freedreno parity gap is real: Windows stack exposes these via
  D3D12 video + MFTs on top of firmware (qcav1e8380.mbn etc.).

## Useful entry symbols for follow-up
- `_Z7A7xInitP21DxHwFactoryCreateData` @ 0x2f2910
- `_ZN9DxAdapter15LoadCompilerDllEv` @ 0x29209c
- `_ZN23DxCompilerPluginAdapter15LoadCompilerDllEv` @ 0x2965e4
- `OpenAdapter12` export; `D3D12OpenCompilerDDI`
- String `GMU_XOCLK` / `GMU_GMUCLK` (clock gating labels) — xref later for
  GMU freq domain references.

# qcdx12arm64xum.dll (native Windows D3D12 UMD, ARM64 PE, 9.9 MB)

Session 4, 2026-10-28. REA/Ghidra (2G heap, succeeded — 7,260 procs, 8,066
strings, image base 0x180000000). SHA-256
8bd195f04beef263e4f79d91474f20316701a1e7e6c4268e7d192922914ef5e0.
Snapshot: analysis/rea-snapshots/umd-native-snapshot.bin.

- Symbols are stripped (no C++ itanium names in .rdata), unlike the WSL .so
  which is full of `Dx*`/`A7x*` names — but structure is identical:
  - exports/uses `D3D12OpenCompilerDDI` (same compiler-plugin DDI entry)
  - compiler core = `qcgpuarm64xcompilercore` (arm64x variant of the WSL .so's
    `qcgpuarm64compilercore`, loaded the same way)
  - A7x binlib source path string …adreno-core/sharedlibs/binlib/hwl/a7x/
    a7xbinlib.cpp; GMU_GMUCLK/GMU_XOCLK clock labels
  - Shader input pipeline is DXIL: dxil.dll / dxilconv.dll references,
    dxilBitcode/dxilBitcodeSize strings — D3D12 runtime DXIL goes through the
    Qualcomm compiler core to Adreno ISA (closed source; no SPIR-V here).
- Confirms: WSL .so and native .dll are the same generation of UMD; only the
  kernel-facing layer and symbol exposure differ.

# INF/INI/registry decode (driver template + runtime state)

- qcdx8380.inf (v31.0.152.1): Display class, DriverVer 05/23/2026.
  - Hardware matches ACPI\VEN_QCOM&DEV_0C36 (QC_Device_X185) per REV byte:
    QCDX_Inst_Base covers REV_004x…008C incl. **REV_0088** (our device);
    REV-keyed variants choose per-bin AcpiBaseFile: QCDX_Inst_Base_63/68/110/
    150 (qcdxkmbase8380_63/68/110/150.bin). Purwa variants (X145, DEV_0D17
    component) use qcdxkmbase8380_pa*.bin + qcdxkm8380.sys (same binary).
  - Service: QCDX kernel driver = qcdxkm8380.sys, demand start.
  - UMD plumbing (QCDX_SoftwareDeviceSettings): InstalledDisplayDrivers =
    qcdx11arm64xum + qcdx12arm64xum; UserModeDriverNameWsl =
    libqcdx12arm64wslum.so; VulkanDriverName = qcvk_icd_arm64x.json;
    **OpenCLDriverName = OpenCL_adreno.dll**; ContentProtection =
    qchdcpumd8380.dll; GpuStatistics = qcdxsdarm64x.dll;
    HwQueuedRenderPacketGroupLimitPerNode = 4.
  - Component QDCMLibrary (SWC_QDCM8380) + QCDPPSLibrary (qcdpps8380 = display
    post-processing) — Qualcomm color/display-management user components.
- The .ini files in FileRepository are driver-store file manifests
  ([DriverPackage]/[Files]: name,size,ts,hash) — not registry templates.
- Runtime registry (collector export):
  - Class 0000: DriverVersion 31.0.152.1, MatchingDeviceId …DEV_0C36…REV_0088,
    AcpiBaseFile = qcdxkmbase8380.bin (no suffix — REV_0088 bin),
    **AcpiBaseBootCount = 0x36**, FeatureScore 0xd1, Vulkan/OpenCL paths point
    at the DriverStore package dir (97b66cecb1490986).
  - Enum node: Device Parameters with Interrupt Management Affinity Policy +
    DISPLAY_ACPI_INFO; components QDCMLibrary + QCDPPSLibrary registered.

# Cross-reference: Windows artifacts vs Linux stock stack (this machine)

- GPU identity: ACPI 0C36 REV_0088 → KMD family 0x88 (gen7). Linux DT
  compatible qcom,adreno-43050c01 (a740) with X1-85 — 43050c01 is the DT-side
  chip id; the 0x88/0x9a family ids and 0x60cXXX revision encodings are the
  Windows-internal encodings for the same gen7 hardware.
- GMU firmware: Windows = WMI blob/KMD-embedded (load regions 0x40030000);
  Linux = qcom/gen70500_gmu.bin + gen70500_sqe.fw, GMU fw v4.3.17 confirmed
  loaded (session 3 dmesg). Same GMU CSRAM region convention.
- Zap shader: qcdxkmsuc8380.mbn shared name both sides (12,088 B sibling
  builds); Linux loads it from DT location microsoft/Denali.
- PM4: same instruction stream concept; Windows ships user-side PM4 checker
  (gsl_pm4cc_a6x/a7x/a8x). Linux turnip generates PM4 directly; a740/gen7
  support upstream matches A7x here.
- Video: Windows exposes JPEG/MJPEG/AV1-12bit decode (D3D12) + AV1/H264/HEVC
  encode (MFTs + qcav1e8380.mbn via Venus HFI in KMD). Linux a740 turnip/
  freedreno do not expose these today — this stack is the reference corpus if
  video APIs are ever chased.
- OpenCL: Windows = OpenCL_adreno.dll over libgsluser (KGSL ABI) + KMD.
  Linux has no OpenCL for Adreno in stock stack; the WSL .so meta-commands
  and this lib pair are the reference for any CL exploration.

# OpenCL stack deep dive (session 5 — optional work CLOSE-OUT)

Session 5, 2026-10-28. Source binaries: the active driver package in
/run/media/richard/Local Disk/QC-GPU-Collect/qc-gpu-20261028-161216/
06-driverstore-active/qcdx8380.inf_arm64_97b66cecb1490986/ (workspace tmp/
copy removed at close-out).

## OpenCL_adreno.dll (760 KB, ARM64 PE) — CL driver/runtime
- REA pass (2,307 procs, sha 30ba1d32..., snapshot opencl-runtime-snapshot.bin).
- dlopens **libgsluser.dll** at runtime ("failed to open GSL library",
  "failed to load the GSL jump table") — no static import; builds a GSL
  jump table from the KGGL-ABI exports surveyed in session 4c.
- Internal driver API surface: **qCLDrvAPI_*** wrapper functions (478 cl*
  symbols incl. clCreateBuffer/SubBuffer/BufferFromImageQCOM,
  clCreateCommandQueue, clEnqueue*, clGetDevice*, QCOM extensions
  clCreateEventFromEGLSyncKHR, clGetDeviceImageInfoQCOM).

## Full Windows OpenCL stack (dependency chain, fully mapped)
1. OpenCL.dll (534 KB) — Khronos ICD loader.
2. OpenCL_adreno.dll — CL driver/runtime (this).
3. libgsluser.dll — GSL/KGSL-ABI user lib → D3DKMT → qcdxkm8380.sys (KMD).
4. **qcclarm64xcompiler.dll (51 MB) — the OpenCL C compiler**: strings prove a
   Qualcomm internal **LLVM/Clang fork** (gfxcompiler\shadercompiler\llvm\
   tools\clang\lib\cl_interface\cl_compiler_if.cpp — their "cl_interface"
   frontend glue on top of their in-tree LLVM).
5. kcl.dll (31 MB) — NOT a compiler: pre-baked OpenCL kernel library for DNN
   ops (78 exports: KclCreateConvolution[FBw'd]/Gemm/LSTM/MultiHeadAttn/
   LayerNorm/GroupNorm kernels etc.) — the Neural-LE path.
6. kernelmanager.dll (352 KB) — program/kernel manager companion.

## Linux-side implications
- The KGSL-ABI link means the CL driver talks the SAME ioctl surface Linux's
  /dev/kgsl-3d exposes (session-4c conclusion). A hypothetical CL path on
  Linux would need: ICD loader (ocl-icd) + this GSL-family user lib (or
  Rusticl on freedreno, in Mesa) + an OpenCL C→Adreno ISA compiler
  (Rusticl uses Mesa NIR; Qualcomm's own compiler closed/fork-LLVM here;
  Qualcomm has been working on open Linux Adreno OpenCL/LLVM efforts —
  not verified by web search in this session, flagged for future check).
- Stock Ubuntu 26.04 on this machine: no clinfo/OpenCL ICD for Adreno found
  (Phase 5); freedreno GL/turnip Vulkan remain the supported acceleration
  paths. Video APIs (encode/decode) likewise undocumented in Linux stack.

# qcdxkm8380.sys (Windows KMD, ARM64 PE)

Session 4, 2026-10-28. REA/Ghidra 12.1.4, image base 0x140000000, 4,706 procs,
7,405 strings. SHA-256 93bd0e0a4625273529159d398c198d535c977ff29b064d5c628f1111d49701c7.
Snapshot: analysis/rea-snapshots/kmd8380-snapshot.bin.

## Identity / model
- WDDM kernel-mode miniport on **WDF + DMF** (Dmf_IoctlHandler.c strings), NOT
  a KGSL chardev — no KGSL/IOCTL chardev surface, no zap-shader concepts.
  Kernel counterpart is `\Device\DxgKrnl`. Build tree string:
  `X:\qcdksrc\rel\10.9\...` (Qualcomm internal source tree, rel 10.9).
- KMD embeds the **Venus video engine (VED)** driver: Ved2Av1e*, Ved* HFI
  sessions (`HFI_PROP_DX_ARCH_VERSION/PROFILE/LEVEL/TIER/FRAME_RATE`), family
  "Venus"/"Hamoa" gates — AV1/H264/HEVC encode runs inside the graphics KMD,
  using qcav1e8380.mbn firmware.

## Linux-facing reference facts
- `GPU_RPMH_CPRF` — RPMh CPRF rail/clock voting (Linux: rpmh GPU CX/GX rails).
- `ICBID_MASTER_GFX3D`, `ICBID_SLAVE_GFX3D_CFG`, `ICBID_SLAVE_EBI1` — interconnect
  IDs, counterparts of Linux x1e80100 icc paths gfx3d / gfx3d_cfg.
- QTIMER timestamps: "QTimer freq", VedCalibrateEngineClock — Windows GPU
  timestamps come from Qualcomm QTimer.
- Debug leftovers: `\DosDevices\C:\data\test\...`, `QdssTrace.bin`,
  `sampleap.mbn` test fw load (`C:\Data\Test\bin\sampleap.mbn`).

## GMU firmware load (KEY)
- FUN_1404a1250 (string "GmuFwFile"): GMU fw obtained via WMI/UEFI callback
  (guard_check_icall with L"GmuFwFile") returning the firmware blob — under
  Windows the GMU fw rides with the platform, not a filesystem path.
- Fallback: **embedded firmware data blobs in the KMD** keyed by chip family:
  - family 0x88 → blob @ DAT_14022c480, load word 0x40030012, len 0x3415 words
  - family 0x9a → blob @ UNK_14021f930, load word 0x40060003, len 0x32bd words
  - 0x40030000/0x40060000 are GMU csram/fw regions — matches Linux gmu fw load
    region 0x40030000.
- Family ids 0x88/0x9a are Qualcomm internal gen7/gen8 encodings (not 0x43050c01);
  0x88 = gen7 (X185), 0x9a appears in A8x paths.

# libgsluser.dll (GSL user library, ARM64 PE, 7.5 MB)

Session 4, 2026-10-28. Ghidra open OOM'd at 2G heap (RTTI analyzer) — first
pass done via PE export-table parse + strings instead. SHA-256
6dbf7a714d91f9dbe344980e6a050ef4657796c772726eba8221fefbd6e47a57.
RE-run REA next session: server env GHIDRA_HEADLESS_MAXMEM=6G now set
(opencode.jsonc rea environment; needs MCP restart / new session).

## Exports / ABI (229 exports)
- Full KGSL-mirror GSL API: gsl_library/version/open/close, gsl_device_open/
  close/getinfo/ext/getfeatures/get_gpu_clock/getirqcntrbase/waitirq/
  setpowerstate/dumpstate, gsl_context_create/destroy/bindgmemshadow/
  setbinbaseoffset, gsl_command_issueib[_sync|_timeline_sync|_with_alloc_list]/
  insertfence/checktimestamp/waittimestamp/readtimestamp/freememontimestamp,
  gsl_memory_alloc_pure[_64]/phys/virt/mmap/munmap/cacheoperation/copy/set/
  read/write/import/export/bind, gsl_syncobj_* (incl. win32 fd/handle create),
  gsl_timeline_*, gsl_perfcounter_select/read/query (+trylock/unlock),
  gsl_aux_command, gsl_get_device_file_path, gsl_get_device_drm_properties,
  gsl_present, gsl_set_constraint, gsl_set_pwrctrl, os_alloc_physical etc.

## Kernel surface
- Internal fns literally named kgsl_sharedmem_read/write/set — same KGSL lineage
  as Linux kernel driver code; ERROR strings match kgsl_sharedmem_* semantics.
- Kernel access is through D3DKMT (D3DKMTCreateDevice/DestroyDevice) +
  CreateDXGIFactory/dxgi.dll; `p_gsl_ioctl_ops` is a pluggable ops table
  (ioctl_sharedmem_external_alloc/export/import, ioctl_get_win32_nthandle_from_name)
  → the SAME library targets KGSL ioctls on Linux and D3DKMT on Windows.
  `gsl_get_device_drm_properties` exposes DRM-style properties from the KMD.
- Source tree: C:\Users\divydivy\adrenoSC-promo\gsl\user\src\gsl_pm4cc_a6x.c /
  a7x / a8x (rules) — PM4 command checker (validation) shipped in user lib for
  A6x/A7x/**A8x**; companion kcl.dll / kernelmanager.dll in package.

## Cross-lib conclusion (project-relevant)
- The windows Adreno stack is a straight KGSL-ABI port: GSL user lib over
  D3DKMT, KMD over WDF. For a Linux **OpenCL** path, OpenCL_adreno.dll would
  link this libgsluser → on Linux the equivalent is KGSL ioctls on
  /dev/kgsl-3d via libgsl — i.e. the OpenCL/Adreno runtime could be studied
  for portability, but native Linux already has Mesa; value = reference only.

# Firmware blob mapping (session 4, shell-level)

- qcdxkmsuc8380.mbn (win pkg, 12,088 B) vs linux Denali
  /lib/firmware/qcom/x1e80100/microsoft/Denali/qcdxkmsuc8380.mbn: SAME size
  and ELF32-arm header type, DIFFERENT sha (59e8d72e... vs f2f6dd1d...) —
  sibling build of the same zap image; Linux one is active and works.
- qcdxkmbase8380*.bin (125 KB, header "base_8380" + ENGS magic): SEC/protection
  metadata image (PT tables: CryptoSecurePT, GraphicsGmuPT, Video*/Mdp PT,
  SecureCarveoutSize). Windows-only KMD base; NOT the Linux gmu/sqe firmware.
- GMU/SQE firmware: NOT shipped as files on Windows — delivered via WMI/UEFI
  "GmuFwFile" blob or KMD-embedded blobs (families 0x88/0x9a at 0x40030000/
  0x40060000). Linux equivalents: qcom/gen70500_gmu.bin (81 KB) +
  qcom/gen70500_sqe.fw (77 KB) — confirmed present and loaded on this machine.
- Per-speed-bin variants _63/_68/_110/_150 (+_pa_*): bins for different X1E
  SKUs (gpu speed-bin from DT; Linux DT zap does not need them — single
  qcdxkmsuc8380.mbn covers it).