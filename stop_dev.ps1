<#
.SYNOPSIS
    Libris -- Sprint 15 Root Stack Terminator
#>
[CmdletBinding()]
param(
    [switch]$Force
)

& "$PSScriptRoot\scripts\stop_dev.ps1" @PSBoundParameters
