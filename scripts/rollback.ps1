$ErrorActionPreference = "Stop"

$AppDir = if ($env:VM_APP_DIR) { $env:VM_APP_DIR } else { (Get-Location).Path }
$RepoDir = (Resolve-Path ".").Path
$StateFile = Join-Path $AppDir "active-slot"
$NginxTemplate = Join-Path $RepoDir "deploy/nginx.conf.template"
$NginxGenerated = Join-Path $RepoDir "deploy/nginx.generated.conf"

function Get-SlotPort {
    param([string]$Slot)

    switch ($Slot) {
        "blue" { return 8001 }
        "green" { return 8002 }
        default { throw "Unknown slot: $Slot" }
    }
}

if (-not (Test-Path $StateFile)) {
    throw "No active slot state file found at $StateFile"
}

$activeSlot = (Get-Content $StateFile -Raw).Trim()
$rollbackSlot = if ($activeSlot -eq "blue") { "green" } elseif ($activeSlot -eq "green") { "blue" } else { throw "Invalid active slot: $activeSlot" }
$rollbackPort = Get-SlotPort $rollbackSlot

Invoke-WebRequest -Uri "http://127.0.0.1:$rollbackPort/health" -UseBasicParsing -TimeoutSec 3 | Out-Null

$content = Get-Content $NginxTemplate -Raw
$content = $content.Replace("__ACTIVE_PORT__", [string]$rollbackPort)
Set-Content -Path $NginxGenerated -Value $content -NoNewline
docker exec fastapi-cicd-nginx nginx -s reload
Set-Content -Path $StateFile -Value $rollbackSlot

Write-Host "Rolled back to $rollbackSlot."
