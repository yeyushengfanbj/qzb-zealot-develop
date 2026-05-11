param(
  [string]$ConfigPath = ".\\customer.release.env",
  [string]$RollbackTag = ""
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "`n==> $Message" -ForegroundColor Yellow
}

function Read-Config {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Config file not found: $Path"
  }

  $map = @{}
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      return
    }

    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2) {
      return
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    $map[$key] = $value
  }

  return $map
}

function Require-Key {
  param(
    [hashtable]$Config,
    [string]$Key
  )

  if (-not $Config.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Config[$Key])) {
    throw "Missing required key: $Key"
  }
}

function Set-Or-Add-EnvLine {
  param(
    [string]$FilePath,
    [string]$Key,
    [string]$Value
  )

  if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "Env file not found: $FilePath"
  }

  $lines = Get-Content -LiteralPath $FilePath
  $prefix = "$Key="
  $found = $false

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith($prefix)) {
      $lines[$i] = "$Key=$Value"
      $found = $true
    }
  }

  if (-not $found) {
    $lines += "$Key=$Value"
  }

  Set-Content -LiteralPath $FilePath -Value $lines
}

Write-Step "Loading config"
$config = Read-Config -Path $ConfigPath

$requiredKeys = @(
  "CLIENT_DEPLOY_DIR",
  "CLIENT_SERVER_PORT",
  "CLIENT_HEALTH_PATH",
  "IMAGE_REPO"
)

foreach ($key in $requiredKeys) {
  Require-Key -Config $config -Key $key
}

$deployDir = $config["CLIENT_DEPLOY_DIR"]
$serverPort = $config["CLIENT_SERVER_PORT"]
$healthPath = $config["CLIENT_HEALTH_PATH"]
$imageRepo = $config["IMAGE_REPO"]

if (-not (Test-Path -LiteralPath $deployDir)) {
  throw "Deploy directory not found: $deployDir"
}

$targetTag = $RollbackTag
if ([string]::IsNullOrWhiteSpace($targetTag)) {
  if ($config.ContainsKey("ROLLBACK_IMAGE_TAG") -and -not [string]::IsNullOrWhiteSpace($config["ROLLBACK_IMAGE_TAG"])) {
    $targetTag = $config["ROLLBACK_IMAGE_TAG"]
  }
}

if ([string]::IsNullOrWhiteSpace($targetTag)) {
  throw "Rollback tag not provided. Set ROLLBACK_IMAGE_TAG in config or pass -RollbackTag"
}

$rollbackImage = "$imageRepo`:$targetTag"

$envFile = Join-Path $deployDir ".env"
$envLocalFile = Join-Path $deployDir ".env.local"

Write-Step "Switching ZEALOT_IMAGE to rollback image"
Set-Or-Add-EnvLine -FilePath $envFile -Key "ZEALOT_IMAGE" -Value $rollbackImage
Set-Or-Add-EnvLine -FilePath $envLocalFile -Key "ZEALOT_IMAGE" -Value $rollbackImage

Push-Location $deployDir
try {
  Write-Step "Pulling rollback image"
  docker compose -f docker-compose.local.yml pull zealyn

  Write-Step "Recreating service"
  docker compose -f docker-compose.local.yml up -d --force-recreate zealyn

  Write-Step "Service status"
  docker compose -f docker-compose.local.yml ps

  Write-Step "Health check: localhost"
  curl.exe -i "http://localhost:$serverPort$healthPath"
}
finally {
  Pop-Location
}

Write-Step "Done"
Write-Host "Rollback success with image: $rollbackImage" -ForegroundColor Green
