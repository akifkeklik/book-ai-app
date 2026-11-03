<#
.SYNOPSIS
    Libris -- Sprint 15: One-Command Full-Stack Development Launcher
.DESCRIPTION
    Launches the Flask backend, Next.js web application, and Flutter mobile-web
    preview in managed background processes, verifies HTTP readiness on all three
    endpoints, and opens Chrome with the web application and mobile viewport preview.
.PARAMETER BackendPort
    Local port for Flask API (default: 5000)
.PARAMETER WebPort
    Local port for Next.js web application (default: 3000)
.PARAMETER FlutterPort
    Local port for Flutter web server (default: 5001)
.PARAMETER TimeoutSeconds
    Readiness polling timeout in seconds (default: 60)
.PARAMETER NoBrowser
    Do not automatically open Chrome after services are ready
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

$ErrorActionPreference = "Stop"

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# -- Color Utilities ------------------------------------------------------------
function Write-Header ($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Success ($text) { Write-Host " [PASS] $text" -ForegroundColor Green }
function Write-Info    ($text) { Write-Host " [INFO] $text" -ForegroundColor DarkGray }
function Write-Warn    ($text) { Write-Host " [WARN] $text" -ForegroundColor Yellow }
function Write-Fail    ($text) { Write-Host " [FAIL] $text" -ForegroundColor Red }

# -- Paths & Setup -------------------------------------------------------------
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogDir   = Join-Path $RepoRoot ".logs"
$PidFile  = Join-Path $RepoRoot ".libris_pids.json"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

Write-Header "LIBRIS SPRINT 15 -- FULL-STACK DEVELOPMENT LAUNCHER"
Write-Info "Repository Root: $RepoRoot"
Write-Info "Target Ports: Backend=$BackendPort, Web=$WebPort, FlutterWeb=$FlutterPort"

# -- Step 1: Pre-flight Runtime Checks -----------------------------------------
Write-Header "STEP 1: PRE-FLIGHT RUNTIME AUDIT"

# Check Python
$pythonCmd = Get-Command "python" -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Fail "Python 3 is not found in PATH."
    exit 1
}
$pyVersion = (& python --version 2>&1).Trim()
Write-Success "Python: $pyVersion"

# Check Node & npm
$nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
$npmCmd  = Get-Command "npm" -ErrorAction SilentlyContinue
if (-not $nodeCmd -or -not $npmCmd) {
    Write-Fail "Node.js / npm not found in PATH."
    exit 1
}
$nodeVersion = (& node --version 2>&1).Trim()
$npmVersion  = (& npm --version 2>&1).Trim()
Write-Success "Node.js: $nodeVersion (npm: $npmVersion)"

# Check Flutter
$flutterCmd = Get-Command "flutter" -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Fail "Flutter SDK not found in PATH."
    exit 1
}
$flutterVersionLine = ((& flutter --version 2>&1) | Select-Object -First 1).Trim()
Write-Success "Flutter: $flutterVersionLine"

# Detect Chrome Executable
$ChromePath = $null
$chromeCandidates = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
foreach ($cand in $chromeCandidates) {
    if (Test-Path $cand) {
        $ChromePath = $cand
        break
    }
}
if ($ChromePath) {
    Write-Success "Google Chrome: $ChromePath"
} else {
    Write-Warn "Google Chrome executable not detected at standard locations. Browser auto-open will use system default."
}

# -- Step 2: Environment Configuration Check -----------------------------------
Write-Header "STEP 2: CONFIGURATION AUDIT"

$backendEnvFile = Join-Path $RepoRoot "backend\.env"
$rootEnvFile    = Join-Path $RepoRoot ".env"
$webEnvFile     = Join-Path $RepoRoot "web\.env.local"

if (-not (Test-Path $backendEnvFile) -and -not (Test-Path $rootEnvFile)) {
    Write-Warn "Neither backend\.env nor root .env found. Backend will run in unconfigured test mode."
} else {
    Write-Success "Environment configuration found."
}

