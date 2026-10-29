# Keychron Q6 HE 8K Profile Monitor

A small AutoHotkey v2 utility that detects profile changes made with the physical switch on a Keychron Q6 HE 8K and displays a Windows notification.

## How it works

The utility registers for Windows Raw Input from the keyboard's vendor-specific HID collection:

*   **Vendor ID:** `0x3434`
    
*   **Product ID:** `0x1060`
    
*   **Usage page:** `0xFF60`
    
*   **Usage:** `0x61`
    

Profile changes produce a 32-byte HID report beginning with:

```
A9 11 02 <profile>
```

The final byte identifies the selected profile:
| Value | Profile |
| --- | --- |
| `0` | Profile 1 |
| `1` | Profile 2 |
| `2` | Profile 3 |

The script filters for this packet, debounces rapid changes caused by moving the physical switch through an intermediate position, and displays the final profile as a Windows notification.

## Requirements

*   Windows 10 or 11
    
*   AutoHotkey v2, or the provided compiled executable
    
*   Keychron Q6 HE 8K (`VID 3434`, `PID 1060`)
    

## Customisation

Profile names can be changed in the script:

```
global ProfileNames := Map(
    0, "Default",
    1, "FPS Gaming",
    2, "Gamepad"
)
```

Notification icons should be placed beside the script or executable:

```
Keychron.ico
Profile1.ico
Profile2.ico
Profile3.ico
```

The debounce duration can also be adjusted:

```
global ProfileDebounceMs := 300
```

## Disclaimer

The AutoHotkey code was generated with assistance from AI and tested with a Keychron Q6 HE 8K. It is provided as-is, without warranty.
