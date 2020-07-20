#Include %A_ScriptDir%\Explorer.ahk

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

;Multimedia Keys for Ducky Shine 3

;Open selected file using notepad++
SC121::
	SelectedItems := """" . Explorer_GetSelected() . """"
	SelectedItems := StrReplace(SelectedItems, "`n", "`"" `""")
	Run,%A_ProgramFiles%\Notepad++\notepad++.exe %SelectedItems%,,,NotepadppPID
	WinActivate, ahk_pid %NotepadppPID%
return

;sc16b::b
;sc16c::run https://mail.google.com/mail/u/0/#inbox
;sc132::run D:\