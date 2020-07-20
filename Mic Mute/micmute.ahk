Pause:: ;Pause Break button is my chosen hotkey

; The last number here is the microphone id
SoundSet, +1, MASTER, mute, 10
SoundGet, master_mute, , mute, 10

if (master_mute = "On") {
  Status = MUTED
} else {
  Status = ON
}

TrayTip , AHK Microphone Mute Toggle, Your microphone is now: %Status%, 2
return