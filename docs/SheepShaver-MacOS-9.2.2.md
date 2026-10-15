# Mac OS 9.2.x on SheepShaver — compatibility ledger

Status: **EXPERIMENTAL / NOT BOOTABLE IN THIS FORK AS VERIFIED**. This
document carries forward the earlier native Apple Silicon, ROM loader,
and startup diagnostics work; it does not replace their checks.

## Evidence and boundaries

| Item | Status | Evidence / next test |
| --- | --- | --- |
| ARM64 native `SheepShaver.app` | Existing build route; runtime unverified | `make sheepshaver` on Apple Silicon |
| Cocoa configuration before SDL | Integrated; runtime unverified | `make sheepshaver-settings` |
| CHRP New World `Mac OS ROM` decoding | Bounded lzss/prcl parser and 16 MiB container loader implemented; **no real 9.2.2 ROM verified** | Synthetic OldWorld/NewWorld CHRP tests via `make test-sheepshaver-rom-verification` |
| PPC32 BAT/hashed page table/MMU | **Standalone experimental module imported, NOT integrated** | `make test-sheepshaver-92-mmu` |
| CPU MSR, SPRs, DSI/ISI, syscall and privileged exception wiring | Isolated register bridge implemented; live CPU instruction/exception wiring still missing | `make test-sheepshaver-92-registers` |
| New World nanokernel v2 configuration handoff | Missing | KDP/ConfigInfo, ROM entry, exception vector baselines |
| Open Firmware-compatible device tree | Missing | Compare with a 9.2.x golden trace and model data |
| PMU, NVRAM, OpenPIC, PCI, ATA and video device behaviors | Not established | Add only observed requirements |
| Mac OS 9.2.2 installer -> installed system -> Finder -> guest shutdown | NOT TESTED | Use legally obtained ROM/system media and repeatable guest tests |
| Mac OS 9.0.4 regression | Not run here | Retain existing runtime until compatibility is proven |

## Donor source provenance

Public fork: `billcavalieri/macemu`, branch `newworld-boot`, commit
`1204ba0d3028021a19daea0e4bb426a61461f254`, as retrieved
2026-10-15. Imported only `ppc-mmu.hpp` and `ppc-mmu.cpp`,
under the GPL-2.0-or-later headers supplied with those files.
All other boot code and guest firmware in that project is **not imported**.
This component is tested as a host-side C++ unit, not included in
the SheepShaver Xcode target and not enabled at runtime.

Source research: public `OS921-BOOT-PLAN.md` and
`NEWWORLD-BOOT-PLAN.md` on that branch; Ken Hawkins's
2026-08-10 NewSheep report (9.2.1 desktop, 9.2.2 installer).
Those results were observed on different forks and hardware; do not
transfer their boot claims to this repository.

## ROM identity and container verification (2026-10-15)

`DecodeROM` now verifies recognized decoded ROM signatures (Boot TNT,
Alchemy, Zanzibar, Gazelle, Gossamer and NewWorld). It no longer accepts
a CHRP file solely because an unbounded decompressor returned. The
ROM file loader reads complete containers up to 16 MiB rather than
truncating at the decoded 4 MiB length. CHRP header offsets, parcel
linked-list entries, and LZSS output are bounded. Synthetic fixtures
cover OldWorld/plain, NewWorld/CHRP lzss, NewWorld/CHRP prcl, truncated
containers, malformed offsets, and missing ROM signatures.

To inspect a locally owned ROM without booting the emulator, run
`make check-sheepshaver-rom SHEEPSHAVER_ROM="/path/to/Mac OS ROM"`.
The inspector reports container format, recognized decoded ROM identity,
and whether the New World nanokernel entry region is populated. It does
not certify a ROM as version 9.2.2 or verify guest OS compatibility.

**Validation boundary:** a recognized NewWorld ROM is not necessarily
a 9.2.2 ROM, and acceptance is not proof that 9.2.2 will boot. The ROM
nanokernel v2 and device-tree/PowerPC MMU requirements are still missing
in the running emulator. Real Apple ROMs are neither bundled nor
validated by this test.

## Register-state inventory (2026-10-15)

Reference: NXP MPC750 User's Manual. The isolated `ppc-registers.hpp`
uses the same MMU for the register state and address translations.

| Registers | IDs / role | State |
| --- | --- | --- |
| MSR | IR, DR, PR, IP | Shared with experimental MMU |
| SR0–15 | Segment registers (not SPR numbers) | Reads/writes and conservative TLB flush |
| SDR1 | SPR 25 | Hashed page-table base read/write |
| IBAT / DBAT | SPR 528–535 / 536–543 | Independent U/L halves |
| DAR / DSISR | SPR 19 / 18 | DSI fault address and reason |
| SRR0 / SRR1 | SPR 26 / 27 | Exception PC and prior MSR |
| SPRG0–3 | SPR 272–275 | Four scratch latches |
| PVR | SPR 287 | Read-only CPU model value |
| HID, DEC, TB | CPU-model/timebase dependent | Not implemented; no fictitious values |

**Existing runtime obstacle:** In `Unix/main_unix.cpp`, SIGILL still
fabricates `SDR1=0xdead001f` and skips `mtsr`, `mtsrin`, `tlbie`
and some BAT writes. We have not routed those live opcodes to this
bridge: doing that safely also needs physical memory/MMIO translation,
privilege checks, DSI/ISI, RFI and nanokernel boot tests.

Standalone test: `make test-sheepshaver-92-registers`. No Apple ROM
or Mac OS 9.2.2 guest is required, and this is not a claim of boot support.

## Next integration gates

1. Verify the standalone BAT/HTAB/TLB tests on native macOS/ARM64 and Linux;
   check protection, MSR IR/DR split, PTE R/C side effects, and TLB invalidation.
2. Add guest physical memory access hooks for RAM, ROM and MMIO without
   changing existing `Mac2HostAddr()` behavior globally.
3. Connect interpreter fetch/load/store to one guest translator, with
   guest-visible MSR, SDR1, SR and BAT reads/writes, TLB invalidation,
   and correct DSI/ISI/Program exception paths. Keep 9.0.4 as a regression.
4. Implement the New World boot contract (ROM identity, firmware/device
   tree, kernel handoff) from independently checked evidence. Do **not**
   bypass guest ROM checks, skip instructions, or falsify Mac OS version.
5. Compare guest boot traces against a known-good 9.2.x machine/whole-machine
   emulator; fix the earliest divergence before claiming Finder support.

Run: `make test-sheepshaver-92-mmu`. This requires only a C++11 host compiler.
Do not commit copyrighted Apple ROMs, media, or ROM-derived logs.
