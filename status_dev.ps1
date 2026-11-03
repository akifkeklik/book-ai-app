<#
.SYNOPSIS
    Libris -- Sprint 15 Root Stack Status Inspector
#>
[CmdletBinding()]
param()

& "$PSScriptRoot\scripts\status_dev.ps1" @PSBoundParameters
