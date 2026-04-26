#Requires -Version 5.1
<#
.SYNOPSIS
    GolemGarden Web UI - Windows 환경 자동 셋업

.DESCRIPTION
    1. 환경 검사 (uv, npm, python, claude)
    2. 한글 username 감지 → C:\g-garden junction 생성
    3. 사용자 환경변수 영구 설정
    4. web/gateway uv sync
    5. web/client npm install
    6. 검증

.PARAMETER WhatIf
    Dry-run 모드: 실제 변경 없이 수행할 작업만 표시

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File web/setup.ps1
    powershell -ExecutionPolicy Bypass -File web/setup.ps1 -WhatIf
#>
param(
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── helpers ─────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host ">>> $Msg" -ForegroundColor Cyan
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg"   -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "  [ERR] $Msg"  -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "  $Msg"        -ForegroundColor Gray }

function Test-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ask-Continue {
    param([string]$Prompt)
    $ans = Read-Host "$Prompt [y/N]"
    return ($ans -eq 'y' -or $ans -eq 'Y')
}

# ── banner ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host "  GolemGarden Web UI - Windows Setup"              -ForegroundColor Magenta
if ($WhatIf) {
    Write-Host "  [DRY-RUN MODE - no changes will be made]"     -ForegroundColor Yellow
}
Write-Host "==================================================" -ForegroundColor Magenta

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$GatewayDir  = Join-Path $ScriptDir "gateway"
$ClientDir   = Join-Path $ScriptDir "client"

# ── STEP 1: 환경 검사 ────────────────────────────────────────────────────────

Write-Step "Step 1/5: Required tools check"

$missing = @()

foreach ($tool in @('python', 'npm', 'uv')) {
    if (Test-Command $tool) {
        Write-OK "$tool found"
    } else {
        Write-Warn "$tool not found"
        $missing += $tool
    }
}

# claude CLI - optional (Web UI works without it for local dev)
if (Test-Command 'claude') {
    Write-OK "claude CLI found"
} else {
    Write-Warn "claude CLI not found (needed for SOUL chat — install via npm i -g @anthropic-ai/claude-code)"
}

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Err "Missing required tools: $($missing -join ', ')"
    Write-Host "  Install guide:"
    if ($missing -contains 'uv')     { Write-Host "    uv:     https://docs.astral.sh/uv/getting-started/installation/" }
    if ($missing -contains 'npm')    { Write-Host "    npm:    https://nodejs.org/" }
    if ($missing -contains 'python') { Write-Host "    python: https://www.python.org/downloads/" }
    Write-Host ""
    if (-not (Ask-Continue "Continue anyway?")) {
        exit 1
    }
}

# ── STEP 2: 한글 username 감지 → junction ────────────────────────────────────

Write-Step "Step 2/5: Korean username / path junction check"

$junctionTarget = "$env:USERPROFILE\.claude\golem-garden"
$junctionLink   = "C:\g-garden"

$hasNonAscii = $env:USERPROFILE -match '[^\x00-\x7f]'

if ($hasNonAscii) {
    Write-Warn "Non-ASCII characters detected in USERPROFILE: $env:USERPROFILE"
    Write-Info "Git for Windows bash cannot resolve paths with Korean/CJK characters."
    Write-Info "Creating NTFS junction: $junctionLink -> $junctionTarget"

    if (Test-Path $junctionLink) {
        $existing = (Get-Item $junctionLink).Target
        if ($existing -eq $junctionTarget) {
            Write-OK "Junction already exists and points to correct target"
        } else {
            Write-Warn "Junction exists but points to: $existing"
            Write-Info "Expected: $junctionTarget"
            if (-not $WhatIf) {
                if (Ask-Continue "Recreate junction?") {
                    cmd /c "rmdir `"$junctionLink`"" 2>$null
                    cmd /c "mklink /J `"$junctionLink`" `"$junctionTarget`""
                    Write-OK "Junction recreated"
                }
            } else {
                Write-Info "[DRY-RUN] Would recreate junction $junctionLink -> $junctionTarget"
            }
        }
    } else {
        if (-not (Test-Path $junctionTarget)) {
            Write-Warn "Target path does not exist yet: $junctionTarget"
            Write-Info "Run install.sh first, then re-run this script."
        } elseif ($WhatIf) {
            Write-Info "[DRY-RUN] Would run: mklink /J `"$junctionLink`" `"$junctionTarget`""
        } else {
            cmd /c "mklink /J `"$junctionLink`" `"$junctionTarget`""
            if ($LASTEXITCODE -eq 0) {
                Write-OK "Junction created: $junctionLink"
            } else {
                Write-Err "Failed to create junction. Try running as Administrator."
            }
        }
    }
} else {
    Write-OK "Username is ASCII-safe: $env:USERNAME"
    Write-Info "Junction not required (but optional if you want a short path)"
}

