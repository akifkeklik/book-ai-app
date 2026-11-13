<#
.SYNOPSIS
    Libris -- Root Launcher (delegates to scripts/launch_dev.ps1)
#>
[CmdletBinding()]
param(
    [int]$BackendPort = 5000,
    [int]$WebPort = 3000,
    [int]$TimeoutSeconds = 120,
    [switch]$NoBrowser,
    [switch]$Wait,
    [switch]$Help
)

& "$PSScriptRoot\scripts\launch_dev.ps1" @PSBoundParameters
