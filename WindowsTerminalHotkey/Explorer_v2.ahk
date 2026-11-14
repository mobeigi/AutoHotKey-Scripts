#Requires AutoHotkey v2.0

/*
Explorer_v2.ahk
Project: https://github.com/mobeigi/AutoHotkey-Explorer-v2
Author: Mo Beigi <me@mobeigi.com>
Inspired by Joshua A. Kinnison's original Explorer helper.

Read filesystem paths and selected items from an Explorer window or desktop.
The filename targets AutoHotkey v2; Explorer.Version identifies the release.

API & usage
-----------
    #Include Explorer_v2.ahk

    context := Explorer.GetContext()         ; Active folder and selection.
    context := Explorer.GetContext(0, false) ; Active folder only.

GetContext(hwnd := 0, readSelection := true)
    Omit hwnd, or pass 0, to use the foreground window.

Result
------
    WindowHwnd
    FolderPath, SelectedPaths (Array)
    FolderStatus, SelectionStatus
    FolderSource, SelectionSource
    Diagnostics (Array)

Check the relevant status for "ok" before using its result.
An empty SelectedPaths array means nothing is selected only when
SelectionStatus is "ok". Diagnostics explains retrieval failures.

Design
------
Uses shell APIs first, with UI Automation recovery when shell access fails.
Validates paths and rejects ambiguous or incomplete selections.
Read-only: no navigation, keystrokes, clipboard changes, or persistent view caches.
*/

class Explorer {
    static Version := "1.0.0"

    static GetContext(hwnd := 0, readSelection := true) {
        result := this.Context(hwnd ? hwnd : WinExist("A"), readSelection)
        try {
            target := "ahk_id " result.WindowHwnd
            if !result.WindowHwnd || WinGetProcessName(target) != "explorer.exe"
                return this._Unsupported(result)
            windowClass := WinGetClass(target)
            desktop := RegExMatch(windowClass, "^(Progman|WorkerW)$")
            if !desktop && !RegExMatch(windowClass, "^(Cabinet|Explore|Explorer)WClass$")
                return this._Unsupported(result)
            tab := desktop ? 0 : this._ActiveTab(result.WindowHwnd)
            view := this._ViewHwnd(tab ? tab : result.WindowHwnd)
            if desktop && !view
                return this._Unsupported(result)

            shell := ComObject("Shell.Application")
            if desktop {
                this._SetFolder(result, A_Desktop, "shell")
            } else {
                try {
                    window := this._ShellWindow(shell, result.WindowHwnd, tab)
                    this._ReadShell(result, window, readSelection)
                } catch as err
                    this._Diagnostic(result, "shell", err)
            }

            ; Empty successful selections and known virtual folders do not trigger recovery.
            if result.FolderStatus = "unavailable"
                || (readSelection && result.SelectionStatus = "unavailable") {
                try this._ReadUIA(result, shell, view, desktop, readSelection)
                catch as err
                    this._Diagnostic(result, "uia", err)
            }

            ; Do not return information from a tab which changed while being read.
            if !WinExist(target) || (!desktop && this._ActiveTab(result.WindowHwnd) != tab)
                this._Invalidate(result, "The Explorer window or active tab changed during retrieval.")
        } catch as err {
            this._Diagnostic(result, "discovery", err)
            this._Invalidate(result, "The Explorer context could not be verified.")
        }
        return result
    }

    class Context {
        __New(hwnd, readSelection) {
            this.WindowHwnd := hwnd
            this.FolderPath := ""
            this.SelectedPaths := []
            this.FolderStatus := "unavailable"
            this.SelectionStatus := readSelection ? "unavailable" : "not-requested"
            this.FolderSource := ""
            this.SelectionSource := ""
            this.Diagnostics := []
        }
    }

    class ReadError extends Error {
        __New(status, message) {
            super.__New(message)
            this.Status := status
        }
    }

    static _Unsupported(result) {
        result.FolderStatus := "unsupported-window"
        if result.SelectionStatus != "not-requested"
            result.SelectionStatus := "unsupported-window"
        result.Diagnostics.Push("The target is not a supported Explorer folder window or desktop.")
        return result
    }

    static _Invalidate(result, message) {
        result.FolderPath := ""
        result.SelectedPaths := []
        result.FolderStatus := "stale-context"
        if result.SelectionStatus != "not-requested"
            result.SelectionStatus := "stale-context"
        result.FolderSource := ""
        result.SelectionSource := ""
        result.Diagnostics.Push(message)
    }

