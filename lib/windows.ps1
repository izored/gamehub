# Shared window and process helpers (a small C# class), used by watch-game.ps1, track-games.ps1
# and controller-helper.ps1. Reads window titles and executable paths only; it never opens,
# reads or stops another process.

if (-not ('GameHubWindows' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class GameHubWindows {
  public class Win { public IntPtr Handle; public int Pid; public string Title; public bool Minimized; public int Width; public int Height; }

  [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
  delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int pid);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder path, ref int size);

  // Full path of a process's executable. Asks only for "query limited information" (0x1000),
  // which Windows grants even for games protected by anti-cheat.
  public static string ProcessPath(int pid) {
    IntPtr h = OpenProcess(0x1000, false, pid);
    if (h == IntPtr.Zero) return null;
    try {
      var sb = new StringBuilder(1024);
      int size = sb.Capacity;
      return QueryFullProcessImageName(h, 0, sb, ref size) ? sb.ToString() : null;
    } finally { CloseHandle(h); }
  }

  // Visible top-level windows that are not owned by another window (dialogs, tooltips).
  public static List<Win> TopWindows() {
    var list = new List<Win>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      if (IsWindowVisible(h) && GetWindow(h, 4) == IntPtr.Zero) {
        var sb = new StringBuilder(256);
        GetWindowText(h, sb, sb.Capacity);
        int pid;
        GetWindowThreadProcessId(h, out pid);
        RECT r;
        GetWindowRect(h, out r);
        list.Add(new Win { Handle = h, Pid = pid, Title = sb.ToString(), Minimized = IsIconic(h), Width = r.Right - r.Left, Height = r.Bottom - r.Top });
      }
      return true;
    }, IntPtr.Zero);
    return list;
  }

  // Restores a window and brings it to the front. Windows only lets the program the user is
  // using change the front window, so this briefly joins the input of the current front window
  // (a documented technique, used here only for the Game Hub window).
  public static bool BringToFront(IntPtr hWnd) {
    if (IsIconic(hWnd)) ShowWindowAsync(hWnd, 9);   // SW_RESTORE
    IntPtr fg = GetForegroundWindow();
    int ignore;
    uint fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out ignore);
    uint me = GetCurrentThreadId();
    bool attached = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
    try {
      BringWindowToTop(hWnd);
      SetForegroundWindow(hWnd);
    } finally {
      if (attached) AttachThreadInput(me, fgThread, false);
    }
    return GetForegroundWindow() == hWnd;
  }
}
'@
}

$script:HubBrowsers = @('chrome', 'msedge', 'brave', 'vivaldi', 'opera', 'chromium')

function Get-ExeName([int]$procId) {
  $p = [GameHubWindows]::ProcessPath($procId)
  if ($p) { return [IO.Path]::GetFileName($p) }
  return '?'
}

# the Game Hub app window: a Chromium-based browser window titled exactly "Game Hub"
function Get-HubWindows {
  return @([GameHubWindows]::TopWindows() | Where-Object { $_.Title -eq 'Game Hub' } | Where-Object {
    $p = [GameHubWindows]::ProcessPath($_.Pid)
    $p -and ($script:HubBrowsers -contains [IO.Path]::GetFileNameWithoutExtension($p).ToLowerInvariant())
  })
}

# ids of the processes whose executable lives inside $dir
function Get-GamePids([string]$dir) {
  $prefix = $dir.TrimEnd('\') + '\'
  $ids = New-Object System.Collections.Generic.List[int]
  foreach ($p in [Diagnostics.Process]::GetProcesses()) {
    if ($p.Id -le 4) { continue }
    $path = [GameHubWindows]::ProcessPath($p.Id)
    if ($path -and $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $ids.Add($p.Id) }
  }
  return ,$ids
}

# path of every running process, once (cheaper than Get-GamePids for many games)
function Get-ProcessPaths {
  $list = New-Object System.Collections.Generic.List[string]
  foreach ($p in [Diagnostics.Process]::GetProcesses()) {
    if ($p.Id -le 4) { continue }
    $path = [GameHubWindows]::ProcessPath($p.Id)
    if ($path) { $list.Add($path) }
  }
  return ,$list
}
