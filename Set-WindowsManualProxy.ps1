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
With -Disable, turns off the manual proxy and removes these four environment
variables from both User and Process scopes. Retains the saved manual proxy
address and bypass list so they can be inspected or reused.
Both modes leave PAC and automatic proxy detection settings unchanged.
Run in PowerShell 7 on Windows; administrator privileges are not required.
Run with & ./Set-WindowsManualProxy.ps1 in an existing PowerShell session
to update that session too. A separate pwsh -File process cannot update
the environment of its parent terminal.
Restart affected applications if they do not pick up the new settings.
.PARAMETER Disable
Turns off the manual proxy and clears HTTP_PROXY, HTTPS_PROXY, ALL_PROXY
and NO_PROXY from the current user's persistent environment and this process.
.EXAMPLE
& ./Set-WindowsManualProxy.ps1
Enables the configured manual proxy and sets proxy environment variables.
.EXAMPLE
& ./Set-WindowsManualProxy.ps1 -Disable
Disables the manual proxy and clears proxy environment variables.
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
    New-ItemProperty -Path $proxyKey -Name ProxyEnable -PropertyType DWord -Value 0 -Force | Out-Null
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
    Select-Object ProxyEnable, ProxyServer, ProxyOverride

[pscustomobject]$proxyEnvironment

