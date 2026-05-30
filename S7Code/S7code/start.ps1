# start.ps1 — One-click runner for the S7 RAG benchmark
#
# What it does (fully automated, no user prompts):
#   1. Verifies Ollama is reachable and has required models loaded
#   2. Starts LLM Gateway V7 in the background, logging to logs\gateway_<ts>.log
#   3. Polls http://localhost:8107/v1/status until the gateway is ready (120s timeout)
#   4. Warms up Ollama with a small ping so the model is hot before long queries
#   5. Runs run_all_queries.py (all 15 queries, sequential)
#   6. Prints the log directory so you know where to find the results
#
# Usage:
#   cd "D:\EAG\EAG\Class 23 May\Solution_Submission\S7Code\S7code"
#   .\start.ps1

$ErrorActionPreference = "Stop"

# Force UTF-8 and unbuffered output for all Python subprocesses
$env:PYTHONUTF8 = "1"
$env:PYTHONUNBUFFERED = "1"

$S7DIR   = $PSScriptRoot
$GWDIR   = Resolve-Path "$S7DIR\..\..\Gateway\llm_gatewayV7"
$LOGSDIR = "$S7DIR\logs"
$TS      = Get-Date -Format "yyyyMMdd_HHmmss"
$GWLOG   = "$LOGSDIR\gateway_$TS.log"
$PIDFILE = "$S7DIR\.gateway.pid"

