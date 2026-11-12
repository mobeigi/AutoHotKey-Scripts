#Requires AutoHotkey v2.0
#Include Explorer_v2.ahk

; Open selected file(s) using Zed
zedCliPath := EnvGet("LocalAppData") "\Programs\Zed\bin\Zed.exe"
F13::
{
    selectedItems := Explorer_GetSelected()

    if (selectedItems != "" && selectedItems != "ERROR")
    {
        selectedItems := '"' . selectedItems . '"'
        selectedItems := StrReplace(selectedItems, "`n", '" "')
        Run('"' zedCliPath '" ' selectedItems, , "Hide")
		return
    }

    currentPath := Explorer_GetPath()

    if (currentPath != "" && currentPath != "ERROR")
    {
        Run('"' zedCliPath '" "' currentPath '"', , "Hide")
        return
    }

    Run('"' zedCliPath '"', , "Hide")
}
