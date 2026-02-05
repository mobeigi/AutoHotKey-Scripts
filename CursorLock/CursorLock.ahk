#Requires AutoHotkey v2.0
#SingleInstance Force

DllCall("SetProcessDpiAwarenessContext", "ptr", -4)

global g_Locked := false
global g_LockedMon := 0

; Toggle hotkey: Ctrl + Alt + M
^!m::ToggleMonitorCursorLock()

OnExit(*) => UnlockCursor()

ToggleMonitorCursorLock() {
    global g_Locked, g_LockedMon

    if !g_Locked {
        GetCursorPos(&mx, &my)
        hMon := MonitorFromPoint(mx, my)

        GetMonitorRect(hMon, &L, &T, &R, &B)

        if LockCursorToRect(L, T, R, B) {
            g_Locked := true
            g_LockedMon := hMon
            SetTimer(() => ToolTip(), -1200)
        } else {
            SetTimer(() => ToolTip(), -1200)
        }
    } else {
        UnlockCursor()
        g_Locked := false
        g_LockedMon := 0
    }
}

LockCursorToRect(L, T, R, B) {
    ; RECT = left, top, right, bottom (all LONG)
    rc := Buffer(16, 0)
    NumPut("Int", L, rc, 0)
    NumPut("Int", T, rc, 4)
    NumPut("Int", R, rc, 8)
    NumPut("Int", B, rc, 12)
    return !!DllCall("User32\ClipCursor", "ptr", rc, "int")
}

UnlockCursor() {
    ; ClipCursor(NULL) releases the cursor
    DllCall("User32\ClipCursor", "ptr", 0)
}

; ---------------- Cursor-only monitor picking ----------------
GetCursorPos(&x, &y) {
    pt := Buffer(8, 0)
    if !DllCall("User32\GetCursorPos", "ptr", pt)
        throw Error("GetCursorPos failed")
    x := NumGet(pt, 0, "Int")
    y := NumGet(pt, 4, "Int")
}
MonitorFromPoint(x, y) {
    ; MonitorFromPoint(POINT pt, DWORD flags), POINT passed by value.
    ; MONITOR_DEFAULTTONEAREST = 2
    pt64 := (x & 0xFFFFFFFF) | ((y & 0xFFFFFFFF) << 32)
    return DllCall("User32\MonitorFromPoint", "int64", pt64, "uint", 2, "ptr")
}
GetMonitorRect(hMon, &L, &T, &R, &B) {
    mi := Buffer(40, 0) ; MONITORINFO
    NumPut("UInt", 40, mi, 0)
    if !DllCall("User32\GetMonitorInfo", "ptr", hMon, "ptr", mi)
        throw Error("GetMonitorInfo failed")
    L := NumGet(mi,  4, "Int")
    T := NumGet(mi,  8, "Int")
    R := NumGet(mi, 12, "Int")
    B := NumGet(mi, 16, "Int")
}
