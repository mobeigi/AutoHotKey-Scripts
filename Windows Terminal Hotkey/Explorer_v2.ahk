/*
	Library for getting info from a specific explorer window (if window handle not specified, the currently active
	window will be used).  Requires AHK v2.  Works with the desktop.  Does not currently work with save
	dialogs and such.


	Explorer_GetSelected(hwnd := "")   - paths of target window's selected items
	Explorer_GetAll(hwnd := "")        - paths of all items in the target window's folder
	Explorer_GetPath(hwnd := "")       - path of target window's folder

	example:
		F1:: {
			path := Explorer_GetPath()
			all  := Explorer_GetAll()
			sel  := Explorer_GetSelected()
			MsgBox path
			MsgBox all
			MsgBox sel
		}

	Joshua A. Kinnison
	2011-04-27, 16:12

	Converted to AHK v2 syntax by Claude.
	2026-05-05
*/

#Requires AutoHotkey v2.0

Explorer_GetPath(hwnd := "")
{
	if !(window := Explorer_GetWindow(hwnd))
		return "ERROR"
	if (window = "desktop")
		return A_Desktop
	path := window.LocationURL
	path := RegExReplace(path, "ftp://.*@", "ftp://")
	path := StrReplace(path, "file:///")
	path := StrReplace(path, "/", "\")

	; thanks to polyethene
	Loop {
		if RegExMatch(path, "i)(?<=%)[\da-f]{1,2}", &hex)
			path := StrReplace(path, "%" . hex[], Chr("0x" . hex[]))
		else
			break
	}
	return path
}

Explorer_GetAll(hwnd := "")
{
	return Explorer_Get(hwnd)
}

Explorer_GetSelected(hwnd := "")
{
	return Explorer_Get(hwnd, true)
}

Explorer_GetWindow(hwnd := "")
{
	; thanks to jethrow for some pointers here
	hwnd := hwnd ? hwnd : WinExist("A")
	process  := WinGetProcessName("ahk_id " hwnd)
	winClass := WinGetClass("ahk_id " hwnd)

	if (process != "explorer.exe")
		return
	if (winClass ~= "(Cabinet|Explore)WClass")
	{
		for window in ComObject("Shell.Application").Windows
			if (window.hwnd == hwnd)
				return window
	}
	else if (winClass ~= "Progman|WorkerW")
		return "desktop" ; desktop found
}

Explorer_Get(hwnd := "", selection := false)
{
	if !(window := Explorer_GetWindow(hwnd))
		return "ERROR"
	ret := ""
	if (window = "desktop")
	{
		hwWindow := ControlGetHwnd("SysListView321", "ahk_class Progman")
		if !hwWindow ; #D mode
			hwWindow := ControlGetHwnd("SysListView321", "A")
		files := ListViewGetContent((selection ? "Selected " : "") . "Col1", hwWindow)
		base  := (SubStr(A_Desktop, -1) == "\") ? SubStr(A_Desktop, 1, -1) : A_Desktop
		Loop Parse, files, "`n", "`r"
		{
			path := base "\" A_LoopField
			if FileExist(path) ; ignore special icons like Computer (at least for now)
				ret .= path "`n"
		}
	}
	else
	{
		if selection
			collection := window.document.SelectedItems
		else
			collection := window.document.Folder.Items
		for item in collection
			ret .= item.path "`n"
	}
	return Trim(ret, "`n")
}
