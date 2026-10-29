#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()

;@Ahk2Exe-SetName Keychron Profile Monitor
;@Ahk2Exe-SetDescription Keychron Profile Monitor
;@Ahk2Exe-SetMainIcon Keychron.ico

TraySetIcon(A_ScriptDir "\Keychron.ico")

; ---------------------------------------------------------------------------
; Keychron Q6 HE 8K profile monitor
;
; Profile-change HID packet:
; A9 11 02 <profile>
;
; Keyboard reports profiles as:
;   0 = Profile 1
;   1 = Profile 2
;   2 = Profile 3
; ---------------------------------------------------------------------------

global KEYCHRON_VID := "VID_3434"
global KEYCHRON_PID := "PID_1060"
global USAGE_PAGE   := 0xFF60
global USAGE        := 0x61

global ProfileNames := Map(
    0, "Default",
    1, "FPS Gaming",
    2, "Gamepad"
)

global LastProfile := -1
global PendingProfile := -1
global ProfileDebounceMs := 300
global NotificationWasShown := false
global DeviceCache := Map()

; Register the WM_INPUT handler before registering the device.
OnMessage(0x00FF, RawInputHandler)

RegisterKeychronRawInput()

; ---------------------------------------------------------------------------
; Register the Keychron vendor-defined HID collection with Windows Raw Input.
; ---------------------------------------------------------------------------

RegisterKeychronRawInput()
{
    global USAGE_PAGE, USAGE

    ; RAWINPUTDEVICE structure:
    ;
    ; USHORT usUsagePage  offset 0
    ; USHORT usUsage      offset 2
    ; DWORD  dwFlags      offset 4
    ; HWND   hwndTarget   offset 8

    ridSize := 8 + A_PtrSize
    rid := Buffer(ridSize, 0)

    NumPut("UShort", USAGE_PAGE, rid, 0)
    NumPut("UShort", USAGE, rid, 2)

    ; RIDEV_INPUTSINK:
    ; Receive input even when this script is not focused.
    NumPut("UInt", 0x00000100, rid, 4)
    NumPut("Ptr", A_ScriptHwnd, rid, 8)

    success := DllCall(
        "RegisterRawInputDevices",
        "Ptr", rid.Ptr,
        "UInt", 1,
        "UInt", rid.Size,
        "Int"
    )

    if !success {
        errorCode := A_LastError

        MsgBox(
            "Failed to register the Keychron HID collection.`n`n"
            . "Windows error: " errorCode,
            "Keychron profile monitor",
            "Iconx"
        )

        ExitApp()
    }
}

; ---------------------------------------------------------------------------
; Handle WM_INPUT messages.
; ---------------------------------------------------------------------------

RawInputHandler(wParam, lParam, msg, hwnd)
{
    static RID_INPUT   := 0x10000003
    static RIM_TYPEHID := 2
    static HeaderSize  := 8 + (2 * A_PtrSize)

    ; First call determines the required buffer size.
    sizeBuffer := Buffer(4, 0)

    result := DllCall(
        "GetRawInputData",
        "Ptr", lParam,
        "UInt", RID_INPUT,
        "Ptr", 0,
        "Ptr", sizeBuffer.Ptr,
        "UInt", HeaderSize,
        "UInt"
    )

    if result = 0xFFFFFFFF
        return

    requiredSize := NumGet(sizeBuffer, 0, "UInt")

    if requiredSize < HeaderSize
        return

    ; Second call retrieves the Raw Input data.
    raw := Buffer(requiredSize, 0)
    NumPut("UInt", requiredSize, sizeBuffer, 0)

    result := DllCall(
        "GetRawInputData",
        "Ptr", lParam,
        "UInt", RID_INPUT,
        "Ptr", raw.Ptr,
        "Ptr", sizeBuffer.Ptr,
        "UInt", HeaderSize,
        "UInt"
    )

    if result = 0xFFFFFFFF
        return

    ; RAWINPUTHEADER.dwType
    inputType := NumGet(raw, 0, "UInt")

    if inputType != RIM_TYPEHID
        return

    ; RAWINPUTHEADER.hDevice
    deviceHandle := NumGet(raw, 8, "Ptr")

    if !IsKeychronDevice(deviceHandle)
        return

    ; RAWHID starts immediately after RAWINPUTHEADER:
    ;
    ; DWORD dwSizeHid
    ; DWORD dwCount
    ; BYTE  bRawData[]

    hidOffset   := HeaderSize
    reportSize  := NumGet(raw, hidOffset, "UInt")
    reportCount := NumGet(raw, hidOffset + 4, "UInt")
    dataOffset  := hidOffset + 8

    if reportSize < 4 || reportCount < 1
        return

    Loop reportCount {
        reportOffset := dataOffset + ((A_Index - 1) * reportSize)

        if reportOffset + reportSize > raw.Size
            break

        ProcessHidReport(raw, reportOffset, reportSize)
    }
}

; ---------------------------------------------------------------------------
; Look for the profile-change packet:
;
; A9 11 02 00 = Profile 1
; A9 11 02 01 = Profile 2
; A9 11 02 02 = Profile 3
; ---------------------------------------------------------------------------

