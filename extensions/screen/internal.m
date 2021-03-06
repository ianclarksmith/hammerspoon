#import <Cocoa/Cocoa.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <lauxlib.h>

#define get_screen_arg(L, idx) (__bridge NSScreen*)*((void**)luaL_checkudata(L, idx, "hs.screen"))

static void geom_pushrect(lua_State* L, NSRect rect) {
    lua_newtable(L);
    lua_pushnumber(L, rect.origin.x);    lua_setfield(L, -2, "x");
    lua_pushnumber(L, rect.origin.y);    lua_setfield(L, -2, "y");
    lua_pushnumber(L, rect.size.width);  lua_setfield(L, -2, "w");
    lua_pushnumber(L, rect.size.height); lua_setfield(L, -2, "h");
}

static int screen_frame(lua_State* L) {
    NSScreen* screen = get_screen_arg(L, 1);
    geom_pushrect(L, [screen frame]);
    return 1;
}

static int screen_visibleframe(lua_State* L) {
    NSScreen* screen = get_screen_arg(L, 1);
    geom_pushrect(L, [screen visibleFrame]);
    return 1;
}

/// hs.screen:id(screen) -> number
/// Method
/// Returns a screen's unique ID.
static int screen_id(lua_State* L) {
    NSScreen* screen = get_screen_arg(L, 1);
    lua_pushnumber(L, [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] doubleValue]);
    return 1;
}

/// hs.screen:name(screen) -> string
/// Method
/// Returns the preferred name for the screen set by the manufacturer.
static int screen_name(lua_State* L) {
    NSScreen* screen = get_screen_arg(L, 1);
    CGDirectDisplayID screen_id = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] intValue];

    CFDictionaryRef deviceInfo = IODisplayCreateInfoDictionary(CGDisplayIOServicePort(screen_id), kIODisplayOnlyPreferredName);
    NSDictionary *localizedNames = [(__bridge NSDictionary *)deviceInfo objectForKey:[NSString stringWithUTF8String:kDisplayProductName]];

    if ([localizedNames count])
        lua_pushstring(L, [[localizedNames objectForKey:[[localizedNames allKeys] objectAtIndex:0]] UTF8String]);
    else
        lua_pushnil(L);

    CFRelease(deviceInfo);

    return 1;
}

// CoreGraphics DisplayMode struct used in private APIs
typedef struct {
    uint32_t modeNumber;
    uint32_t flags;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint8_t unknown[170];
    uint16_t freq;
    uint8_t more_unknown[16];
    float density;
} CGSDisplayMode;

// CoreGraphics private APIs with support for scaled (retina) display modes
void CGSGetCurrentDisplayMode(CGDirectDisplayID display, int *modeNum);
void CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID display, int modeNum);
void CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int *nModes);
void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display, int idx, CGSDisplayMode *mode, int length);

/// hs.screen:currentMode() -> table
/// Method
/// Returns a table describing the current screen mode
///
/// Parameters:
///  * None
///
/// Returns:
///  * A table containing the current screen mode. The keys of the table are:
///   * w - A number containing the width of the screen mode in points
///   * h - A number containing the height of the screen mode in points
///   * scale - A number containing the scaling factor of the screen mode (typically `1` for a native mode, `2` for a HiDPI mode)
///   * desc - A string containing a representation of the mode as used in `hs.screen:availableModes()` - e.g. "1920x1080@2x"
static int screen_currentMode(lua_State* L) {
    NSScreen* screen = get_screen_arg(L, 1);
    CGDirectDisplayID screen_id = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] intValue];
    int currentModeNumber;
    CGSGetCurrentDisplayMode(screen_id, &currentModeNumber);
    CGSDisplayMode mode;
    CGSGetDisplayModeDescriptionOfLength(screen_id, currentModeNumber, &mode, sizeof(mode));

    lua_newtable(L);

    lua_pushnumber(L, (double)mode.width);
    lua_setfield(L, -2, "w");

    lua_pushnumber(L, (double)mode.height);
    lua_setfield(L, -2, "h");

    lua_pushnumber(L, (double)mode.density);
    lua_setfield(L, -2, "scale");

    lua_pushstring(L, [[NSString stringWithFormat:@"%dx%d@%.0fx", mode.width, mode.height, mode.density] UTF8String]);
    lua_setfield(L, -2, "desc");

    return 1;
}

