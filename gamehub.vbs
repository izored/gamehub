' Runs a Game Hub script without a console window.
'   wscript.exe gamehub.vbs          -> open the hub (starts the server if needed)
'   wscript.exe gamehub.vbs server   -> start the server only (used by the Startup shortcut)
Dim sh, fso, dir, script
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
script = "open-hub.ps1"
If WScript.Arguments.Count > 0 Then
  If LCase(WScript.Arguments(0)) = "server" Then script = "server.ps1"
End If
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\" & script & """", 0, False