ProcessHidReport(raw, reportOffset, reportSize)
{
    if reportSize < 4
        return

    ; Windows Raw Input may include a leading report-ID byte.
    ; Searching the report handles either format.

    Loop reportSize - 3 {
        offset := reportOffset + A_Index - 1

        if (
            NumGet(raw, offset, "UChar") = 0xA9
            && NumGet(raw, offset + 1, "UChar") = 0x11
            && NumGet(raw, offset + 2, "UChar") = 0x02
        ) {
            profile := NumGet(raw, offset + 3, "UChar")

            if profile >= 0 && profile <= 2
                HandleProfileChange(profile)

            return
        }
    }
}

; ---------------------------------------------------------------------------
; Display the Windows toast notification.
; ---------------------------------------------------------------------------

HandleProfileChange(profile)
{
    global PendingProfile
    global ProfileDebounceMs
    global NotificationWasShown

    PendingProfile := profile

    ; Cancel the icon-restoration timer belonging to the previous
    ; notification. Otherwise it could fire while the new profile icon
    ; is being prepared.
    SetTimer(RestoreKeychronIcon, 0)

    ; Immediately dismiss the previous notification when movement of the
    ; physical switch is detected.
    if NotificationWasShown {
        ; First try the normal dismissal method.
        TrayTip()

        ; Windows 10/11 does not always honour TrayTip() by itself.
        ; Briefly hiding the tray icon forces the notification to close.
        SetTimer(ForceDismissNotification, -1)
    }

    ; Restart the debounce timer. Only the final physical switch
    ; position will be processed.
    SetTimer(CommitProfileChange, -ProfileDebounceMs)
}

ForceDismissNotification()
{
    global NotificationWasShown

    if !NotificationWasShown
        return

    A_IconHidden := true
    Sleep(200)
    A_IconHidden := false

    NotificationWasShown := false
}

CommitProfileChange()
{
    global PendingProfile, LastProfile, ProfileNames, NotificationWasShown

    profile := PendingProfile

    if profile < 0 || profile > 2
        return

    ; Ignore duplicate notifications.
    if profile = LastProfile
        return

    LastProfile := profile

    ; Keyboard reports 0–2; display profiles as 1–3.
    profileNumber := profile + 1

    name := ProfileNames.Has(profile)
        ? ProfileNames[profile]
        : "Unknown"

    title := name
    message := "Changed to profile " profileNumber

    ; Use a profile-specific notification icon when available.
    profileIcon := A_ScriptDir "\Profile" profileNumber ".ico"

    if FileExist(profileIcon)
        TraySetIcon(profileIcon)
    else
        TraySetIcon(A_ScriptDir "\Keychron.ico")

    ; Allow Windows a moment to register the changed tray icon.
    Sleep(50)

    ; 4  = use the current tray icon
    ; 16 = suppress notification sound
    ; 32 = request the large version of the icon
    TrayTip(
        message,
        title,
        4 | 16 | 32
    )

    NotificationWasShown := true

    ; Restore the normal tray icon shortly afterwards.
    SetTimer(RestoreKeychronIcon, -500)

    OutputDebug(message "`n")

    ; Add profile-specific actions here.
    switch profile {
        case 0:
            ; Run("C:\Scripts\DefaultProfile.ahk")
            return

        case 1:
            ; Run("C:\Scripts\FPSProfile.ahk")
            return

        case 2:
            ; Run("C:\Scripts\GamepadProfile.ahk")
            return
    }
}

RestoreKeychronIcon()
{
    icon := A_ScriptDir "\Keychron.ico"

    if FileExist(icon)
        TraySetIcon(icon)
}

; ---------------------------------------------------------------------------
; Confirm that a Raw Input event belongs to the Keychron Q6 HE 8K.
; ---------------------------------------------------------------------------

IsKeychronDevice(deviceHandle)
{
    global DeviceCache, KEYCHRON_VID, KEYCHRON_PID

    if DeviceCache.Has(deviceHandle)
        return DeviceCache[deviceHandle]

    static RIDI_DEVICENAME := 0x20000007

    charCountBuffer := Buffer(4, 0)

    result := DllCall(
        "GetRawInputDeviceInfoW",
        "Ptr", deviceHandle,
        "UInt", RIDI_DEVICENAME,
        "Ptr", 0,
        "Ptr", charCountBuffer.Ptr,
        "UInt"
    )

    if result = 0xFFFFFFFF {
        DeviceCache[deviceHandle] := false
        return false
    }

    charCount := NumGet(charCountBuffer, 0, "UInt")

    if charCount = 0 {
        DeviceCache[deviceHandle] := false
        return false
    }

    nameBuffer := Buffer(charCount * 2, 0)

    result := DllCall(
        "GetRawInputDeviceInfoW",
        "Ptr", deviceHandle,
        "UInt", RIDI_DEVICENAME,
        "Ptr", nameBuffer.Ptr,
        "Ptr", charCountBuffer.Ptr,
        "UInt"
    )

    if result = 0xFFFFFFFF {
        DeviceCache[deviceHandle] := false
        return false
    }

    deviceName := StrGet(nameBuffer, "UTF-16")

    matches := (
        InStr(deviceName, KEYCHRON_VID, false)
        && InStr(deviceName, KEYCHRON_PID, false)
    )

    DeviceCache[deviceHandle] := matches

    return matches
}