    static _Diagnostic(result, source, err) {
        ; Expected access/provider failures become statuses; programming errors do not.
        if !this._IsAccessError(err)
            throw err
        result.Diagnostics.Push(source ": " err.Message)
    }

    static _IsAccessError(err) => err is this.ReadError || err is OSError || err is TargetError

    static _ActiveTab(hwnd) {
        ; Explorer orders the active ShellTabWindowClass first in child Z-order.
        ; Inactive tab hosts can also report IsWindowVisible=true on Win11.
        for child in WinGetControlsHwnd("ahk_id " hwnd) {
            if WinGetClass("ahk_id " child) = "ShellTabWindowClass"
                && DllCall("IsWindowVisible", "Ptr", child, "Int")
                return child
        }
        return 0
    }

    static _ViewHwnd(hwnd) {
        views := []
        for child in WinGetControlsHwnd("ahk_id " hwnd) {
            if WinGetClass("ahk_id " child) = "SHELLDLL_DefView"
                && DllCall("IsWindowVisible", "Ptr", child, "Int")
                views.Push(child)
        }
        if views.Length > 1
            throw this.ReadError("unavailable", "More than one visible Explorer file view was found.")
        return views.Length ? views[1] : 0
    }

    static _DesktopListHwnd(view) {
        lists := []
        for child in WinGetControlsHwnd("ahk_id " view) {
            if WinGetClass("ahk_id " child) = "SysListView32"
                && DllCall("GetParent", "Ptr", child, "Ptr") = view
                && DllCall("IsWindowVisible", "Ptr", child, "Int")
                lists.Push(child)
        }
        if lists.Length != 1
            throw this.ReadError("unavailable", "No unique native Desktop icon list was found.")
        return lists[1]
    }

    static _ShellWindow(shell, hwnd, tab) {
        matches := []
        for window in shell.Windows {
            if window.HWND != hwnd
                continue
            if tab {
                ; SID_STopLevelBrowser, IID_IShellBrowser; IOleWindow::GetWindow.
                try {
                    browser := ComObjQuery(window, "{4C96BE40-915C-11CF-99D3-00AA004AE837}", "{000214E2-0000-0000-C000-000000000046}")
                    if !browser
                        continue
                    browserHwnd := 0
                    ComCall(3, browser, "Ptr*", &browserHwnd)
                    if browserHwnd != tab
                        continue
                } catch as err {
                    if !this._IsAccessError(err)
                        throw err
                    continue
                }
            }
            matches.Push(window)
        }
        if matches.Length != 1
            throw this.ReadError("unavailable", "No unique shell automation entry exists for the active view.")
        return matches[1]
    }

    static _ReadShell(result, window, readSelection) {
        document := window.Document
        if !IsObject(document)
            throw this.ReadError("unavailable", "The shell view does not expose a document yet.")
        folderItem := document.Folder.Self
        originalFolder := folderItem.Path
        try {
            if !folderItem.IsFileSystem
                throw this.ReadError("not-filesystem", "This shell location is not a filesystem directory.")
            this._SetFolder(result, originalFolder, "shell")
        } catch as err {
            result.FolderStatus := err is this.ReadError ? err.Status : "unavailable"
            this._Diagnostic(result, "shell folder", err)
        }
        if !readSelection
            return
        try {
            paths := []
            selectedItems := document.SelectedItems
            expectedCount := selectedItems.Count
            for item in selectedItems {
                if !item.IsFileSystem
                    throw this.ReadError("not-filesystem", "The selection includes a non-filesystem shell item.")
                path := item.Path
                if !FileExist(path)
                    throw this.ReadError("unresolved", "A selected path is missing or inaccessible: " path)
                paths.Push(path)
            }
            if paths.Length != expectedCount || selectedItems.Count != expectedCount
                throw this.ReadError("unavailable", "The selection changed while it was being enumerated.")
            if document.Folder.Self.Path != originalFolder
                throw this.ReadError("stale-context", "The folder changed while its selection was being read.")
            result.SelectedPaths := paths
            result.SelectionStatus := "ok"
            result.SelectionSource := "shell"
        } catch as err {
            if err is this.ReadError && err.Status = "stale-context" {
                this._Invalidate(result, err.Message)
                return
            }
            result.SelectionStatus := err is this.ReadError ? err.Status : "unavailable"
            this._Diagnostic(result, "shell selection", err)
        }
    }

