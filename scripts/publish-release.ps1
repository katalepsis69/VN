param(
    [string]$Version,
    [string]$Changelog,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
Set-Location $rootDir

$projectGodot = Join-Path $rootDir "project.godot"
if (-not (Test-Path $projectGodot)) {
    Write-Error "project.godot not found at $projectGodot"
}

# 1. Determine base version from latest Git tag, fallback to project.godot
$latestTag = ""
$tagOutput = git tag --sort=-v:refname 2>$null
if ($tagOutput) {
    $latestTag = ($tagOutput | Select-Object -First 1)
}
$baseVer = ""
if (-not [string]::IsNullOrWhiteSpace($latestTag)) {
    $baseVer = $latestTag.TrimStart('v', 'V')
} else {
    $content = Get-Content $projectGodot -Raw
    if ($content -match 'config/version="([^"]+)"') {
        $baseVer = $matches[1]
    } else {
        $baseVer = "1.0"
    }
}

# 2. 2-digit version calculation (e.g. 1.0 -> 1.1 -> 1.2)
function Get-NextVersion([string]$current, [string]$bump) {
    $clean = $current.TrimStart('v', 'V')
    $parts = $clean.Split('.')
    [int]$major = if ($parts.Length -gt 0) { [int]$parts[0] } else { 1 }
    [int]$minor = if ($parts.Length -gt 1) { [int]$parts[1] } else { 0 }

    switch ($bump.ToLowerInvariant()) {
        "major" { return "$($major + 1).0" }
        "minor" { return "$major.$($minor + 1)" }
        default {
            if ($bump -match '^\d+(\.\d+)*$') { return $bump.TrimStart('v', 'V') }
            return "$major.$($minor + 1)"
        }
    }
}

$cleanVer = if ([string]::IsNullOrWhiteSpace($Version)) {
    Get-NextVersion $baseVer "minor"
} else {
    Get-NextVersion $baseVer $Version
}

$tag = "v$cleanVer"

# Interactive prompt if running manually
if ([string]::IsNullOrWhiteSpace($Version) -and -not $NonInteractive -and [Environment]::UserInteractive) {
    $entry = Read-Host "Publish version (Enter = $cleanVer, or type custom like $baseVer)"
    if (-not [string]::IsNullOrWhiteSpace($entry)) {
        $cleanVer = Get-NextVersion $baseVer $entry.Trim()
        $tag = "v$cleanVer"
    }
}

Write-Host "Publishing version $tag..." -ForegroundColor Cyan

# 3. Update version in project.godot and scripts/updater.gd
$godotTxt = Get-Content $projectGodot -Raw
if ($godotTxt -match 'config/version="[^"]+"') {
    $godotTxt = $godotTxt -replace 'config/version="[^"]+"', "config/version=`"$cleanVer`""
} else {
    $godotTxt = $godotTxt -replace '(\[application\]\s*)', "`$1config/version=`"$cleanVer`"`r`n"
}
[System.IO.File]::WriteAllText($projectGodot, $godotTxt)

$updaterPath = Join-Path $rootDir "scripts\updater.gd"
if (Test-Path $updaterPath) {
    $updaterTxt = Get-Content $updaterPath -Raw
    $updaterTxt = $updaterTxt -replace 'const CURRENT_VERSION := "[^"]+"', "const CURRENT_VERSION := `"$cleanVer`""
    [System.IO.File]::WriteAllText($updaterPath, $updaterTxt)
}

# 4. Check for pending git changes and commit
$pending = & git status --porcelain
if ($pending) {
    Write-Host "Committing pending changes..." -ForegroundColor Yellow
    $commitMsg = "Release $tag"
    if (-not [string]::IsNullOrWhiteSpace($Changelog)) {
        $commitMsg = "Release ${tag}: $Changelog"
    }
    & git add -A
    & git commit -m $commitMsg --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git commit failed."
    }
}

# 5. Build executable using Godot
Write-Host "[1/4] Exporting VNReader.exe..." -ForegroundColor Yellow
$godotBin = "C:/Users/sloth/Downloads/Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godotBin)) {
    Write-Error "Godot binary not found at $godotBin"
}

$buildDir = Join-Path $rootDir "build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

$exportOutput = & $godotBin --headless --path . --export-release "Windows Desktop" "build/VNReader.exe" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Godot export failed: $exportOutput"
}

$exePath = Join-Path $buildDir "VNReader.exe"
if (-not (Test-Path $exePath)) {
    Write-Error "VNReader.exe was not produced at $exePath"
}
$exeSize = (Get-Item $exePath).Length
Write-Host "Executable built: $exePath ($exeSize bytes)" -ForegroundColor Green

# 6. Package standalone zip for fresh users
Write-Host "[2/4] Packaging release zip..." -ForegroundColor Yellow
$zipPath = Join-Path $buildDir "VNReader-$tag.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$tempPackageDir = Join-Path $env:TEMP "VNReader_pack_$tag"
if (Test-Path $tempPackageDir) { Remove-Item $tempPackageDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempPackageDir | Out-Null

Copy-Item $exePath -Destination $tempPackageDir
foreach ($dll in @("pdfium.dll", "pdfium-gde.windows.template_release.x86_64.dll")) {
    $dllPath = Join-Path $buildDir $dll
    if (Test-Path $dllPath) {
        Copy-Item $dllPath -Destination $tempPackageDir
    }
}

# Include user folders structure
foreach ($folder in @("My Backgrounds", "My Books", "My Fonts", "My Sounds", "My Sprites")) {
    $srcFolder = Join-Path $rootDir $folder
    if (Test-Path $srcFolder) {
        Copy-Item $srcFolder -Destination $tempPackageDir -Recurse
    }
}

Compress-Archive -Path "$tempPackageDir\*" -DestinationPath $zipPath -Force
Remove-Item $tempPackageDir -Recurse -Force
Write-Host "Release zip created: $zipPath" -ForegroundColor Green

# 7. Authenticate with GitHub
Write-Host "[3/4] Authenticating with GitHub..." -ForegroundColor Yellow
$token = $env:GITHUB_TOKEN

if ([string]::IsNullOrWhiteSpace($token)) {
    try {
        $credInput = "protocol=https`nhost=github.com`nusername=katalepsis69`n"
        $credOutput = $credInput | git credential fill 2>$null | Out-String
        if ($credOutput -match "password=(.+)") {
            $token = $matches[1].Trim()
        }
    } catch {
        Write-Warning "Could not query Git Credential Manager: $_"
    }
}

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "No GitHub token found. Authenticate Git or set GITHUB_TOKEN."
}

