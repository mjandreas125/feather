<#
  Visual check helper: launches Feather, optionally sends keystrokes, captures the window
  (PrintWindow with PW_RENDERFULLCONTENT, so it works even when the window is covered)
  and saves a PNG.

  Example:
    powershell -ExecutionPolicy Bypass -File tools\shot.ps1 -Out shot.png -Wait 6 `
      -AppArgs @('C:\some\folder', '--model=haiku', '--prompt=Hello')
    # Steps: "wait:5", "post:1", "post:ENTER", "text:hello", "shot:after.png"
#>
param(
  [string]$Exe = "$PSScriptRoot\..\build\windows\x64\runner\Release\feather.exe",
  [string[]]$AppArgs = @(),
  [int]$Wait = 6,
  [string]$Out = "$env:TEMP\feather_shot.png",
  [string[]]$Steps = @(),
  [switch]$Keep,
  # Ask the app to render itself (works with the monitor asleep / window covered).
  [switch]$InApp,
  [int]$Width = 1040,
  [int]$Height = 820
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FW {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint flags, UIntPtr extra);

  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size = 40)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);

  static INPUT Key(ushort vk, ushort scan, uint flags) {
    var i = new INPUT(); i.type = 1; i.ki.wVk = vk; i.ki.wScan = scan; i.ki.dwFlags = flags; return i;
  }
  // Presses a chord of virtual keys (e.g. Ctrl+T) with correct scan codes.
  public static void Chord(ushort[] vks) {
    var list = new System.Collections.Generic.List<INPUT>();
    foreach (var vk in vks) list.Add(Key(vk, (ushort)MapVirtualKey(vk, 0), IsExt(vk) ? 1u : 0u));
    for (int k = vks.Length - 1; k >= 0; k--) list.Add(Key(vks[k], (ushort)MapVirtualKey(vks[k], 0), (IsExt(vks[k]) ? 1u : 0u) | 2u));
    SendInput((uint)list.Count, list.ToArray(), Marshal.SizeOf(typeof(INPUT)));
  }
  static bool IsExt(ushort vk) { return vk == 0x25 || vk == 0x26 || vk == 0x27 || vk == 0x28 || vk == 0x2E || vk == 0x24 || vk == 0x23; }
  // Types text as Unicode characters, independent of the keyboard layout.
  public static void Text(string s) {
    foreach (char c in s) {
      var a = new INPUT[] { Key(0, c, 4), Key(0, c, 4 | 2) };
      SendInput(2, a, Marshal.SizeOf(typeof(INPUT)));
      System.Threading.Thread.Sleep(6);
    }
  }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@

$script:snapDir = Join-Path $env:TEMP ('feather_snap_' + [guid]::NewGuid().ToString('N'))
if ($InApp) { New-Item -ItemType Directory -Force $script:snapDir | Out-Null; $AppArgs = @($AppArgs) + @("--snapshot-dir=$script:snapDir") }

function Capture($h, $path) {
  if ($InApp) {
    $name = [IO.Path]::GetFileName($path)
    Set-Content -Path (Join-Path $script:snapDir 'request.txt') -Value $name -NoNewline
    $out = Join-Path $script:snapDir $name
    for ($i = 0; $i -lt 40 -and -not (Test-Path $out); $i++) { Start-Sleep -Milliseconds 150 }
    if (Test-Path $out) { Start-Sleep -Milliseconds 100; Copy-Item $out $path -Force; Write-Host "saved $path (in-app)" } else { Write-Host "in-app snapshot timed out" }
    return
  }
  $r = New-Object FW+RECT
  [void][FW]::GetWindowRect($h, [ref]$r)
  $w = $r.R - $r.L; $hh = $r.B - $r.T
  $bmp = New-Object System.Drawing.Bitmap $w, $hh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [void][FW]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc); $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "saved $path"
}

function EnsureForeground($h) {
  for ($i = 0; $i -lt 5; $i++) {
    if ([FW]::GetForegroundWindow() -eq $h) { return $true }
    # A lone Alt tap lets a background process take the foreground (Windows rule).
    [FW]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [FW]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [void][FW]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 250
  }
  return ([FW]::GetForegroundWindow() -eq $h)
}

function ParseChord($spec) {
  $named = @{ CTRL = 0x11; SHIFT = 0x10; ALT = 0x12; ENTER = 0x0D; ESC = 0x1B; TAB = 0x09; UP = 0x26; DOWN = 0x28;
              LEFT = 0x25; RIGHT = 0x27; SPACE = 0x20; BACK = 0x08; DEL = 0x2E; HOME = 0x24; END = 0x23 }
  [uint16[]]($spec.ToUpper() -split '\+' | ForEach-Object { if ($named.ContainsKey($_)) { $named[$_] } else { [int][char]$_ } })
}

function FlutterView($h) {
  $v = [FW]::FindWindowEx($h, [IntPtr]::Zero, 'FLUTTERVIEW', [NullString]::Value)
  if ($v -eq [IntPtr]::Zero) { return $h } else { return $v }
}
$vkNames = @{ ENTER = 0x0D; ESC = 0x1B; TAB = 0x09; UP = 0x26; DOWN = 0x28; LEFT = 0x25; RIGHT = 0x27; SPACE = 0x20; BACK = 0x08 }
function PostKey($h, $name) {
  $v = FlutterView $h
  $vk = if ($vkNames.ContainsKey($name)) { $vkNames[$name] } else { [int][char]$name.ToUpper() }
  $sc = [FW]::MapVirtualKey($vk, 0)
  $down = [IntPtr](1 -bor ($sc -shl 16))
  $up = [IntPtr]([int64]1 -bor ([int64]$sc -shl 16) -bor (1L -shl 30) -bor (1L -shl 31))
  [void][FW]::PostMessage($v, 0x0100, [IntPtr]$vk, $down)
  if ($name.Length -eq 1) { [void][FW]::PostMessage($v, 0x0102, [IntPtr][int][char]$name, $down) }
  if ($name -eq 'ENTER') { [void][FW]::PostMessage($v, 0x0102, [IntPtr]13, $down) }
  Start-Sleep -Milliseconds 30
  [void][FW]::PostMessage($v, 0x0101, [IntPtr]$vk, $up)
  Start-Sleep -Milliseconds 60
}
function PostText($h, $text) {
  $v = FlutterView $h
  foreach ($ch in $text.ToCharArray()) {
    [void][FW]::PostMessage($v, 0x0102, [IntPtr][int]$ch, [IntPtr]1)
    Start-Sleep -Milliseconds 8
  }
}

$p = Start-Process -FilePath (Resolve-Path $Exe) -ArgumentList $AppArgs -PassThru
$deadline = (Get-Date).AddSeconds(20)
while ($p.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200; $p.Refresh() }
$h = $p.MainWindowHandle
[void][FW]::ShowWindow($h, 1)
[void][FW]::MoveWindow($h, 60, 40, $Width, $Height, $true)
Start-Sleep -Seconds $Wait

foreach ($s in $Steps) {
  $kind, $val = $s -split ':', 2
  switch ($kind) {
    'wait'  { Start-Sleep -Milliseconds ([int]([double]$val * 1000)) }
    'shot'  { Capture $h $val }
    # Clicks the middle of Feather's own reminder popup (found by window class); no-op if absent.
    'clickpopup' {
      $pw = [FW]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, 'FeatherReminderPopup', [NullString]::Value)
      if ($pw -eq [IntPtr]::Zero) { Write-Host 'no popup' } else {
        $r = New-Object FW+RECT; [void][FW]::GetWindowRect($pw, [ref]$r)
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ([int](($r.L + $r.R) / 2 - 40)), ([int](($r.T + $r.B) / 2 + 10))
        [FW]::keybd_event(0, 0, 0, [UIntPtr]::Zero)
        Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);' -Name M -Namespace W -ErrorAction SilentlyContinue
        [W.M]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); [W.M]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        Write-Host 'clicked popup'
      }
    }
    # click:X,Y — window-relative pixels; only when Feather is in front.
    'click' {
      if (EnsureForeground $h) {
        $xy = $val -split ','
        $r = New-Object FW+RECT; [void][FW]::GetWindowRect($h, [ref]$r)
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point ($r.L + [int]$xy[0]), ($r.T + [int]$xy[1])
        Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);' -Name M -Namespace W -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 80
        [W.M]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); [W.M]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 150
      } else { Write-Host "skip click: not foreground" }
    }
    'minimize' { [void][FW]::ShowWindow($h, 6) }
    'restore'  { [void][FW]::ShowWindow($h, 9) }
    # Bottom-right corner of the primary screen only (where Windows shows toasts).
    'corner' {
      $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
      $w = 480; $hh = 300
      $bmp = New-Object System.Drawing.Bitmap $w, $hh
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.CopyFromScreen($b.Right - $w, $b.Bottom - $hh, 0, 0, $bmp.Size)
      $g.Dispose(); $bmp.Save($val, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
      Write-Host "saved $val"
    }
    # Real key presses, sent ONLY after verifying Feather is the foreground window,
    # so nothing can ever be typed into another application.
    # key:CTRL+T  key:ENTER  key:1  key:SHIFT+TAB  key:DOWN
    'key'   { if (EnsureForeground $h) { [FW]::Chord((ParseChord $val)); Start-Sleep -Milliseconds 120 } else { Write-Host "skip key: not foreground" } }
    # ASCII text via SendKeys (reliable with Flutter); utype = Unicode via SendInput.
    'type'  { if (EnsureForeground $h) { [System.Windows.Forms.SendKeys]::SendWait(($val -replace '([+^%~(){}\[\]])', '{$1}')) } else { Write-Host "skip type: not foreground" } }
    'utype' { if (EnsureForeground $h) { [FW]::Text($val) } else { Write-Host "skip utype: not foreground" } }
  }
}
Capture $h $Out
$p.Refresh()
"WorkingSet: {0:N0} MB  Private: {1:N0} MB" -f ($p.WorkingSet64/1MB), ($p.PrivateMemorySize64/1MB)
if (-not $Keep) { Stop-Process -Id $p.Id -Force }
