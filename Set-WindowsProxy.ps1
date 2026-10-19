#Requires -Version 7.0
<#
.SYNOPSIS
Manages the current Windows user's proxy settings and proxy environment variables.
.DESCRIPTION
Enable mode sets a manual HTTP proxy and replaces its bypass list. It also
sets HTTP_PROXY, HTTPS_PROXY, ALL_PROXY and NO_PROXY in User and Process scopes.

Disable mode turns off manual proxy, PAC and automatic detection for LAN,
clears the PAC URL, and removes the four proxy environment variables.
The saved manual proxy address and bypass list are retained. Enable mode
does not change or restore PAC and automatic detection settings.

VPN and WinHTTP settings are separate and are not modified.
.PARAMETER Disable
Turns off LAN proxy settings and removes proxy environment variables.
.PARAMETER ProxyAddress
HTTP proxy endpoint in host:port format, without a URL scheme or credentials.
Defaults to 127.0.0.1:10808. Bracket IPv6 addresses, for example [::1]:10808.
.EXAMPLE
& ./Set-WindowsProxy.ps1
Enables the default proxy and sets proxy environment variables.
.EXAMPLE
& ./Set-WindowsProxy.ps1 -ProxyAddress '192.168.1.10:7890'
Uses a custom endpoint for the manual proxy and proxy environment variables.
.EXAMPLE
& ./Set-WindowsProxy.ps1 -Disable
Turns off manual proxy, PAC and automatic detection, and removes proxy variables.
.NOTES
Requires Windows and PowerShell 7; administrator privileges are not required.
Run from an existing PowerShell session to update that session's environment.
A separate pwsh -File process cannot change its parent terminal's environment.
Other running applications may need to be restarted.

NO_PROXY uses comma-separated hosts and CIDR ranges, rather than Windows
wildcards. CIDR support varies by client; <local> has no portable equivalent.
Both HTTP_PROXY and HTTPS_PROXY use an http:// URL for the HTTP proxy endpoint.
#>

[CmdletBinding()]
param(
    [switch]$Disable,

    [ValidateScript({
        $endpoint = $null
        if ($_ -notmatch '^(?:[A-Za-z0-9._-]+|\[[0-9A-Fa-f:.%]+\]):[0-9]{1,5}$' -or
            -not [Uri]::TryCreate(('http://' + $_), [UriKind]::Absolute, [ref]$endpoint) -or
            $endpoint.Port -lt 1 -or $endpoint.Port -gt 65535) {
            throw 'ProxyAddress must be host:port (port 1-65535), e.g. 127.0.0.1:10808 or [::1]:10808. Do not include a URL scheme.'
        }
        $true
    })]
    [string]$ProxyAddress = '127.0.0.1:10808'
)

$ErrorActionPreference = 'Stop'

if (-not $IsWindows) {
    throw 'This script requires Windows.'
}

function Initialize-LanProxyApi {
    if ('PublicRepo.LanProxySettings' -as [type]) {
        return
    }

    # WinINet controls all three LAN proxy modes, including automatic detection.
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

function Set-ManualProxy {
    param(
        [string]$RegistryPath,
        [string]$Address,
        [string]$BypassList
    )

    New-ItemProperty -Path $RegistryPath -Name ProxyServer -PropertyType String -Value $Address -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name ProxyOverride -PropertyType String -Value $BypassList -Force | Out-Null
    New-ItemProperty -Path $RegistryPath -Name ProxyEnable -PropertyType DWord -Value 1 -Force | Out-Null
}

function Set-ProxyEnvironment {
    param(
        [string]$ProxyUrl,
        [string]$NoProxy,
        [switch]$Disable
    )

    $variables = [ordered]@{
        HTTP_PROXY  = $ProxyUrl
        HTTPS_PROXY = $ProxyUrl
        ALL_PROXY   = $ProxyUrl
        NO_PROXY    = $NoProxy
    }

    foreach ($name in @($variables.Keys)) {
        if ($Disable) {
            $variables[$name] = $null
        }

        foreach ($scope in @('User', 'Process')) {
            if ($Disable) {
                # A true .NET null deletes the variable on PowerShell 7.5+ too.
                [Environment]::SetEnvironmentVariable($name, [NullString]::Value, $scope)
            }
            else {
                [Environment]::SetEnvironmentVariable($name, $variables[$name], $scope)
            }
        }
    }

    [pscustomobject]$variables
}

# Keep Windows bypass rules separate from the NO_PROXY format used by CLI tools.
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$manualBypass = @(
    'localhost'
    '127.*'
    '10.*'
    '172.16.*'
    '172.17.*'
    '172.18.*'
    '172.19.*'
    '172.20.*'
    '172.21.*'
    '172.22.*'
    '172.23.*'
    '172.24.*'
    '172.25.*'
    '172.26.*'
    '172.27.*'
    '172.28.*'
    '172.29.*'
    '172.30.*'
    '172.31.*'
    '192.168.*'
    'hzboiler.com'
    '<local>'
) -join ';'

$noProxy = @(
    'localhost'
    '127.0.0.1'
    '::1'
    '127.0.0.0/8'
    '10.0.0.0/8'
    '172.16.0.0/12'
    '192.168.0.0/16'
    'hzboiler.com'
    '.hzboiler.com'
) -join ','

if ($Disable) {
    Initialize-LanProxyApi
    [PublicRepo.LanProxySettings]::Disable()
}
else {
    Set-ManualProxy -RegistryPath $registryPath -Address $ProxyAddress -BypassList $manualBypass
}

$environmentState = Set-ProxyEnvironment -ProxyUrl ('http://' + $ProxyAddress) -NoProxy $noProxy -Disable:$Disable

Get-ItemProperty -Path $registryPath |
    Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL

$environmentState