# ── STEP 3: 환경변수 영구 설정 ───────────────────────────────────────────────

Write-Step "Step 3/5: Environment variables (User scope)"

# forge.sh path: prefer junction if it was created, else original path
if ($hasNonAscii -and (Test-Path $junctionLink)) {
    $forgeBashPath = "/mnt/c/g-garden/forge.sh"
} else {
    # Convert Windows path to bash-compatible /mnt/ path
    $winForge = Join-Path $junctionTarget "forge.sh"
    $forgeBashPath = $winForge -replace '^([A-Za-z]):\\', '/mnt/$1/' -replace '\\', '/'
    $forgeBashPath = $forgeBashPath.ToLower() -replace '^/mnt/([a-z])/', { "/mnt/$($_.Groups[1].Value.ToLower())/" }
}

# Ask for extra project roots
Write-Host ""
Write-Host "  GOLEM_EXTRA_PROJECT_ROOTS: projects outside your home dir (e.g. C:/work/proj1;C:/work/proj2)" -ForegroundColor Gray
Write-Host "  Current project root: $ProjectRoot" -ForegroundColor Gray
$currentExtra = [System.Environment]::GetEnvironmentVariable('GOLEM_EXTRA_PROJECT_ROOTS', 'User')
if ($currentExtra) {
    Write-Host "  Current value: $currentExtra" -ForegroundColor DarkGray
    $extraRoots = Read-Host "  New value (leave blank to keep current)"
    if (-not $extraRoots) { $extraRoots = $currentExtra }
} else {
    $default = $ProjectRoot -replace '\\', '/'
    $extraRoots = Read-Host "  Enter paths (default: $default)"
    if (-not $extraRoots) { $extraRoots = $default }
}

$envVars = [ordered]@{
    'GOLEM_FORGE_SH_BASH'      = $forgeBashPath
    'MSYS_NO_PATHCONV'         = '1'
    'MSYS2_ARG_CONV_EXCL'      = '*'
    'GOLEM_EXTRA_PROJECT_ROOTS' = $extraRoots
}

foreach ($key in $envVars.Keys) {
    $desired = $envVars[$key]
    $current = [System.Environment]::GetEnvironmentVariable($key, 'User')

    if ($current -eq $desired) {
        Write-OK "$key = $desired (unchanged)"
    } elseif ($current) {
        Write-Warn "$key changing: '$current' -> '$desired'"
        if (-not $WhatIf) {
            [System.Environment]::SetEnvironmentVariable($key, $desired, 'User')
            Write-OK "$key updated"
        } else {
            Write-Info "[DRY-RUN] Would set $key = $desired"
        }
    } else {
        if (-not $WhatIf) {
            [System.Environment]::SetEnvironmentVariable($key, $desired, 'User')
            Write-OK "$key set"
        } else {
            Write-Info "[DRY-RUN] Would set $key = $desired"
        }
    }
}

# ── STEP 4: gateway uv sync ──────────────────────────────────────────────────

Write-Step "Step 4/5: Gateway dependencies (uv sync)"

if (Test-Path $GatewayDir) {
    if (-not $WhatIf) {
        Push-Location $GatewayDir
        try {
            uv sync
            Write-OK "Gateway deps installed"
        } catch {
            Write-Err "uv sync failed: $_"
            if (-not (Ask-Continue "Continue to next step?")) { exit 1 }
        } finally {
            Pop-Location
        }
    } else {
        Write-Info "[DRY-RUN] Would run: uv sync in $GatewayDir"
    }
} else {
    Write-Warn "Gateway dir not found: $GatewayDir — skipping"
}

# ── STEP 5: client npm install ───────────────────────────────────────────────

Write-Step "Step 5/5: Client dependencies (npm install)"

if (Test-Path $ClientDir) {
    if (-not $WhatIf) {
        Push-Location $ClientDir
        try {
            npm install
            Write-OK "Client deps installed"
        } catch {
            Write-Err "npm install failed: $_"
            if (-not (Ask-Continue "Continue?")) { exit 1 }
        } finally {
            Pop-Location
        }
    } else {
        Write-Info "[DRY-RUN] Would run: npm install in $ClientDir"
    }
} else {
    Write-Warn "Client dir not found: $ClientDir — skipping"
}

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Magenta
Write-Host ""
if (-not $WhatIf) {
    Write-Host "  IMPORTANT: Open a NEW shell window for env vars to take effect." -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "  Start servers:" -ForegroundColor Cyan
Write-Host "    Double-click:  web\start-all.bat"
Write-Host "    Or separately: web\start-gateway.bat"
Write-Host "                   web\start-ui.bat"
Write-Host ""
Write-Host "  Browser: http://localhost:5173"
Write-Host ""
