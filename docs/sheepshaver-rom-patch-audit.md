# SheepShaver ROM patch audit (Mac OS 9.2.2)

Status: ACTIVE — source review and safe guard repairs. This ledger supplements, not replaces, the original ROM source or the boot debugger.

## Observed ROM evidence

| Datum | Value | Status |
|---|---|---|
| Container | CHRP compressed | User's ROM inspector |
| Container bytes | 2,782,462 | User's ROM inspector |
| Decoded image | 4,194,304 bytes (4 MiB) | User's ROM inspector |
| Identity | NewWorld | User's ROM inspector |
| Legacy `sr_init` search | 0x3101B0–0x3105B0 | SheepShaver source |
| `sr_init` signature | `35 4A FF FC 7D 86 50 2E` | SheepShaver source |
| Relocated signature | +0x3106F8 | User's ROM inspector |
| Failed check | `patch_nanokernel_boot()` | ROM fault trip (line numbers can drift) |
| Candidate context | Unknown on real ROM | Await four overwritten instructions and PVR cross-check |

A relocated pair of instructions **does not** establish that it is safe to overwrite the next two instructions. File container size, decoded ROM size and executable layout are distinct quantities. This is not proof of larger-than-4-MiB decoded ROM.

## What the patcher does

Source of truth: `SheepShaver/src/rom_patches.cpp`, called from `SheepShaver/src/main.cpp::InitAll`. Patches affect a private, decoded in-memory ROM image; the original ROM file is not overwritten.

1. `PatchROM`: classify the ROM, check writable patch-space sentinels, orchestrate mandatory patches, then copy the 68k emulator segment to the extra 1 MiB region.
2. `patch_nanokernel_boot`: rewrite nanokernel boot structures and entry instructions; skip SR/BAT/SDR initialization; replace PVR/SDR1 access, page-table setup, segment-register handling, and early 68k transition paths.
3. `patch_68k_emul`: replace original PPC `twi` entry points, generate host-emulation dispatch stubs, and redirect 68k emulator execution.
4. `patch_nanokernel`: bypass or rewrite virtual-to-physical mapping, exception tables, FPU MSR changes, decrementer updates, RFI-related return logic and page-table accesses.
5. `patch_68k`: replace 68k RESET, machine identity and hardware register accesses, NVRAM/ADB/VIA/timer code, Mac OS resource and driver behavior, system traps and clipboard routes.

These functions are not independent optional modules. Removing an opcode rewrite without replacing its expected hardware/host function can prevent booting, even with PPC32 `mfmsr`, `mtmsr`, `rfi`, and supervisor register support.

### Nanokernel patch policy (experimental)

`patch_nanokernel()` is **skipped by default** (`patchnanokernel=false` in `prefs_items.cpp`), protecting its original PPC MMU, exception-table, FPU/MSR, decrementer, and `rfi` code from that rewrite pass. The legacy pass is retained and can be explicitly selected with a saved preference `patchnanokernel true` or a command-line override. Saved values override compiled defaults.

**Scope guard:** `patch_nanokernel_boot()` still runs beforehand, and `patch_68k_emul()` / `patch_68k()` still modify the decoded ROM for host integration. Thus `patchnanokernel=false` is *not* a fully unpatched Apple ROM execution mode. In particular, the `sr_init` signature check in `patch_nanokernel_boot()` still rejects the user-observed relocated sequence at +0x3106F8 until independent instruction/context validation allows a safe change. This preference cannot by itself get a 9.2.2 ROM past that existing rejection.

Unpatched nanokernel instructions can expose missing emulated hardware functions. Before removing additional patches, implement/verify PPC segment registers, BAT mappings, SDR1, instruction/data address translation, exception delivery and return, FPU state, decrementer timing, and the 68k/PPC handoff. The new preference is for architectural testing, not a 9.2.2 boot success guarantee.

## Defect ledger and repairs

| ID | Finding | Status | Guard |
|---|---|---|---|
| ROM-01 | Signature matching after in-place rewrites could leave a partially modified image on failure | Repaired | `ROMPatchTransaction`: 4 MiB snapshot, automatic rollback, commit after success |
| ROM-02 | `AddSifter` lacked a capacity check for its 32-entry array | Repaired | Reject excess additions and log the reason |
| ROM-03 | Linked ROM resource table traversal trusted unchecked pointers and had an unbounded loop | Repaired | Bounds on map/node/data offsets; finite traversal limit |
| ROM-04 | A-trap table entries could index or point outside decoded ROM, with unguarded patch writes | Repaired | Table/target bounds plus write-span preflight before `patch_68k` writes |
| ROM-05 | Legacy `sr_init` search window excludes +0x3106F8 | Open compatibility investigation | Read-only signature/context/PVR probes; no auto-patching |
| ROM-06 | Many nanokernel/68k patches still depend on hard-coded signatures and offsets | Open architectural investigation | Require version-specific control-flow validation and hardware contracts before eliminating patches |
| ROM-07 | `find_rom_trap` checks ROM offset bounds, but other 68k resource data semantics and offsets remain incompletely validated | Open | Revisit ROM resource spans and side effects if a later patch fails |
| ROM-08 | Historical `patch_nanokernel()` rewrites guest MMU, exception, MSR/FPU, decrementer and `rfi` paths needed for supervisor validation | Disabled by default, experimental | `patchnanokernel=false` preference; explicit `true` restores the unchanged legacy stage |

**Scope limit:** rollback restores decoded ROM bytes and in-patcher resource/sifter cursors, Sony offset, and ROM type on rejection. It does not undo arbitrary external hardware/device side effects or replace full guest exception delivery. The audio sifter capacity limit prevents overflow, but a ROM with more than 32 distinct sifters may need a larger or dynamic table to preserve all sound features.

## Cross-project context

The OpenBIOS fork (`retrochristian5000/PPC-Firmware`) implements PowerPC Open Firmware machine identity, OF memory setup, boot-device selection, `(adler32)`, and Macintosh storage boot paths. These are useful for reconstructing what a guest expects of firmware but **do not verify** SheepShaver's ROM-specific instruction rewrites. Do not conflate OpenBIOS firmware ROM, Apple's Mac OS ROM image, and an OS disk boot loader.

## Validation

Run from the MacEMUs checkout:

```sh
make test-sheepshaver-rom-verification
make check-sheepshaver-rom SHEEPSHAVER_ROM="/path/to/Mac OS ROM"
make sheepshaver
```

Record the CHRP payload offset/size, decoded ROM header fields, `sr_init` candidate context (four words before, four overwritten, four after), PVR companion-match count and the first failure reported by the fault trip. Do not embed Apple ROM bytes in this repository. Structural source checks are not a compiled-application or 9.2.2 boot validation.
