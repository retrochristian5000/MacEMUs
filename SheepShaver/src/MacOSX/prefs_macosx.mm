/*
 *	$Id$
 *
 *	prefs_macosx.mm - Enables access to SheepShaver preferences while
 *                    SheepShaver is running (on Mac OS X).
 *
 *  Copyright (C) 2007 Alexei Svitkine
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */


#include "sysdeps.h"

// The _UINT64 define is needed to guard against a typedef mismatch with Snow Leopard headers.
#define _UINT64

#include <Cocoa/Cocoa.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include "boot_debugger.h"
#include "VMSettingsController.h"

#ifdef USE_SDL_VIDEO
#include <SDL.h>
#else
#define SDL_VERSION_ATLEAST(a,b,c)	0
#endif

@interface SheepShaverMain : NSObject
{
	NSArray *nibObjects;
	NSWindow *prefsWindow;
}
@end

@implementation SheepShaverMain


- (NSArray*) loadPrefsNibFile
{
	NSNib *nib = [[NSNib alloc] initWithNibNamed:@"VMSettingsWindow" bundle:nil];
	NSArray *objects = nil;
 
	if (![nib instantiateNibWithOwner:[VMSettingsController sharedInstance] topLevelObjects:&objects]) {
		NSLog(@"Could not load Prefs NIB file!\n");
		return nil;
	}

	NSLog(@"%lu objects loaded\n", [objects count]);

	// Release the raw nib data.
	[nib release];
 
	// Release the top-level objects so that they are just owned by the array.
	[objects makeObjectsPerformSelector:@selector(release)];

	prefsWindow = nil;
 	for (int i = 0; i < [objects count]; i++) {
		NSObject *object = [objects objectAtIndex:i];
		NSLog(@"Got %@", object);

		if ([object isKindOfClass:[NSWindow class]]) {
			prefsWindow = (NSWindow *) object;
			break;
		}
	}

	if (prefsWindow == nil) {
		NSLog(@"Could not find NSWindow in Prefs NIB file!\n");
		return nil;
	}

	return objects;
}


- (void) openPreferences:(id)sender
{
	NSAutoreleasePool *pool;

	if (nibObjects == nil) {
		nibObjects = [self loadPrefsNibFile];
		if (nibObjects == nil)
			return;
		[nibObjects retain];
	}

	pool = [[NSAutoreleasePool alloc] init];
	[[VMSettingsController sharedInstance] setupGUI];
	[NSApp runModalForWindow:prefsWindow];
	[pool release];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	return YES;
}

@end

/*
 *  Initialization
 */

void prefs_init(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#if SDL_VERSION_ATLEAST(2,0,0)
	// No menu necessarily exists in the SDL-independent settings path.
	NSMenu *menu = [NSApp mainMenu];
	if (menu && [menu numberOfItems] > 0) {
		NSMenu *appMenu = [[menu itemAtIndex:0] submenu];
		for (NSMenuItem *sub_item in [appMenu itemArray]) {
			if ([sub_item.title isEqualToString:@"Preferences…"] ||
			    [sub_item.title isEqualToString:@"Settings…"]) {
				sub_item.target = [[SheepShaverMain alloc] init];
				sub_item.action = @selector(openPreferences:);
				break;
			}
		}
	}
#else
	NSMenu *appMenu;
	NSMenuItem *menuItem;

	appMenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
	menuItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..." action:@selector(openPreferences:) keyEquivalent:@","];
	[appMenu insertItem:menuItem atIndex:2];
	[appMenu insertItem:[NSMenuItem separatorItem] atIndex:3];
	[menuItem release];
	
	[NSApp setDelegate:[[SheepShaverMain alloc] init]];
#endif
	[pool release];
}

/*
 *  Deinitialization
 */

void prefs_exit(void)
{
}

// Load the Cocoa configuration UI without requiring SDL or a guest ROM.
bool ShowSheepShaverSettings(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[NSApplication sharedApplication];
	VMSettingsController *controller = [VMSettingsController sharedInstance];
	NSWindow *window = [controller window];
	if (!window) {
		NSLog(@"SheepShaver: could not load VMSettingsWindow.nib");
		[pool release];
		return false;
	}
	[controller setupGUI];
	[window center];
	[window makeKeyAndOrderFront:nil];
	[NSApp activateIgnoringOtherApps:YES];
	[NSApp runModalForWindow:window];
	[pool release];
	return true;
}


/*
 * Separate, read-only PPC boot debugger window.
 *
 * The guest display remains SDL-owned; this Cocoa window never pauses the
 * emulator, reads live guest memory, or dispatches from a signal handler.
 * Bounded ASCII diagnostics are queued under a short try-lock, then consumed
 * on the macOS main thread (from the existing SDL/interrupt event pump).
 */
enum { BOOT_DEBUG_LINES = 128, BOOT_DEBUG_LINE_LEN = 192 };
static pthread_mutex_t boot_debug_lock = PTHREAD_MUTEX_INITIALIZER;
static char boot_debug_lines[BOOT_DEBUG_LINES][BOOT_DEBUG_LINE_LEN];
static unsigned boot_debug_write = 0, boot_debug_read = 0;
static int boot_debug_enabled = 1; // collect early startup stages before prefs load
static NSWindow *boot_debug_window = nil;
static NSTextView *boot_debug_text = nil;

