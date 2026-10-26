param(
  [string]$ConfigPath = ".\\customer.release.env",
  [switch]$SkipLogin,
  [switch]$SkipPull
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "`n==> $Message" -ForegroundColor Cyan
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

function Invoke-Deploy {
  param(
    [string]$DeployDir,
    [string]$ServerPort,
    [string]$HealthPath,
    [bool]$SkipImagePull
  )

  Push-Location $DeployDir
  try {
    if (-not $SkipImagePull) {
      Write-Step "Pulling image"
      docker compose -f docker-compose.local.yml pull zealyn
    }
    else {
      Write-Step "Skip pull enabled; using local image cache"
    }

    Write-Step "Recreating service"
    if ($SkipImagePull) {
      docker compose -f docker-compose.local.yml up -d --force-recreate --pull never zealyn
    }
    else {
      docker compose -f docker-compose.local.yml up -d --force-recreate zealyn
    }

    Write-Step "Service status"
    docker compose -f docker-compose.local.yml ps

    Write-Step "Health check: localhost"
    curl.exe -i "http://localhost:$ServerPort$HealthPath"
  }
  finally {
    Pop-Location
  }
}

Write-Step "Loading config"
$config = Read-Config -Path $ConfigPath

$requiredKeys = @(
  "CLIENT_DEPLOY_DIR",
  "CLIENT_SERVER_PORT",
  "CLIENT_HEALTH_PATH",
  "GHCR_USER",
  "IMAGE_REPO",
  "IMAGE_TAG"
)

foreach ($key in $requiredKeys) {
  Require-Key -Config $config -Key $key
}

$deployDir = $config["CLIENT_DEPLOY_DIR"]
$serverPort = $config["CLIENT_SERVER_PORT"]
$healthPath = $config["CLIENT_HEALTH_PATH"]
$ghcrUser = $config["GHCR_USER"]
$image = "$($config["IMAGE_REPO"]):$($config["IMAGE_TAG"])"

$envFile = Join-Path $deployDir ".env"
$envLocalFile = Join-Path $deployDir ".env.local"

if (-not (Test-Path -LiteralPath $deployDir)) {
  throw "Deploy directory not found: $deployDir"
}

if (-not $SkipLogin) {
  Write-Step "Logging in to GHCR"
  $pat = ""
  if ($config.ContainsKey("GHCR_PAT")) {
    $pat = $config["GHCR_PAT"]
  }

  if ([string]::IsNullOrWhiteSpace($pat)) {
    docker login ghcr.io -u $ghcrUser
  }
  else {
    $pat | docker login ghcr.io -u $ghcrUser --password-stdin
  }
}

Write-Step "Updating ZEALOT_IMAGE in env files"
Set-Or-Add-EnvLine -FilePath $envFile -Key "ZEALOT_IMAGE" -Value $image
Set-Or-Add-EnvLine -FilePath $envLocalFile -Key "ZEALOT_IMAGE" -Value $image

# Optional business URL settings are updated only if keys exist and have values.
if ($config.ContainsKey("CLIENT_DOMAIN") -and -not [string]::IsNullOrWhiteSpace($config["CLIENT_DOMAIN"])) {
  Set-Or-Add-EnvLine -FilePath $envLocalFile -Key "ZEALOT_DOMAIN" -Value $config["CLIENT_DOMAIN"]
}

if ($config.ContainsKey("CLIENT_SERVER_IP") -and -not [string]::IsNullOrWhiteSpace($config["CLIENT_SERVER_IP"])) {
  Set-Or-Add-EnvLine -FilePath $envLocalFile -Key "ZEALOT_HOST" -Value $config["CLIENT_SERVER_IP"]
}

if ($config.ContainsKey("CLIENT_SERVER_PORT") -and -not [string]::IsNullOrWhiteSpace($config["CLIENT_SERVER_PORT"])) {
  Set-Or-Add-EnvLine -FilePath $envLocalFile -Key "ZEALOT_PORT" -Value $config["CLIENT_SERVER_PORT"]
}

if ($config.ContainsKey("API_BASE_URL") -and -not [string]::IsNullOrWhiteSpace($config["API_BASE_URL"])) {
  Set-Or-Add-EnvLine -FilePath $envLocalFile -Key "API_BASE_URL" -Value $config["API_BASE_URL"]
}

Invoke-Deploy -DeployDir $deployDir -ServerPort $serverPort -HealthPath $healthPath -SkipImagePull:$SkipPull

Write-Step "Done"
Write-Host "Deploy success with image: $image" -ForegroundColor Green
