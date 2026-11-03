<#
.SYNOPSIS
    Libris -- Development Stack Health & Status Inspector
.DESCRIPTION
    Checks the real-time liveness, readiness, and process status of all three
    Libris services started by launch_dev.ps1.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

function Write-Header ($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Success ($text) { Write-Host " [PASS] $text" -ForegroundColor Green }
function Write-Info    ($text) { Write-Host " [INFO] $text" -ForegroundColor DarkGray }
function Write-Warn    ($text) { Write-Host " [WARN] $text" -ForegroundColor Yellow }
function Write-Fail    ($text) { Write-Host " [FAIL] $text" -ForegroundColor Red }

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$PidFile  = Join-Path $RepoRoot ".libris_pids.json"
$LogDir   = Join-Path $RepoRoot ".logs"

Write-Header "LIBRIS SPRINT 15 -- STACK STATUS INSPECTOR"

if (-not (Test-Path $PidFile)) {
    Write-Warn "No .libris_pids.json found. The stack is not running via launch_dev.ps1."
    exit 0
}

try {
    $pidData = Get-Content $PidFile -Raw | ConvertFrom-Json
} catch {
    Write-Fail "Could not parse .libris_pids.json."
    exit 1
}

Write-Info "Stack Started At: $($pidData.started_at)"

function Check-ServiceStatus ($serviceName, $procInfo, $probeUrl, $readyUrl = $null) {
    Write-Host ""
    Write-Host "[$serviceName]" -ForegroundColor Cyan
    $pidVal = $procInfo.pid
    $portVal = $procInfo.port
    $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue

    if ($proc) {
        $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        Write-Success ("Process: RUNNING (PID " + $pidVal + ", WorkingSet: " + $memMB + " MB)")
    } else {
        Write-Fail ("Process: NOT RUNNING (PID " + $pidVal + " has exited)")
    }

    # Port Check
    $conn = Get-NetTCPConnection -LocalPort $portVal -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
    if ($conn) {
        Write-Success ("Port " + $portVal + ": LISTENING")
    } else {
        Write-Fail ("Port " + $portVal + ": NOT LISTENING")
    }

    # HTTP Probe
    if ($probeUrl) {
        try {
            $resp = Invoke-WebRequest -Uri $probeUrl -Method GET -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            Write-Success ("HTTP Probe (" + $probeUrl + "): HTTP " + $resp.StatusCode + " OK")
        } catch {
            $errMsg = $_.Exception.Message
            Write-Fail ("HTTP Probe (" + $probeUrl + "): FAILED - " + $errMsg)
        }
    }

    # Optional Readiness Probe
    if ($readyUrl) {
        try {
            $rResp = Invoke-WebRequest -Uri $readyUrl -Method GET -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            $rJson = $rResp.Content | ConvertFrom-Json
            Write-Success ("Readiness (" + $readyUrl + "): HTTP " + $rResp.StatusCode + " (status: " + $rJson.status + ")")
        } catch {
            $rErr = $_.Exception.Message
            Write-Warn ("Readiness (" + $readyUrl + "): NOT READY - " + $rErr)
        }
    }

    # Log tail if process exited
    if (-not $proc -and (Test-Path $procInfo.log)) {
        Write-Host "Recent Log Output:" -ForegroundColor DarkRed
        Get-Content $procInfo.log -Tail 10
    }
}

$bPort = $pidData.backend.port
$wPort = $pidData.web.port
$fPort = $pidData.flutter.port

$bUrl = "http://127.0.0.1:" + $bPort + "/api/health"
$bReadyUrl = "http://127.0.0.1:" + $bPort + "/api/health/ready"
$wUrl = "http://127.0.0.1:" + $wPort
$fUrl = "http://127.0.0.1:" + $fPort

Check-ServiceStatus "Backend (Flask API)" $pidData.backend $bUrl $bReadyUrl
Check-ServiceStatus "Web Application (Next.js)" $pidData.web $wUrl
Check-ServiceStatus "Mobile Application (Flutter Web)" $pidData.flutter $fUrl

Write-Host ""