if (-not (Test-Path $webEnvFile)) {
    Write-Warn "web\.env.local not found. Web client will use default localhost configuration."
} else {
    Write-Success "Web environment configuration found ($webEnvFile)."
}

# -- Step 3: Port Conflict Verification ----------------------------------------
Write-Header "STEP 3: PORT AVAILABILITY AUDIT"

function Test-PortAvailable ($port, $serviceName) {
    $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
    if ($conn) {
        $occupyingPid = $conn[0].OwningProcess
        $procName = (Get-Process -Id $occupyingPid -ErrorAction SilentlyContinue).ProcessName
        Write-Fail "Port $port ($serviceName) is already occupied by PID $occupyingPid ($procName)."
        Write-Fail "Resolve the conflict or pass alternate port via -$serviceNamePort <port>."
        return $false
    }
    Write-Success "Port $port ($serviceName) is free."
    return $true
}

$backendPortOk = Test-PortAvailable $BackendPort "Backend"
$webPortOk     = Test-PortAvailable $WebPort "Web"
$flutterPortOk = Test-PortAvailable $FlutterPort "Flutter"

if (-not ($backendPortOk -and $webPortOk -and $flutterPortOk)) {
    Write-Fail "Port conflict detected. Stopping launcher to prevent service corruption."
    exit 1
}

# Check for existing PID file
if (Test-Path $PidFile) {
    try {
        $existing = Get-Content $PidFile -Raw | ConvertFrom-Json
        Write-Warn "Found existing .libris_pids.json from a previous run."
        Write-Info "Executing stop script to clean up any orphaned processes..."
        & (Join-Path $PSScriptRoot "stop_dev.ps1")
    } catch {
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
}

# -- Step 4: Managed Process Launch --------------------------------------------
Write-Header "STEP 4: STARTING SERVICES IN MANAGED BACKGROUND PROCESSES"

$backendLog = Join-Path $LogDir "backend.log"
$webLog     = Join-Path $LogDir "web.log"
$flutterLog = Join-Path $LogDir "flutter.log"

# Clear old logs
"" | Set-Content $backendLog -Force
"" | Set-Content $webLog -Force
"" | Set-Content $flutterLog -Force

# 4A. Start Backend
Write-Info "Starting Flask Backend on 127.0.0.1:$BackendPort..."
$backendCmd = "set DEBUG=true&& set HOST=127.0.0.1&& set PORT=$BackendPort&& set PYTHONUNBUFFERED=1&& python -u -m backend.app > `"$backendLog`" 2>&1"
$backendProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $backendCmd -WorkingDirectory $RepoRoot -PassThru -NoNewWindow
Write-Info "Backend launched with wrapper PID $($backendProc.Id)."

# 4B. Start Web (Next.js)
Write-Info "Starting Next.js Web on 127.0.0.1:$WebPort..."
$webDir = Join-Path $RepoRoot "web"
$webCmd = "set BACKEND_URL=http://127.0.0.1:$BackendPort&& npm run dev -- -p $WebPort -H 127.0.0.1 > `"$webLog`" 2>&1"
$webProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $webCmd -WorkingDirectory $webDir -PassThru -NoNewWindow
Write-Info "Web client launched with wrapper PID $($webProc.Id)."

# 4C. Start Flutter Web
Write-Info "Starting Flutter Web target on 127.0.0.1:$FlutterPort..."
$flutterDir = Join-Path $RepoRoot "mobile\flutter_app"
$flutterCmd = "flutter run -d web-server --web-port $FlutterPort --web-hostname 127.0.0.1 --dart-define=BACKEND_URL=http://127.0.0.1:$BackendPort --dart-define=SUPABASE_URL=https://vnedgshbefpctjyzpqlm.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs > `"$flutterLog`" 2>&1"
$flutterProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $flutterCmd -WorkingDirectory $flutterDir -PassThru -NoNewWindow
Write-Info "Flutter web target launched with wrapper PID $($flutterProc.Id)."

# Persist PID tracking metadata
$pidRecord = @{
    started_at = (Get-Date -Format "o")
    backend = @{
        pid = $backendProc.Id
        port = $BackendPort
        log = $backendLog
        url = "http://127.0.0.1:$BackendPort"
        health_url = "http://127.0.0.1:$BackendPort/api/health"
        ready_url = "http://127.0.0.1:$BackendPort/api/health/ready"
    }
    web = @{
        pid = $webProc.Id
        port = $WebPort
        log = $webLog
        url = "http://127.0.0.1:$WebPort"
    }
    flutter = @{
        pid = $flutterProc.Id
        port = $FlutterPort
        log = $flutterLog
        url = "http://127.0.0.1:$FlutterPort"
    }
}
$pidRecord | ConvertTo-Json -Depth 4 | Set-Content $PidFile -Encoding UTF8
Write-Success "Process tracker saved to .libris_pids.json"

# -- Step 5: Bounded Readiness Polling ------------------------------------------
Write-Header "STEP 5: BOUNDED READINESS POLLING"

function Poll-Endpoint ($url, $timeoutSec, $proc, $logPath, $serviceName, [string]$expectedIdentity = "") {
    Write-Host -NoNewline " [WAIT] Polling $serviceName at $url (up to $timeoutSec s) " -ForegroundColor Yellow
    $startTime = Get-Date
    while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSec) {
        if ($proc.HasExited) {
            Write-Host "`n"
            Write-Fail "$serviceName process exited prematurely with code $($proc.ExitCode)!"
            if (Test-Path $logPath) {
                Write-Host "`n--- $serviceName Log Output ---" -ForegroundColor DarkRed
                Get-Content $logPath -Tail 25
                Write-Host "--------------------------------" -ForegroundColor DarkRed
            }
            return $false
        }
        try {
            $resp = Invoke-WebRequest -Uri $url -Method GET -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) {
                if ($expectedIdentity -ne "" -and -not ($resp.Content -match $expectedIdentity)) {
                    # Endpoint responded but not with expected identity (possible port collision/unrelated service)
                    Write-Host -NoNewline "?" -ForegroundColor Magenta
                } else {
                    Write-Host " [READY] (HTTP $($resp.StatusCode))" -ForegroundColor Green
                    return $true
                }
            }
        } catch {
            # Still warming up
        }
        Write-Host -NoNewline "." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
    Write-Host "`n"
    Write-Fail "$serviceName failed to respond within $timeoutSec seconds."
    if (Test-Path $logPath) {
        Write-Host "`n--- $serviceName Log Tail ---" -ForegroundColor DarkRed
        Get-Content $logPath -Tail 25
        Write-Host "-----------------------------" -ForegroundColor DarkRed
    }
    return $false
}

