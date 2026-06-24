param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('unpin', 'is-on-current')]
  [string]$Action,

  [Parameter(Mandatory = $true)]
  [int]$Hwnd,

  [string]$AppId = 'com.biobase.client'
)

$ErrorActionPreference = 'Stop'

if (-not ('Biobase.VirtualDesktopIsolation' -as [type])) {
  $source = @'
using System;
using System.Runtime.InteropServices;

namespace Biobase {
  [ComImport, Guid("4CE1957C-E601-46E9-A877-F8CA3F01C7CC"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IVirtualDesktopManager {
    int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, [MarshalAs(UnmanagedType.Bool)] out bool onCurrentDesktop);
    int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);
    int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
  }

  [ComImport, Guid("B5A5F37A-5A1B-4C9A-9E33-9E0C70A49495"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IVirtualDesktopPinnedApps {
    int IsAppIdPinned(string appId, [MarshalAs(UnmanagedType.Bool)] out bool pinned);
    int PinAppID(string appId);
    int UnpinAppID(string appId);
    int IsViewPinned(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] out bool pinned);
    int PinView(IntPtr hwnd);
    int UnpinView(IntPtr hwnd);
  }

  public static class VirtualDesktopIsolation {
    private static IVirtualDesktopManager DesktopManager =>
      (IVirtualDesktopManager)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("AA509086-5CA9-4C25-8F95-589D3B07B48A")));

    private static IVirtualDesktopPinnedApps PinnedApps =>
      (IVirtualDesktopPinnedApps)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("B5A5F37A-5A1B-4C9A-9E33-9E0C70A49495")));

    public static void Unpin(IntPtr hwnd, string appId) {
      if (hwnd != IntPtr.Zero) {
        PinnedApps.UnpinView(hwnd);
      }
      if (!string.IsNullOrWhiteSpace(appId)) {
        PinnedApps.UnpinAppID(appId);
      }
    }

    public static bool IsOnCurrentDesktop(IntPtr hwnd) {
      if (hwnd == IntPtr.Zero) return true;
      bool onCurrent;
      DesktopManager.IsWindowOnCurrentVirtualDesktop(hwnd, out onCurrent);
      return onCurrent;
    }
  }
}
'@
  Add-Type -TypeDefinition $source -Language CSharp | Out-Null
}

$ptr = [IntPtr]$Hwnd

switch ($Action) {
  'unpin' {
    [Biobase.VirtualDesktopIsolation]::Unpin($ptr, $AppId)
    Write-Output 'ok'
  }
  'is-on-current' {
    $onCurrent = [Biobase.VirtualDesktopIsolation]::IsOnCurrentDesktop($ptr)
    Write-Output ([string]$onCurrent).ToLower()
  }
}
