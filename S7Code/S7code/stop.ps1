# stop.ps1 — Shut down LLM Gateway V7
#
# Tries two methods in order:
#   1. Read .gateway.pid and kill that process
#   2. Scan netstat for port 8107 and kill whatever is listening
#
# Usage:
#   cd "D:\EAG\EAG\Class 23 May\Solution_Submission\S7Code\S7code"
#   .\stop.ps1

$S7DIR   = $PSScriptRoot
$PIDFILE = "$S7DIR\.gateway.pid"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " S7 RAG System - Shutting down Gateway" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$killed = $false

# ── Method 1: PID file ───────────────────────────────────────────────────────
if (Test-Path $PIDFILE) {
    $pidRaw = (Get-Content $PIDFILE -Raw).Trim()
    if ($pidRaw -match '^\d+$') {
        $gPid = [int]$pidRaw
        try {
            $proc = Get-Process -Id $gPid -ErrorAction Stop
            Write-Host "Stopping gateway process PID $gPid ($($proc.Name)) ..." -ForegroundColor Yellow
            Stop-Process -Id $gPid -Force
            Write-Host "Gateway stopped." -ForegroundColor Green
            $killed = $true
        } catch {
            Write-Host "PID $gPid not found (process may have already exited)." -ForegroundColor DarkGray
        }
    }
    Remove-Item $PIDFILE -ErrorAction SilentlyContinue
} else {
    Write-Host ".gateway.pid not found - will try port scan." -ForegroundColor DarkGray
}

# ── Method 2: Port scan on 8107 ──────────────────────────────────────────────
if (-not $killed) {
    Write-Host "Scanning for process listening on port 8107 ..." -ForegroundColor Yellow
    $netstatLines = netstat -ano 2>$null | Select-String ":8107\s"
    $foundPids = @()
    foreach ($line in $netstatLines) {
        if ($line -match '\s+(\d+)\s*$') {
            $foundPids += [int]$Matches[1]
        }
    }
    $foundPids = $foundPids | Select-Object -Unique

    if ($foundPids.Count -eq 0) {
        Write-Host "No process found on port 8107. Gateway may not be running." -ForegroundColor DarkGray
    } else {
        foreach ($p in $foundPids) {
            try {
                $proc = Get-Process -Id $p -ErrorAction Stop
                Write-Host "Killing PID $p ($($proc.Name)) listening on port 8107 ..." -ForegroundColor Yellow
                Stop-Process -Id $p -Force
                Write-Host "Killed PID $p." -ForegroundColor Green
                $killed = $true
            } catch {
                Write-Host "Could not kill PID $p : $_" -ForegroundColor DarkGray
            }
        }
    }
}

if (-not $killed) {
    Write-Host "Nothing to stop. Gateway appears to be down." -ForegroundColor Green
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Done." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