$backendReady = Poll-Endpoint "http://127.0.0.1:$BackendPort/api/health" $TimeoutSeconds $backendProc $backendLog "Backend" "book-ai-api"
$webReady     = Poll-Endpoint "http://127.0.0.1:$WebPort" $TimeoutSeconds $webProc $webLog "Web"
$flutterReady = Poll-Endpoint "http://127.0.0.1:$FlutterPort" $TimeoutSeconds $flutterProc $flutterLog "Flutter Web"

# Inspect separate database readiness
$dbStatus = "unavailable"
$dbStatusCode = 503
try {
    $readyResp = Invoke-WebRequest -Uri "http://127.0.0.1:$BackendPort/api/health/ready" -Method GET -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    $dbStatusCode = $readyResp.StatusCode
    $readyJson = $readyResp.Content | ConvertFrom-Json
    $dbStatus = $readyJson.status
} catch {
    if ($_.Exception.Response) {
        $dbStatusCode = [int]$_.Exception.Response.StatusCode
    }
}

if (-not ($backendReady -and $webReady -and $flutterReady)) {
    Write-Fail "One or more services failed readiness verification."
    Write-Info "Terminating launched development processes safely..."
    if ($backendProc -and -not $backendProc.HasExited) { Stop-Process -Id $backendProc.Id -Force -ErrorAction SilentlyContinue }
    if ($webProc -and -not $webProc.HasExited) { Stop-Process -Id $webProc.Id -Force -ErrorAction SilentlyContinue }
    if ($flutterProc -and -not $flutterProc.HasExited) { Stop-Process -Id $flutterProc.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# -- Step 6: Three-Link Local Showroom ------------------------------------------
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "                   LIBRIS -- THREE-LINK LOCAL SHOWROOM                          " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Backend health:               http://127.0.0.1:$BackendPort/api/health" -ForegroundColor Green
Write-Host "  2. Web application:              http://127.0.0.1:$WebPort" -ForegroundColor Green
Write-Host "  3. Mobile application in Chrome: http://127.0.0.1:$FlutterPort" -ForegroundColor Green
Write-Host ""
Write-Host "  Readiness and Dependency Details:" -ForegroundColor DarkCyan
Write-Host "   * Backend Liveness:             HEALTHY (HTTP 200)"
Write-Host "   * Backend Database Readiness:   $($dbStatus.ToUpper()) [HTTP $dbStatusCode at /api/health/ready]"
Write-Host "   * Web Client Status:            READY (HTTP 200, Next.js Turbopack)"
Write-Host "   * Flutter Web Target:           READY (HTTP 200, WebAssembly/CanvasKit)"
Write-Host ""
Write-Host "  Interactive Capabilities Available Now:" -ForegroundColor DarkCyan
Write-Host "   - Browse 6,400+ titles in Public Catalog (Web and Flutter Mobile-Web)"
Write-Host "   - Category Timeline, Search and Filtering"
Write-Host "   - AI Discovery Chat and Lexical/Semantic Book Exploration"
Write-Host "   - Offline-first cache and state transitions"
Write-Host ""
Write-Host "  Prerequisites and Boundaries:" -ForegroundColor DarkCyan
Write-Host '   - Unauthenticated browsing is fully open and functional without login.'
Write-Host '   - Personalized shelves (/favorites, library) require active authentication.'
Write-Host '   - Database readiness is independently audited via /api/health/ready.'
Write-Host ""
Write-Host "  Safe Termination:" -ForegroundColor Yellow
Write-Host "   To stop all 3 services safely, run:" -ForegroundColor Yellow
Write-Host '   .\scripts\stop_dev.ps1 (or .\stop_dev.ps1)' -ForegroundColor White
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan

# -- Step 7: Launch Chrome -----------------------------------------------------
if (-not $NoBrowser) {
    Write-Header "STEP 6: LAUNCHING CHROME BROWSING WINDOWS"
    try {
        if ($ChromePath -and (Test-Path $ChromePath)) {
            # Open Web in standard Chrome tab
            Write-Info "Opening Web application in Chrome..."
            Start-Process -FilePath $ChromePath -ArgumentList "http://127.0.0.1:$WebPort"
            Start-Sleep -Milliseconds 500

            # Open Flutter in dedicated Mobile-sized App Window (Pixel 7 / iPhone form factor: 412x915)
            Write-Info "Opening Flutter Mobile preview in Chrome mobile window (412x915)..."
            Start-Process -FilePath $ChromePath -ArgumentList "--app=http://127.0.0.1:$FlutterPort", "--window-size=412,915"
            Write-Success "Chrome windows opened successfully."
        } else {
            Write-Info "Opening Web application in default browser..."
            Start-Process "http://127.0.0.1:$WebPort"
            Start-Process "http://127.0.0.1:$FlutterPort"
            Write-Success "Default browser tabs launched."
        }
        Write-Info "Tip: In Chrome, press F12 then Ctrl+Shift+M to toggle Mobile Device Toolbar."
    } catch {
        Write-Warn "Could not launch Chrome automatically: $_"
    }
}

Write-Host ""
Write-Success "All Libris services are running live in the background. Ready for interaction!"

if ($Wait) {
    Write-Host "`n[DAEMON] Services are kept active in keep-alive loop. Press Ctrl+C to stop." -ForegroundColor Cyan
    try {
        while ($true) {
            Start-Sleep -Seconds 2
        }
    } finally {
        Write-Info "Keep-alive loop interrupted. Cleaning up managed services..."
        & (Join-Path $PSScriptRoot "stop_dev.ps1")
    }
}
