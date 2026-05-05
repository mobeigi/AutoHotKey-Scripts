#Requires AutoHotkey v2.0
#Include Explorer_v2.ahk

#Warn
SendMode "Input"
SetWorkingDir A_ScriptDir

; Run Windows Terminal at current path
^!t:: {
	currentPath := Explorer_GetPath()
	currentPath := RegExReplace(currentPath, "\\", "\\\\") ; Escape slashes to fix arg tokenization (https://github.com/microsoft/terminal/issues/4571)
	arguments := ""
	if (currentPath != "ERROR") {
		arguments .= "-d " . '"' . currentPath . '"'
	}
	Run "wt.exe " . arguments
}
