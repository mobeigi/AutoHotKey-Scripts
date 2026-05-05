#Include Explorer_v2.ahk

; Open selected file(s) using Zed
zedPath := EnvGet("LocalAppData") "\Programs\Zed\Zed.exe"
SC121::
{
    selectedItems := Explorer_GetSelected()

    if (selectedItems != "" && selectedItems != "ERROR")
    {
        selectedItems := '"' . selectedItems . '"'
        selectedItems := StrReplace(selectedItems, "`n", '" "')
        Run('"' zedPath '" ' selectedItems)
        return
    }

    currentPath := Explorer_GetPath()

    if (currentPath != "" && currentPath != "ERROR")
    {
        Run('"' zedPath '" "' currentPath '"')
        return
    }

    Run('"' zedPath '"')
}