New-Item -ItemType Directory -Force -Path $LOGSDIR | Out-Null

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " S7 RAG System - Starting up" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Check Ollama ──────────────────────────────────────────────────────
Write-Host "[1/5] Checking Ollama at http://localhost:11434 ..." -ForegroundColor Yellow
try {
    $ollamaResp = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "      Ollama OK (HTTP $($ollamaResp.StatusCode))" -ForegroundColor Green

    # Check that the required models are present
    $tags = $ollamaResp.Content | ConvertFrom-Json
    $modelNames = $tags.models | ForEach-Object { $_.name }
    $needsLLM   = -not ($modelNames | Where-Object { $_ -like "qwen3*" })
    $needsEmbed = -not ($modelNames | Where-Object { $_ -like "nomic-embed-text*" })

    if ($needsLLM) {
        Write-Host "      WARNING: qwen3:8b not found in Ollama. Pulling now (may take a while)..." -ForegroundColor Yellow
        ollama pull qwen3:8b
    } else {
        Write-Host "      qwen3:8b present" -ForegroundColor Green
    }
    if ($needsEmbed) {
        Write-Host "      WARNING: nomic-embed-text not found in Ollama. Pulling now..." -ForegroundColor Yellow
        ollama pull nomic-embed-text
    } else {
        Write-Host "      nomic-embed-text present" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: Ollama is not running or not reachable." -ForegroundColor Red
    Write-Host "       Start it with:  ollama serve" -ForegroundColor Red
    Write-Host "       Then re-run this script." -ForegroundColor Red
    exit 1
}

# ── Step 2: Start or reuse Gateway V7 ────────────────────────────────────────
Write-Host "[2/5] Starting LLM Gateway V7 ..." -ForegroundColor Yellow
Write-Host "      Directory : $GWDIR" -ForegroundColor DarkGray
Write-Host "      Log file  : $GWLOG" -ForegroundColor DarkGray

# Check if a healthy gateway is already up (use /v1/routers — lightweight endpoint).
$gatewayAlreadyUp = $false
try {
    $existingResp = Invoke-WebRequest -Uri "http://localhost:8107/v1/routers" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
    if ($existingResp.StatusCode -eq 200) {
        Write-Host "      Gateway already running and healthy - reusing." -ForegroundColor Green
        $gatewayAlreadyUp = $true
    }
} catch { }

# If port 8107 is occupied but the gateway is unhealthy (old/broken process), kill it.
if (-not $gatewayAlreadyUp) {
    $netstatLines = netstat -ano 2>$null | Select-String ":8107\s"
    foreach ($line in $netstatLines) {
        if ($line -match '\s+(\d+)\s*$') {
            $stalePid = [int]$Matches[1]
            try {
                Stop-Process -Id $stalePid -Force -ErrorAction SilentlyContinue
                Write-Host "      Killed stale process PID $stalePid on port 8107." -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
            } catch { }
        }
    }
}

if (-not $gatewayAlreadyUp) {
    $gwProc = Start-Process `
        -FilePath "uv" `
        -ArgumentList "run", "main.py" `
        -WorkingDirectory $GWDIR `
        -RedirectStandardOutput $GWLOG `
        -RedirectStandardError "$GWLOG.err" `
        -PassThru `
        -WindowStyle Hidden

    $gwProc.Id | Out-File -FilePath $PIDFILE -Encoding ascii
    Write-Host "      Gateway PID $($gwProc.Id) written to .gateway.pid" -ForegroundColor DarkGray

    # ── Step 3: Wait for gateway ready ───────────────────────────────────────
    Write-Host "[3/5] Waiting for gateway to become ready (max 120s) ..." -ForegroundColor Yellow
    $maxWait = 120
    $waited  = 0
    $ready   = $false
    while ($waited -lt $maxWait) {
        Start-Sleep -Seconds 3
        $waited += 3
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8107/v1/routers" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -eq 200) {
                $ready = $true
                break
            }
        } catch { }
        Write-Host "      ...${waited}s elapsed" -ForegroundColor DarkGray
    }

    if (-not $ready) {
        Write-Host ""
        Write-Host "ERROR: Gateway did not become ready within ${maxWait}s." -ForegroundColor Red
        Write-Host "       Check gateway log: $GWLOG" -ForegroundColor Red
        Write-Host "       Check error log  : $GWLOG.err" -ForegroundColor Red
        exit 1
    }
    Write-Host "      Gateway ready after ${waited}s" -ForegroundColor Green
} else {
    Write-Host "[3/5] Gateway already up - skipping wait." -ForegroundColor Green
}

# ── Step 3b: Smoke-test /v1/chat so we know the gateway handles POST correctly ─
Write-Host "      Smoke-testing /v1/chat ..." -ForegroundColor DarkGray
try {
    $chatBody = '{"prompt":"Reply with the single word OK.","max_tokens":4,"temperature":0}'
    $chatResp = Invoke-WebRequest `
        -Uri "http://localhost:8107/v1/chat" `
        -Method POST `
        -Body $chatBody `
        -ContentType "application/json" `
        -TimeoutSec 120 `
        -UseBasicParsing `
        -ErrorAction Stop
    Write-Host "      /v1/chat smoke test OK (HTTP $($chatResp.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "      WARNING: /v1/chat smoke test failed: $_" -ForegroundColor Yellow
    Write-Host "      Check $GWLOG and $GWLOG.err for details." -ForegroundColor Yellow
    Write-Host "      Proceeding anyway — gateway may still work for real queries." -ForegroundColor Yellow
}

# ── Step 4: Warm up Ollama (load model into VRAM before first query) ──────────
Write-Host "[4/5] Warming up Ollama model (loading into VRAM) ..." -ForegroundColor Yellow
try {
    $warmupBody = '{"model":"qwen3:8b","prompt":"hi","stream":false}'
    $warmupResp = Invoke-WebRequest `
        -Uri "http://localhost:11434/api/generate" `
        -Method POST `
        -Body $warmupBody `
        -ContentType "application/json" `
        -TimeoutSec 120 `
        -UseBasicParsing `
        -ErrorAction Stop
    Write-Host "      Ollama warmup complete (HTTP $($warmupResp.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "      Ollama warmup skipped (non-fatal): $_" -ForegroundColor DarkGray
}

# ── Step 5: Run all queries ───────────────────────────────────────────────────
Write-Host "[5/5] Running all 15 queries (this will take several minutes) ..." -ForegroundColor Yellow
Write-Host "      Each query has its own log in $LOGSDIR\session_*\" -ForegroundColor DarkGray
Write-Host ""

Set-Location $S7DIR

uv run python run_all_queries.py

$exitCode = $LASTEXITCODE

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
if ($exitCode -eq 0) {
    Write-Host " All queries completed successfully!" -ForegroundColor Green
} else {
    Write-Host " Some queries failed. Check logs in $LOGSDIR" -ForegroundColor Red
}
Write-Host " Logs directory: $LOGSDIR" -ForegroundColor Cyan
Write-Host " Gateway log   : $GWLOG" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Run .\stop.ps1 to shut down the gateway when you are done." -ForegroundColor Yellow
Write-Host ""

exit $exitCode
