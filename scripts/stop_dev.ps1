<#
.SYNOPSIS
    Libris -- Safe Development Stack Terminator
.DESCRIPTION
    Safely terminates ONLY the background processes started by launch_dev.ps1,
    verifies that all ports are freed, and cleans up process tracking state.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Continue"

function Write-Header ($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Success ($text) { Write-Host " [PASS] $text" -ForegroundColor Green }
function Write-Info    ($text) { Write-Host " [INFO] $text" -ForegroundColor DarkGray }
function Write-Warn    ($text) { Write-Host " [WARN] $text" -ForegroundColor Yellow }
function Write-Fail    ($text) { Write-Host " [FAIL] $text" -ForegroundColor Red }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PidFile  = Join-Path $RepoRoot ".libris_pids.json"

Write-Header "LIBRIS SPRINT 15 -- SAFE STACK TERMINATOR"

if (-not (Test-Path $PidFile)) {
    Write-Warn "No .libris_pids.json file found. No tracked launcher processes to terminate."
    exit 0
}

try {
    $pidData = Get-Content $PidFile -Raw | ConvertFrom-Json
} catch {
    Write-Fail "Could not parse .libris_pids.json: $_"
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    exit 1
}

function Stop-ManagedProcess ($procInfo, $serviceName) {
    if (-not $procInfo -or -not $procInfo.pid) {
        Write-Info "No PID recorded for $serviceName."
        return
    }
    $targetPid = $procInfo.pid
    $proc = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Info "Terminating $serviceName process tree (PID $targetPid)..."
        # taskkill /T /F terminates the process and any spawned child processes (cmd, python, node, dart)
        & taskkill /PID $targetPid /T /F 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500
        $check = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
        if ($check) {
            Write-Warn "PID $targetPid did not terminate immediately. Retrying Stop-Process..."
            Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
        } else {
            Write-Success "$serviceName (PID $targetPid) terminated."
        }
    } else {
        Write-Info "$serviceName (PID $targetPid) is no longer running."
    }

    # Verify port is released
    if ($procInfo.port) {
        $port = $procInfo.port
        Start-Sleep -Milliseconds 300
        $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
        if ($conn) {
            $otherPid = $conn[0].OwningProcess
            Write-Warn "Port $port is still in use by PID $otherPid."
        } else {
            Write-Success "Port $port is free."
        }
    }
}

Stop-ManagedProcess $pidData.backend "Backend (Flask)"
Stop-ManagedProcess $pidData.web "Web (Next.js)"
Stop-ManagedProcess $pidData.flutter "Flutter Web"

# Clean up PID tracking file
Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
Write-Success "Process tracker .libris_pids.json removed."
Write-Host "`nAll Libris development services have been stopped safely." -ForegroundColor Green