extern "C" void SheepShaverBootDebuggerLog(const char *line)
{
    if (!boot_debug_enabled || !line)
        return;
    // Emulation and signal-handler paths must never wait on the UI.
    if (pthread_mutex_trylock(&boot_debug_lock) != 0)
        return;
    snprintf(boot_debug_lines[boot_debug_write % BOOT_DEBUG_LINES],
             BOOT_DEBUG_LINE_LEN, "%s", line);
    ++boot_debug_write;
    if (boot_debug_write - boot_debug_read > BOOT_DEBUG_LINES)
        boot_debug_read = boot_debug_write - BOOT_DEBUG_LINES;
    pthread_mutex_unlock(&boot_debug_lock);
}

extern "C" void SheepShaverBootDebuggerCPU(uint32_t pc, uint32_t opcode,
                                            uint32_t msr)
{
    char line[BOOT_DEBUG_LINE_LEN];
    if (opcode) {
        snprintf(line, sizeof(line), "[PPC sample] PC=%08x opcode=%08x MSR=%08x",
                 (unsigned)pc, (unsigned)opcode, (unsigned)msr);
    } else {
        snprintf(line, sizeof(line), "[JIT sample] PC=%08x MSR=%08x (opcode not sampled)",
                 (unsigned)pc, (unsigned)msr);
    }
    SheepShaverBootDebuggerLog(line);
}

extern "C" void SheepShaverBootDebuggerPump(void)
{
    if (!boot_debug_enabled || !boot_debug_window || !boot_debug_text ||
        ![NSThread isMainThread])
        return;

    char pending[BOOT_DEBUG_LINES][BOOT_DEBUG_LINE_LEN];
    unsigned count = 0;
    if (pthread_mutex_trylock(&boot_debug_lock) != 0)
        return;
    while (boot_debug_read != boot_debug_write && count < BOOT_DEBUG_LINES) {
        snprintf(pending[count], BOOT_DEBUG_LINE_LEN, "%s",
                 boot_debug_lines[boot_debug_read % BOOT_DEBUG_LINES]);
        ++boot_debug_read;
        ++count;
    }
    pthread_mutex_unlock(&boot_debug_lock);
    if (!count)
        return;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableString *combined = [NSMutableString stringWithString:[boot_debug_text string]];
    for (unsigned i = 0; i < count; ++i) {
        NSString *line = [NSString stringWithUTF8String:pending[i]];
        if (line)
            [combined appendFormat:@"%@\n", line];
    }
    // Do not accumulate unbounded text during an instruction loop or hang.
    if ([combined length] > 30000)
        [combined deleteCharactersInRange:NSMakeRange(0, [combined length] - 24000)];
    [boot_debug_text setString:combined];
    [boot_debug_text scrollRangeToVisible:NSMakeRange([[boot_debug_text string] length], 0)];
    [boot_debug_window displayIfNeeded];
    [pool release];
}

extern "C" void SheepShaverBootDebuggerOpen(int enabled)
{
    // Called on the main thread after preference initialization, not by PPC.
    boot_debug_enabled = enabled != 0;
    if (!boot_debug_enabled) {
        if (boot_debug_window)
            [boot_debug_window orderOut:nil];
        return;
    }
    if (boot_debug_window) {
        [boot_debug_window orderFront:nil];
        SheepShaverBootDebuggerPump();
        return;
    }
    if (![NSThread isMainThread])
        return;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    const NSRect frame = NSMakeRect(120, 140, 740, 360);
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask |
                       NSMiniaturizableWindowMask | NSResizableWindowMask;
    boot_debug_window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [boot_debug_window setTitle:@"SheepShaver Boot Debugger"];
    [boot_debug_window setReleasedWhenClosed:NO];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
        [[boot_debug_window contentView] bounds]];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];

    boot_debug_text = [[NSTextView alloc] initWithFrame:[[scroll contentView] bounds]];
    [boot_debug_text setEditable:NO];
    [boot_debug_text setSelectable:YES];
    [boot_debug_text setRichText:NO];
    [boot_debug_text setFont:[NSFont userFixedPitchFontOfSize:12.0]];
    [boot_debug_text setVerticallyResizable:YES];
    [boot_debug_text setHorizontallyResizable:NO];
    [boot_debug_text setAutoresizingMask:NSViewWidthSizable];
    [scroll setDocumentView:boot_debug_text];
    [[boot_debug_window contentView] addSubview:scroll];
    [boot_debug_text release]; // NSScrollView owns document view
    [scroll release];
    [boot_debug_window setFrameAutosaveName:@"SheepShaverBootDebugger"];
    [boot_debug_window orderFront:nil]; // do not steal keyboard focus from SDL
    SheepShaverBootDebuggerLog(
        "[debugger] Boot diagnostics enabled; PPC samples are periodic, not single-step.");
    SheepShaverBootDebuggerPump();
    [pool release];
}
