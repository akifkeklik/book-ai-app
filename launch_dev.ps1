<#
.SYNOPSIS
    Libris -- Sprint 15 Root Launcher
#>
[CmdletBinding()]
param(
    [int]$BackendPort = 5000,
    [int]$WebPort = 3000,
    [int]$FlutterPort = 5001,
    [int]$TimeoutSeconds = 120,
    [switch]$NoBrowser,
    [switch]$Wait,
    [switch]$Emulator,
    [string]$DeviceId = "",
    [switch]$Help
)

& "$PSScriptRoot\scripts\launch_dev.ps1" @PSBoundParameters
