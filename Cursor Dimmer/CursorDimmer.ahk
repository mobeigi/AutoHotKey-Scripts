#Requires AutoHotkey v2.0
#SingleInstance Force
DllCall("SetProcessDpiAwarenessContext", "ptr", -4)

; Hotkey:
^!d::ToggleDim()

; ---- Options ----
global enableOverlay := true             ; Show a black overlay on the monitor
global enableBrightnessDimming := true   ; Dim monitor brightness via DDC/CI (if supported)
global dimAlpha := 255                   ; 0..255 overlay opacity (255 = fully opaque)

; Per-monitor state: key = HMONITOR, value = { on, gui, brightSnap }
global monState := Map()

ToggleDim() {
    global monState, enableOverlay, enableBrightnessDimming, dimAlpha

    GetCursorPos(&mx, &my)
    hMon := MonitorFromPoint(mx, my)

    if !monState.Has(hMon)
        monState[hMon] := { on: false, gui: 0, brightSnap: "" }

    st := monState[hMon]

    ; Create overlay GUI on-demand (only if overlay is enabled)
    if (enableOverlay && !st.gui) {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        g.BackColor := "000000"
        g.Show("NoActivate") ; create HWND reliably
        if (dimAlpha < 255)
            WinSetTransparent(dimAlpha, "ahk_id " g.Hwnd)
        g.Hide()
        st.gui := g
    }

    if !st.on {
        if enableBrightnessDimming {
            st.brightSnap := DDC_GetBrightnessSnapshot(hMon) ; "" if unsupported/fails
            if IsObject(st.brightSnap)
                DDC_SetBrightnessToMin(hMon) ; effectively "0%" for that display's supported range
        }

        if enableOverlay {
            GetMonitorRect(hMon, &L, &T, &R, &B)
            st.gui.Move(L, T, R - L, B - T)
            st.gui.Show("NoActivate")
        }

        st.on := true
    } else {
        if enableOverlay && st.gui
            st.gui.Hide()

        if enableBrightnessDimming && IsObject(st.brightSnap) {
            DDC_RestoreBrightnessSnapshot(hMon, st.brightSnap)
            st.brightSnap := ""
        }

        st.on := false
    }
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

; ---------------- DDC/CI brightness (Dxva2) ----------------

DDC_GetBrightnessSnapshot(hMon) {
    pm := DDC_GetPhysicalMonitors(hMon)
    if !IsObject(pm)
        return ""

    snap := []
    try {
        for hPhys in pm.handles {
            bMin := bCur := bMax := 0
            if !DllCall("Dxva2\GetMonitorBrightness", "ptr", hPhys, "uint*", &bMin, "uint*", &bCur, "uint*", &bMax)
                return ""
            snap.Push({ cur: bCur, min: bMin, max: bMax })
        }
        return snap
    } finally {
        DDC_DestroyPhysicalMonitors(pm)
    }
}

DDC_SetBrightnessToMin(hMon) {
    pm := DDC_GetPhysicalMonitors(hMon)
    if !IsObject(pm)
        return false

    ok := true
    try {
        for hPhys in pm.handles {
            bMin := bCur := bMax := 0
            if !DllCall("Dxva2\GetMonitorBrightness", "ptr", hPhys, "uint*", &bMin, "uint*", &bCur, "uint*", &bMax) {
                ok := false
                continue
            }
            if !DllCall("Dxva2\SetMonitorBrightness", "ptr", hPhys, "uint", bMin)
                ok := false
        }
    } finally {
        DDC_DestroyPhysicalMonitors(pm)
    }
    return ok
}

DDC_RestoreBrightnessSnapshot(hMon, snap) {
    if !IsObject(snap) || snap.Length = 0
        return false

    pm := DDC_GetPhysicalMonitors(hMon)
    if !IsObject(pm)
        return false

    ok := true
    try {
        n := (pm.handles.Length < snap.Length) ? pm.handles.Length : snap.Length
        Loop n {
            hPhys := pm.handles[A_Index]
            s := snap[A_Index]

            bMin := bCur := bMax := 0
            if !DllCall("Dxva2\GetMonitorBrightness", "ptr", hPhys, "uint*", &bMin, "uint*", &bCur, "uint*", &bMax) {
                ok := false
                continue
            }

            val := s.cur
            if (val < bMin)
                val := bMin
            else if (val > bMax)
                val := bMax

            if !DllCall("Dxva2\SetMonitorBrightness", "ptr", hPhys, "uint", val)
                ok := false
        }
    } finally {
        DDC_DestroyPhysicalMonitors(pm)
    }
    return ok
}

DDC_GetPhysicalMonitors(hMon) {
    count := 0
    if !DllCall("Dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "ptr", hMon, "uint*", &count) || (count <= 0)
        return ""

    ; PHYSICAL_MONITOR = HANDLE + WCHAR[128]
    structSize := A_PtrSize + 256
    buf := Buffer(count * structSize, 0)

    if !DllCall("Dxva2\GetPhysicalMonitorsFromHMONITOR", "ptr", hMon, "uint", count, "ptr", buf)
        return ""

    handles := []
    off := 0
    Loop count {
        handles.Push(NumGet(buf, off, "ptr"))
        off += structSize
    }
    return { count: count, buf: buf, handles: handles }
}

DDC_DestroyPhysicalMonitors(pm) {
    try DllCall("Dxva2\DestroyPhysicalMonitors", "uint", pm.count, "ptr", pm.buf)
}
