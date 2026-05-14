param(
    [Parameter(Mandatory = $true)]
    [string]$Image
)

$ErrorActionPreference = "Stop"

$AppDir = if ($env:VM_APP_DIR) { $env:VM_APP_DIR } else { (Get-Location).Path }
$RepoDir = (Resolve-Path ".").Path
$ComposeFile = Join-Path $RepoDir "deploy/docker-compose.blue-green.yml"
$StateFile = Join-Path $AppDir "active-slot"
$NginxTemplate = Join-Path $RepoDir "deploy/nginx.conf.template"
$NginxGenerated = Join-Path $RepoDir "deploy/nginx.generated.conf"
$HealthRetries = if ($env:HEALTH_RETRIES) { [int]$env:HEALTH_RETRIES } else { 12 }
$HealthDelay = if ($env:HEALTH_DELAY) { [int]$env:HEALTH_DELAY } else { 5 }

function Get-SlotPort {
    param([string]$Slot)

    switch ($Slot) {
        "blue" { return 8001 }
        "green" { return 8002 }
        default { throw "Unknown slot: $Slot" }
    }
}

function Get-OppositeSlot {
    param([string]$Slot)

    switch ($Slot) {
        "blue" { return "green" }
        "green" { return "blue" }
        default { return "blue" }
    }
}

function Wait-ForHealth {
    param([int]$Port)

    for ($attempt = 1; $attempt -le $HealthRetries; $attempt++) {
        try {
            Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 3 | Out-Null
            return $true
        }
        catch {
            Write-Host "Health check attempt $attempt/$HealthRetries failed for port $Port"
            Start-Sleep -Seconds $HealthDelay
        }
    }

    return $false
}

function Write-NginxConfig {
    param([int]$Port)

    $content = Get-Content $NginxTemplate -Raw
    $content = $content.Replace("__ACTIVE_PORT__", [string]$Port)
    Set-Content -Path $NginxGenerated -Value $content -NoNewline
}

New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Set-Content -Path (Join-Path $RepoDir ".env") -Value "IMAGE=$Image"

$activeSlot = if (Test-Path $StateFile) { (Get-Content $StateFile -Raw).Trim() } else { "none" }
$targetSlot = Get-OppositeSlot $activeSlot
$targetPort = Get-SlotPort $targetSlot

Write-Host "Active slot: $activeSlot"
Write-Host "Deploying image $Image to $targetSlot on port $targetPort"

Write-NginxConfig $targetPort

docker compose --env-file (Join-Path $RepoDir ".env") -f $ComposeFile --profile $targetSlot pull
docker compose --env-file (Join-Path $RepoDir ".env") -f $ComposeFile --profile $targetSlot up -d nginx "app-$targetSlot"

if (-not (Wait-ForHealth $targetPort)) {
    Write-Host "New $targetSlot slot failed health checks. Keeping $activeSlot active."
    docker compose --env-file (Join-Path $RepoDir ".env") -f $ComposeFile --profile $targetSlot stop "app-$targetSlot"
    exit 1
}

docker exec fastapi-cicd-nginx nginx -s reload
Set-Content -Path $StateFile -Value $targetSlot

if ($activeSlot -in @("blue", "green")) {
    docker compose --env-file (Join-Path $RepoDir ".env") -f $ComposeFile --profile $activeSlot stop "app-$activeSlot"
}

Write-Host "Deployment completed. Active slot is now $targetSlot."