/// hs.screen:availableModes() -> table
/// Method
/// Returns a table containing the screen modes supported by the screen. A screen mode is a combination of resolution, scaling factor and colour depth
///
/// Parameters:
///  * None
///
/// Returns:
///  * A table containing the supported screen modes. The keys of the table take the form of "1440x900@2x" (for a HiDPI mode) or "1680x1050@1x" (for a native DPI mode). The values are tables which contain the keys:
///   * w - A number containing the width of the screen mode in points
///   * h - A number containing the height of the screen mode in points
///   * scale - A number containing the scaling factor of the screen mode (typically `1` for a native mode, `2` for a HiDPI mode)
///
/// Notes:
///  * Only 32-bit colour modes are returned. If you really need to know about 16-bit modes, please file an Issue on GitHub
///  * "points" are not necessarily the same as pixels, because they take the scale factor into account (e.g. "1440x900@2x" is a 2880x1800 screen resolution, with a scaling factor of 2, i.e. with HiDPI pixel-doubled rendering enabled), however, they are far more useful to work with than native pixel modes, when a Retina screen is involved. For non-retina screens, points and pixels are equivalent.
static int screen_availableModes(lua_State* L) {
    NSScreen* screen = get_screen_arg(L, 1);
    CGDirectDisplayID screen_id = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] intValue];

    int i, numberOfDisplayModes;
    CGSGetNumberOfDisplayModes(screen_id, &numberOfDisplayModes);

    lua_newtable(L);

    for (i = 0; i < numberOfDisplayModes; i++)
    {
        CGSDisplayMode mode;
        CGSGetDisplayModeDescriptionOfLength(screen_id, i, &mode, sizeof(mode));

        // NSLog(@"Found a mode: %dx%d@%.0fx, %dbit", mode.width, mode.height, mode.density, (mode.depth == 4) ? 32 : 16);
        if (mode.depth == 4) {
            lua_newtable(L);

            lua_pushnumber(L, (double)mode.width);
            lua_setfield(L, -2, "w");

            lua_pushnumber(L, (double)mode.height);
            lua_setfield(L, -2, "h");

            lua_pushnumber(L, (double)mode.density);
            lua_setfield(L, -2, "scale");

            // Now push this mode table into the list-of-modes table
            lua_setfield(L, -2, [[NSString stringWithFormat:@"%dx%d@%.0fx", mode.width, mode.height, mode.density] UTF8String]);
        }
    }

    return 1;
}

/// hs.screen:setMode(width, height, scale) -> boolean
/// Method
/// Sets the screen to a new mode
///
/// Parameters:
///  * width - A number containing the width in points of the new mode
///  * height - A number containing the height in points of the new mode
///  * scale - A number containing the scaling factor of the new mode (typically 1 for native pixel resolutions, 2 for HiDPI/Retina resolutions)
///
/// Returns:
///  * A boolean, true if the requested mode was set, otherwise false
///
/// Notes:
///  * The available widths/heights/scales can be seen in the output of `hs.screen:availableModes()`, however, it should be noted that the CoreGraphics subsystem seems to list more modes for a given screen than it is actually prepared to set, so you may find that seemingly valid modes still return false. It is not currently understood why this is so!
static int screen_setMode(lua_State* L) {
    NSScreen* screen = get_screen_arg(L, 1);
    long width = luaL_checklong(L, 2);
    long height = luaL_checklong(L, 3);
    lua_Number scale = luaL_checknumber(L, 4);
    CGDirectDisplayID screen_id = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] intValue];

    int i, numberOfDisplayModes;
    CGSGetNumberOfDisplayModes(screen_id, &numberOfDisplayModes);

    for (i = 0; i < numberOfDisplayModes; i++) {
        CGSDisplayMode mode;
        CGSGetDisplayModeDescriptionOfLength(screen_id, i, &mode, sizeof(mode));

        if (mode.depth == 4 && mode.width == width && mode.height == height && mode.density == (float)scale) {
            CGDisplayConfigRef config;
            CGBeginDisplayConfiguration(&config);
            CGSConfigureDisplayMode(config, screen_id, i);
            CGError anError = CGCompleteDisplayConfiguration(config, kCGConfigurePermanently);
            if (anError == kCGErrorSuccess) {
                lua_pushboolean(L, true);
            } else {
                NSLog(@"ERROR: CGSConfigureDisplayMode failed: %d", anError);
                lua_pushboolean(L, false);
            }
            return 1;
        }
    }

    lua_pushboolean(L, false);
    return 1;
}