    static _SetFolder(result, path, source) {
        if !this._AbsolutePath(path) || !DirExist(path)
            throw this.ReadError("unresolved", "The directory is missing or inaccessible: " path)
        result.FolderPath := path
        result.FolderStatus := "ok"
        result.FolderSource := source
    }

    static _AbsolutePath(path) {
        return RegExMatch(path, "i)^(?:[a-z]:\\|\\\\[^\\]+\\[^\\]+(?:\\|$))")
    }

    static _ReadUIA(result, shell, view, desktop, readSelection) {
        uia := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}", "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        root := this._UIRoot(uia, result.WindowHwnd)
        if result.FolderStatus = "unavailable" {
            try this._SetFolder(result, this._UIFolder(uia, root, shell, result.WindowHwnd), "uia")
            catch as err {
                result.FolderStatus := err is this.ReadError ? err.Status : "unavailable"
                this._Diagnostic(result, "uia folder", err)
            }
        }
        if !readSelection || result.SelectionStatus != "unavailable"
            return
        try {
            if !view
                throw this.ReadError("unavailable", "The visible file view could not be identified.")
            ; The Desktop's UIA descendants can omit the native list's class.
            ; Enter that verified list directly rather than searching its proxies.
            names := desktop
                ? this._UISelection(uia, this._UIRoot(uia, this._DesktopListHwnd(view)), true)
                : this._UISelection(uia, this._UIRoot(uia, view))
            ; A successful empty selection does not need a folder path or item mapping.
            if !names.Length
                paths := []
            else {
                if !desktop && result.FolderStatus != "ok"
                    throw this.ReadError("unresolved", "Selected UI items have no verified filesystem folder.")
                folder := shell.NameSpace(desktop ? 0 : result.FolderPath)
                if !folder
                    throw this.ReadError("unresolved", "The shell namespace could not be opened for name resolution.")
                paths := this._ResolveNames(names, folder)
            }
            if !desktop && result.FolderSource = "uia"
                && this._UIFolder(uia, root, shell, result.WindowHwnd) != result.FolderPath {
                this._Invalidate(result, "The address changed while the selection was being read.")
                return
            }
            result.SelectedPaths := paths
            result.SelectionStatus := "ok"
            result.SelectionSource := "uia"
        } catch as err {
            result.SelectionStatus := err is this.ReadError ? err.Status : "unavailable"
            this._Diagnostic(result, "uia selection", err)
        }
    }

    static _UIFolder(uia, root, shell, hwnd := 0) {
        ; Win11 hosts its toolbar outside the file view. Search that smaller tree
        ; when uniquely identifiable; retain the full-window path for other layouts.
        if hwnd {
            hosts := []
            for child in WinGetControlsHwnd("ahk_id " hwnd) {
                if DllCall("GetParent", "Ptr", child, "Ptr") = hwnd
                    && WinGetClass("ahk_id " child) = "Microsoft.UI.Content.DesktopChildSiteBridge"
                    && DllCall("IsWindowVisible", "Ptr", child, "Int")
                    hosts.Push(child)
            }
            if hosts.Length = 1 {
                try return this._UIFolder(uia, this._UIRoot(uia, hosts[1]), shell)
                catch as err {
                    if !this._IsAccessError(err)
                        throw err
                }
            }
        }
        ; Win11's address AutoSuggestBox, scoped to avoid the search box.
        hosts := this._UIFind(uia, root, 30011, "PART_AutoSuggestBox")
        ; Win10's breadcrumb host. These are identifiers/classes, not English UI labels.
        if !hosts.Length
            hosts := this._UIFind(uia, root, 30012, "Breadcrumb Parent")
        candidates := Map()
        candidates.CaseSense := false
        for host in hosts {
            for controlType in [50004, 50021] { ; Edit, ToolBar
                for element in this._UIFind(uia, host, 30003, controlType) {
                    value := this._UIValue(element)
                    if !this._AbsolutePath(value) {
                        ; Legacy address toolbar names may have a localized prefix.
                        label := this._UIString(element, 23)
                        value := RegExMatch(label, "i)(?:^|:\s+)((?:[a-z]:\\|\\\\)[^\r\n]*)$", &match) ? match[1] : ""
                    }
                    if this._AbsolutePath(value) && DirExist(value)
                        candidates[value] := true
                }
            }
        }
        ; Win11 may leave the edit value empty until the address bar is activated.
        ; Resolve its breadcrumb chain using shell identities, without activating it.
        breadcrumbPath := this._UIBreadcrumbFolder(uia, root, shell)
        if breadcrumbPath != ""
            candidates[breadcrumbPath] := true
        if candidates.Count != 1
            throw this.ReadError("unavailable", "No unique filesystem address was exposed by Explorer.")
        for path in candidates
            return path
    }

    static _UIBreadcrumbFolder(uia, root, shell) {
        roots := this._UIFind(uia, root, 30011, "FirstCrumbStackPanel")
        bars := this._UIFind(uia, root, 30011, "PART_BreadcrumbBar")
        if roots.Length != 1 || bars.Length != 1
            return ""
        rootName := this._UIString(roots[1], 23)
        names := []
        for crumb in this._UIFind(uia, bars[1], 30012, "FileExplorerExtensions.BreadcrumbBarItemControl") {
            name := this._UIString(crumb, 23)
            ; Ignore the overflow button preceding the actual root, without using
            ; its localized label. Retain all remaining ancestor components.
            if names.Length || name = rootName
                names.Push(name)
        }
        if !names.Length
            throw this.ReadError("unresolved", "The breadcrumb root is not exposed in its ancestry chain.")

        matches := Map()
        for namespaceId in [0, 17] { ; Desktop and This PC, including localized roots.
            namespace := shell.NameSpace(namespaceId)
            if namespace.Self.Name = rootName
                matches[namespace.Self.Path] := namespace.Self
            for item in this._FoldersNamed(namespace, rootName)
                matches[item.Path] := item
        }
        folder := this._UniqueFolder(matches, rootName)
        for index, name in names {
            if index = 1
                continue
            matches := Map()
            for item in this._FoldersNamed(folder, name)
                matches[item.Path] := item
            folder := this._UniqueFolder(matches, name)
        }
        if !folder.Self.IsFileSystem
            throw this.ReadError("not-filesystem", "The breadcrumb identifies a virtual shell location.")
        return folder.Self.Path
    }

    static _FoldersNamed(folder, name) {
        matches := []
        ; Let the shell exclude non-folders before crossing COM for every item.
        for item in this._Items(folder, true) {
            if item.IsFolder && (item.Name = name || folder.GetDetailsOf(item, 0) = name)
                matches.Push(item)
        }
        return matches
    }

    static _UniqueFolder(matches, name) {
        if matches.Count != 1
            throw this.ReadError("unresolved", "A breadcrumb folder is missing or ambiguous: " name)
        for path, item in matches
            return item.GetFolder
    }

    static _UISelection(uia, root, rootIsContainer := false) {
        if rootIsContainer
            container := root
        else {
            containers := this._UIFind(uia, root, 30012, "UIItemsView")
            if !containers.Length
                containers := this._UIFind(uia, root, 30012, "SysListView32")
            if containers.Length != 1
                throw this.ReadError("unavailable", "No unique supported file-list selection container was found.")
            container := containers[1]
        }
        itemContainer := this._UIPattern(container, 10019) ; Includes virtualized/offscreen items.
        elements := []
        if itemContainer {
            previous := 0
            Loop {
                element := this._UINextSelected(itemContainer, previous)
                if !element
                    break
                elements.Push(element)
                previous := element
            }
        } else {
            pattern := this._UIPattern(container, 10001) ; SelectionPattern (classic lists).
            if !pattern
                throw this.ReadError("unavailable", "The file list does not expose a selection pattern.")
            selected := 0
            ComCall(3, pattern, "Ptr*", &selected)
            elements := this._UIArray(this._Own(selected))
        }
        names := []
        for element in elements {
            controlType := 0
            ComCall(21, element, "Int*", &controlType)
            if controlType != 50007 && !this._UIPattern(element, 10020)
                throw this.ReadError("unresolved", "The file selection contains an unexpected UI element (" controlType ").")
            name := this._UIString(element, 23)
            if name = ""
                throw this.ReadError("unresolved", "A selected file has no exposed display name.")
            names.Push(name)
        }
        return names
    }

    static _UINextSelected(pattern, previous) {
        variant := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        NumPut("UShort", 11, variant) ; VT_BOOL
        NumPut("Short", -1, variant, 8) ; VARIANT_TRUE
        found := 0
        startAfter := previous ? ComObjValue(previous) : 0
        if A_PtrSize = 8
            ComCall(3, pattern, "Ptr", startAfter, "Int", 30079, "Ptr", variant, "Ptr*", &found)
        else
            ComCall(3, pattern, "Ptr", startAfter, "Int", 30079, "Int64", NumGet(variant, 0, "Int64"), "Int64", NumGet(variant, 8, "Int64"), "Ptr*", &found)
        return this._Own(found)
    }

    static _ResolveNames(names, folder) {
        labels := Map()
        labels.CaseSense := false
        for item in this._Items(folder) {
            ; Include shell display names (hidden extensions/shortcuts) and real names.
            itemPath := item.Path
            isFileSystem := !!item.IsFileSystem
            displayNames := [item.Name, folder.GetDetailsOf(item, 0)]
            if isFileSystem {
                SplitPath itemPath, &fileName
                displayNames.Push(fileName)
            }
            for label in displayNames {
                if label = ""
                    continue
                if !labels.Has(label)
                    labels[label] := Map()
                labels[label][itemPath] := isFileSystem
            }
        }
        paths := [], seen := Map()
        seen.CaseSense := false
        for name in names {
            if !labels.Has(name) || labels[name].Count != 1
                throw this.ReadError("unresolved", "Selected display name is missing or ambiguous: " name)
            for path, isFileSystem in labels[name] {
                if !isFileSystem
                    throw this.ReadError("not-filesystem", "Selected item is not a filesystem object: " name)
                if !FileExist(path) || seen.Has(path)
                    throw this.ReadError("unresolved", "A selected path is missing, inaccessible, or duplicated: " path)
                seen[path] := true
                paths.Push(path)
            }
        }
        return paths
    }

    static _Items(folder, foldersOnly := false) {
        items := folder.Items
        ; Filter only this detached enumeration, never the user's Explorer view.
        ; SHCONTF_FOLDERS | INCLUDEHIDDEN | INCLUDESUPERHIDDEN, optionally NONFOLDERS.
        items.Filter(foldersOnly ? 0x100A0 : 0x100E0, "*")
        return items
    }

    ; IUnknown wrappers own exactly the reference returned by each COM out parameter.
    static _Own(ptr) => ptr ? ComValue(13, ptr, 1) : 0

    static _UIRoot(uia, hwnd) {
        element := 0
        ComCall(6, uia, "Ptr", hwnd, "Ptr*", &element) ; ElementFromHandle
        if !element
            throw this.ReadError("unavailable", "UI Automation could not access the target window.")
        return this._Own(element)
    }

    static _UIPattern(element, patternId) {
        pattern := 0
        ComCall(16, element, "Int", patternId, "Ptr*", &pattern)
        return this._Own(pattern)
    }

    static _UIValue(element) {
        pattern := this._UIPattern(element, 10002) ; ValuePattern
        return pattern ? this._UIString(pattern, 4) : ""
    }

    static _UIString(element, method) {
        text := 0
        try {
            ComCall(method, element, "Ptr*", &text)
            return text ? StrGet(text) : ""
        } finally {
            if text
                DllCall("oleaut32\SysFreeString", "Ptr", text)
        }
    }

    static _UIFind(uia, root, propertyId, value) {
        ; CreatePropertyCondition takes a VARIANT by value (ABI differs on x86/x64).
        variant := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
        conditionPtr := 0
        try {
            if value is String {
                NumPut("UShort", 8, variant) ; VT_BSTR
                NumPut("Ptr", DllCall("oleaut32\SysAllocString", "Str", value, "Ptr"), variant, 8)
            } else {
                NumPut("UShort", 3, variant) ; VT_I4
                NumPut("Int", value, variant, 8)
            }
            if A_PtrSize = 8
                ComCall(23, uia, "Int", propertyId, "Ptr", variant, "Ptr*", &conditionPtr)
            else
                ComCall(23, uia, "Int", propertyId, "Int64", NumGet(variant, 0, "Int64"), "Int64", NumGet(variant, 8, "Int64"), "Ptr*", &conditionPtr)
        } finally
            DllCall("oleaut32\VariantClear", "Ptr", variant)
        condition := this._Own(conditionPtr)
        elements := 0
        ComCall(6, root, "Int", 4, "Ptr", ComObjValue(condition), "Ptr*", &elements)
        return this._UIArray(this._Own(elements))
    }

    static _UIArray(array) {
        items := []
        if !array
            return items
        count := 0
        ComCall(3, array, "Int*", &count)
        Loop count {
            element := 0
            ComCall(4, array, "Int", A_Index - 1, "Ptr*", &element)
            if !element
                throw this.ReadError("unavailable", "UI Automation returned an incomplete element array.")
            items.Push(this._Own(element))
        }
        return items
    }
}
