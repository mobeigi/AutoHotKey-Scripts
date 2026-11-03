#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook True

*F19::{
    Run '"C:\Program Files\Nirsoft\NirCmd\nircmd.exe" mutesysvolume 2 default_record',, "Hide"
}
