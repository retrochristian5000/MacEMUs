/*
 * SheepShaver macOS boot debugger: diagnostics only, not a CPU break/step API.
 * All calls are thread-safe for normal execution; do not call from signal
 * handlers. The Cocoa window is created/pumped on the emulation UI thread.
 */
#ifndef SHEEPSHAVER_BOOT_DEBUGGER_H
#define SHEEPSHAVER_BOOT_DEBUGGER_H

#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Call after preferences load on the main thread, before guest boot. */
void SheepShaverBootDebuggerOpen(int enabled);
/* Bounded, nonblocking log of boot events and failure diagnostics. */
void SheepShaverBootDebuggerLog(const char *line);
/* Low-rate CPU sampling, opcode=0 means instruction not sampled. */
void SheepShaverBootDebuggerCPU(uint32_t pc, uint32_t opcode, uint32_t msr);
/* Called from the existing Cocoa/SDL main-thread event pump. */
void SheepShaverBootDebuggerPump(void);
/* Fatal guest/startup fault: hold the guest at a modal Cocoa fault trip
 * until the user explicitly clicks Quit SheepShaver. Returns 1 after that
 * choice; returns 0 if debugger is disabled/not running on the UI thread.
 * NEVER invoke from a Unix signal handler; NEVER resume a failed opcode.
 */
int SheepShaverBootDebuggerTrip(const char *reason, uint32_t pc, uint32_t opcode);
#ifdef __cplusplus
}
#endif
#endif
