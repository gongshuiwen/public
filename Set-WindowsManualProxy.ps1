#Requires -Version 7.0
<#
.SYNOPSIS
Enables or disables the current Windows user's manual proxy and proxy environment variables.
.DESCRIPTION
Replaces the manual proxy bypass list with the configured entries.
The <local> entry enables bypass for local intranet hostnames without dots.
Persists HTTP_PROXY, HTTPS_PROXY, ALL_PROXY and NO_PROXY for the current user
and updates the environment of the PowerShell process running this script.
Both HTTP_PROXY and HTTPS_PROXY use an http:// proxy URL; HTTPS requests
use HTTP CONNECT through the same proxy endpoint.
NO_PROXY uses comma-separated hosts and CIDR ranges instead of Windows
wildcards. CIDR support varies between clients, and <local> has no portable
NO_PROXY equivalent. Configure client-specific bypass rules when needed.
With -Disable, turns off manual proxy, PAC and automatic detection for the
current user's LAN settings, clears the PAC URL and removes these four
environment variables from both User and Process scopes. Retains the saved
manual proxy address and bypass list so they can be inspected or reused.
Enable mode leaves PAC and automatic detection settings unchanged; it does
not restore automatic settings that were cleared by -Disable.
Run in PowerShell 7 on Windows; administrator privileges are not required.
Run with & ./Set-WindowsManualProxy.ps1 in an existing PowerShell session
to update that session too. A separate pwsh -File process cannot update
the environment of its parent terminal.
Restart affected applications if they do not pick up the new settings.
.PARAMETER Disable
Turns off manual proxy, PAC and automatic detection, clears the PAC URL,
and removes HTTP_PROXY, HTTPS_PROXY, ALL_PROXY and NO_PROXY from the current
user's persistent environment and this process. VPN and WinHTTP settings
are separate and are not modified.
.EXAMPLE
& ./Set-WindowsManualProxy.ps1
Enables the configured manual proxy and sets proxy environment variables.
.EXAMPLE
& ./Set-WindowsManualProxy.ps1 -Disable
Disables manual proxy, PAC and automatic detection, and clears proxy environment variables.
#>

[CmdletBinding()]
param(
    [switch]$Disable
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'This script requires Windows.'
}

$proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$proxyAddress = '127.0.0.1:10808'

$bypass = 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;hzboiler.com;<local>'

$proxyUrl = 'http://' + $proxyAddress
$proxyEnvironment = [ordered]@{
    HTTP_PROXY  = $proxyUrl
    HTTPS_PROXY = $proxyUrl
    ALL_PROXY   = $proxyUrl
    NO_PROXY    = 'localhost,127.0.0.1,::1,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,hzboiler.com,.hzboiler.com'
}

if ($Disable) {
    # Use the supported WinINet API rather than editing connection binary data.
    if (-not ('PublicRepo.LanProxySettings' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace PublicRepo
{
    public static class LanProxySettings
    {
        private const uint INTERNET_OPTION_PER_CONNECTION_OPTION = 75;
        private const uint INTERNET_OPTION_SETTINGS_CHANGED = 39;
        private const uint INTERNET_OPTION_REFRESH = 37;
        private const uint INTERNET_PER_CONN_FLAGS = 1;
        private const uint INTERNET_PER_CONN_AUTOCONFIG_URL = 4;
        private const uint PROXY_TYPE_DIRECT = 1;

        [StructLayout(LayoutKind.Explicit)]
        private struct OptionValue
        {
            [FieldOffset(0)] public uint Flags;
            [FieldOffset(0)] public IntPtr Text;
            [FieldOffset(0)] public System.Runtime.InteropServices.ComTypes.FILETIME FileTime;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ConnectionOption
        {
            public uint Option;
            public OptionValue Value;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ConnectionOptionList
        {
            public uint Size;
            public IntPtr Connection;
            public uint Count;
            public uint Error;
            public IntPtr Options;
        }

        [DllImport("wininet.dll", EntryPoint = "InternetSetOptionW", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InternetSetOptionW(IntPtr handle, uint option, IntPtr buffer, uint size);

        private static void SetOption(uint option, IntPtr buffer, uint size)
        {
            if (!InternetSetOptionW(IntPtr.Zero, option, buffer, size))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to update Windows proxy settings (option " + option + ").");
        }

        public static void Disable()
        {
            IntPtr options = IntPtr.Zero;
            IntPtr listBuffer = IntPtr.Zero;
            IntPtr emptyUrl = IntPtr.Zero;
            try
            {
                int optionSize = Marshal.SizeOf(typeof(ConnectionOption));
                options = Marshal.AllocHGlobal(checked(optionSize * 2));
                emptyUrl = Marshal.StringToHGlobalUni(string.Empty);
                // DIRECT only: no PROXY, AUTO_PROXY_URL or AUTO_DETECT flags.
                var flags = new ConnectionOption {
                    Option = INTERNET_PER_CONN_FLAGS,
                    Value = new OptionValue { Flags = PROXY_TYPE_DIRECT }
                };
                var pac = new ConnectionOption {
                    Option = INTERNET_PER_CONN_AUTOCONFIG_URL,
                    Value = new OptionValue { Text = emptyUrl }
                };
                Marshal.StructureToPtr(flags, options, false);
                Marshal.StructureToPtr(pac, IntPtr.Add(options, optionSize), false);
                var list = new ConnectionOptionList {
                    Size = (uint)Marshal.SizeOf(typeof(ConnectionOptionList)),
                    Connection = IntPtr.Zero, // NULL selects LAN; VPN connections are separate.
                    Count = 2,
                    Options = options
                };
                listBuffer = Marshal.AllocHGlobal((int)list.Size);
                Marshal.StructureToPtr(list, listBuffer, false);
                SetOption(INTERNET_OPTION_PER_CONNECTION_OPTION, listBuffer, list.Size);
                SetOption(INTERNET_OPTION_SETTINGS_CHANGED, IntPtr.Zero, 0);
                SetOption(INTERNET_OPTION_REFRESH, IntPtr.Zero, 0);
            }
            finally
            {
                if (listBuffer != IntPtr.Zero) Marshal.FreeHGlobal(listBuffer);
                if (options != IntPtr.Zero) Marshal.FreeHGlobal(options);
                if (emptyUrl != IntPtr.Zero) Marshal.FreeHGlobal(emptyUrl);
            }
        }
    }
}
'@
    }
    [PublicRepo.LanProxySettings]::Disable()
    # Mark the variables for removal in the loop below.
    foreach ($name in @($proxyEnvironment.Keys)) {
        $proxyEnvironment[$name] = $null
    }
}
else {
    New-ItemProperty -Path $proxyKey -Name ProxyServer -PropertyType String -Value $proxyAddress -Force | Out-Null
    New-ItemProperty -Path $proxyKey -Name ProxyOverride -PropertyType String -Value $bypass -Force | Out-Null
    New-ItemProperty -Path $proxyKey -Name ProxyEnable -PropertyType DWord -Value 1 -Force | Out-Null
}

foreach ($entry in $proxyEnvironment.GetEnumerator()) {
    if ($null -eq $entry.Value) {
        # Pass a true .NET null; PowerShell 7.5+ can convert $null to an empty string.
        [Environment]::SetEnvironmentVariable($entry.Key, [NullString]::Value, 'User')
        [Environment]::SetEnvironmentVariable($entry.Key, [NullString]::Value, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'User')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}

Get-ItemProperty -Path $proxyKey |
    Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL

[pscustomobject]$proxyEnvironment

