#Include %A_ScriptDir%\Explorer.ahk

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

; Run Windows Terminal at current path
^!t::
	path := Explorer_GetPath()
	args := ""
	If (path != "ERROR") {
		args .= "-d " . """" . path . """"
	}
	Run wt.exe %args%
	return