$repo = "katalepsis69/VN"
$headers = @{
    Authorization = "Bearer $token"
    "User-Agent"  = "VNReader-Publisher"
    Accept        = "application/vnd.github+json"
}

# 8. Push Git tag & branch
Write-Host "[4/4] Pushing source and tag $tag to GitHub..." -ForegroundColor Yellow
& git push origin main
if ($LASTEXITCODE -ne 0) {
    # If remote doesn't have main yet, push with -u
    & git push -u origin main
    if ($LASTEXITCODE -ne 0) {
        throw "git push origin main failed. Fix remote and re-run."
    }
}
& git tag -f $tag
& git push -f origin $tag
if ($LASTEXITCODE -ne 0) {
    throw "git push tag $tag failed. Fix remote and re-run."
}

# 9. Create or update GitHub Release
$releaseNotes = if (-not [string]::IsNullOrWhiteSpace($Changelog)) { $Changelog } else { "Release $tag for ADHD VN Reader." }

$releasePayload = @{
    tag_name         = $tag
    target_commitish = "main"
    name             = "VN Reader $tag"
    body             = $releaseNotes
    draft            = $false
    prerelease       = $false
} | ConvertTo-Json

$releaseUrl = "https://api.github.com/repos/$repo/releases"
$releaseObj = $null

try {
    $releaseObj = Invoke-RestMethod -Uri $releaseUrl -Method Post -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($releasePayload)) -ContentType "application/json; charset=utf-8"
} catch {
    Write-Host "Release $tag exists, updating..." -ForegroundColor Cyan
    $releaseObj = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/tags/$tag" -Headers $headers
    $patchPayload = @{
        tag_name = $tag
        name     = "VN Reader $tag"
        body     = $releaseNotes
    } | ConvertTo-Json
    $releaseObj = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/$($releaseObj.id)" -Method Patch -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($patchPayload)) -ContentType "application/json; charset=utf-8"
}

# Helper to upload asset
function Upload-ReleaseAsset([object]$rel, [string]$filePath, [string]$contentType) {
    $fileName = [System.IO.Path]::GetFileName($filePath)
    if ($rel.assets) {
        foreach ($a in $rel.assets) {
            if ($a.name -eq $fileName) {
                Write-Host "Replacing existing asset $fileName..." -ForegroundColor Cyan
                Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/assets/$($a.id)" -Method Delete -Headers $headers
            }
        }
    }

    $uploadUrl = $rel.upload_url -replace '\{\?name,label\}', "?name=$fileName"
    Write-Host "Uploading $fileName..." -ForegroundColor Yellow
    $uploadResp = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers @{
        Authorization  = "Bearer $token"
        "User-Agent"   = "VNReader-Publisher"
        "Content-Type" = $contentType
    } -InFile $filePath
    return $uploadResp
}

# Upload raw exe (for in-app 1-click updater)
$exeUpload = Upload-ReleaseAsset $releaseObj $exePath "application/octet-stream"

# Upload zip (for fresh downloads)
$zipUpload = Upload-ReleaseAsset $releaseObj $zipPath "application/zip"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host " Release $tag is live on GitHub!        " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Release Page: $($releaseObj.html_url)"
Write-Host "Executable:   $($exeUpload.browser_download_url)"
Write-Host "Zip Archive:  $($zipUpload.browser_download_url)"
Write-Host ""
