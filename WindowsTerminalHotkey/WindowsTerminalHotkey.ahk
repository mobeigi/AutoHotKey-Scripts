#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Explorer_v2.ahk

#Warn
; Run Windows Terminal at the Explorer path, or its default directory if unavailable.
^!t:: {
    context := Explorer.GetContext(0, false) ; Terminal needs the folder, not the selection.
    command := "wt.exe"
    if context.FolderStatus = "ok" {
        ; Append \. to avoid the trailing-backslash quoting issue, especially at drive roots.
        ; https://github.com/microsoft/terminal/issues/4571
        directory := RTrim(context.FolderPath, "\") "\."
        command .= ' -d "' directory '"'
    }
    try Run(command)
    catch as err
        TrayTip err.Message, "Windows Terminal could not start"
}