/// hs.screen.setTint(redarray, greenarray, bluearray)
/// Function
/// Set the tint on a screen; experimental.
static int screen_setTint(lua_State* L) {
    lua_len(L, 1); int red_len = lua_tonumber(L, -1);
    lua_len(L, 2); int green_len = lua_tonumber(L, -1);
    lua_len(L, 3); int blue_len = lua_tonumber(L, -1);

    CGGammaValue c_red[red_len];
    CGGammaValue c_green[green_len];
    CGGammaValue c_blue[blue_len];

    lua_pushnil(L);
    while (lua_next(L, 1) != 0) {
        int i = lua_tonumber(L, -2) - 1;
        c_red[i] = lua_tonumber(L, -1);
        lua_pop(L, 1);
    }

    lua_pushnil(L);
    while (lua_next(L, 1) != 0) {
        int i = lua_tonumber(L, -2) - 1;
        c_green[i] = lua_tonumber(L, -1);
        lua_pop(L, 1);
    }

    lua_pushnil(L);
    while (lua_next(L, 1) != 0) {
        int i = lua_tonumber(L, -2) - 1;
        c_blue[i] = lua_tonumber(L, -1);
        lua_pop(L, 1);
    }

    CGSetDisplayTransferByTable(CGMainDisplayID(), red_len, c_red, c_green, c_blue);

    return 0;
}

static int screen_gc(lua_State* L) {
    NSScreen* screen __unused = get_screen_arg(L, 1);
    return 0;
}

static int screen_eq(lua_State* L) {
    NSScreen* screenA = get_screen_arg(L, 1);
    NSScreen* screenB = get_screen_arg(L, 2);
    lua_pushboolean(L, [screenA isEqual: screenB]);
    return 1;
}

void new_screen(lua_State* L, NSScreen* screen) {
    void** screenptr = lua_newuserdata(L, sizeof(NSScreen**));
    *screenptr = (__bridge_retained void*)screen;

    luaL_getmetatable(L, "hs.screen");
    lua_setmetatable(L, -2);
}

/// hs.screen.allScreens() -> screen[]
/// Constructor
/// Returns all the screens there are.
static int screen_allScreens(lua_State* L) {
    lua_newtable(L);

    int i = 1;
    for (NSScreen* screen in [NSScreen screens]) {
        lua_pushnumber(L, i++);
        new_screen(L, screen);
        lua_settable(L, -3);
    }

    return 1;
}

/// hs.screen.mainScreen() -> screen
/// Constructor
/// Returns the 'main' screen, i.e. the one containing the currently focused window.
static int screen_mainScreen(lua_State* L) {
    new_screen(L, [NSScreen mainScreen]);
    return 1;
}

/// hs.screen:setPrimary(screen) -> nil
/// Function
/// Sets the screen to be the primary display (i.e. contain the menubar and dock)
static int screen_setPrimary(lua_State* L) {
    int deltaX, deltaY;

    CGDisplayErr dErr;
    CGDisplayCount maxDisplays = 32;
    CGDisplayCount displayCount, i;
    CGDirectDisplayID  onlineDisplays[maxDisplays];
    CGDisplayConfigRef config;

    NSScreen* screen = get_screen_arg(L, 1);
    CGDirectDisplayID targetDisplay = [[[screen deviceDescription] objectForKey:@"NSScreenNumber"] unsignedIntValue];
    CGDirectDisplayID mainDisplay = CGMainDisplayID();

    if (targetDisplay == mainDisplay)
        return 0;

    dErr = CGGetOnlineDisplayList(maxDisplays, onlineDisplays, &displayCount);
    if (dErr != kCGErrorSuccess) {
        // FIXME: Display some kind of error here
        return 0;
    }

    deltaX = -CGRectGetMinX(CGDisplayBounds(targetDisplay));
    deltaY = -CGRectGetMinY(CGDisplayBounds(targetDisplay));

    CGBeginDisplayConfiguration (&config);

    for (i = 0; i < displayCount; i++) {
        CGDirectDisplayID dID = onlineDisplays[i];

        CGConfigureDisplayOrigin(config, dID,
                                 CGRectGetMinX(CGDisplayBounds(dID)) + deltaX,
                                 CGRectGetMinY(CGDisplayBounds(dID)) + deltaY
                                );
    }

    CGCompleteDisplayConfiguration (config, kCGConfigureForSession);

    return 0;
}

static const luaL_Reg screenlib[] = {
    {"allScreens", screen_allScreens},
    {"mainScreen", screen_mainScreen},
    {"setTint", screen_setTint},
    {"setPrimary", screen_setPrimary},

    {"_frame", screen_frame},
    {"_visibleframe", screen_visibleframe},
    {"id", screen_id},
    {"name", screen_name},
    {"availableModes", screen_availableModes},
    {"currentMode", screen_currentMode},
    {"setMode", screen_setMode},

    {NULL, NULL}
};

int luaopen_hs_screen_internal(lua_State* L) {
    luaL_newlib(L, screenlib);

    if (luaL_newmetatable(L, "hs.screen")) {
        lua_pushvalue(L, -2);
        lua_setfield(L, -2, "__index");

        lua_pushcfunction(L, screen_gc);
        lua_setfield(L, -2, "__gc");

        lua_pushcfunction(L, screen_eq);
        lua_setfield(L, -2, "__eq");
    }
    lua_pop(L, 1);

    return 1;
}
