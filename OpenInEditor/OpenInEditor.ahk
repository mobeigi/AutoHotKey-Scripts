#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Explorer_v2.ahk

#Warn

; Open selected file(s) using Zed
zedCliPath := EnvGet("LocalAppData") "\Programs\Zed\bin\Zed.exe"
F13::
{
    context := Explorer.GetContext()
    if context.SelectionStatus != "ok" {
        TrayTip "Could not read the Explorer selection (" context.SelectionStatus ").", "Open in Zed"
        return
    }

    paths := context.SelectedPaths
    if !paths.Length {
        if context.FolderStatus != "ok" {
            TrayTip "Could not read the Explorer directory (" context.FolderStatus ").", "Open in Zed"
            return
        }
        paths := [context.FolderPath]
    }

    arguments := ""
    for path in paths {
        ; Directory roots must not end in a backslash immediately before a quote.
        if DirExist(path)
            path := RTrim(path, "\") "\."
        arguments .= ' "' path '"'
    }
    try Run('"' zedCliPath '"' arguments, , "Hide")
    catch as err
        TrayTip err.Message, "Zed could not start"
}
