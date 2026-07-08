#Requires -Version 5.1
<#
.SYNOPSIS
    Replace the bundled libmpv-2.dll on Windows with the full shinchiro build to enable PGS/SUP bitmap subtitles.

.DESCRIPTION
    media-kit's Windows libmpv prebuild disables most FFmpeg decoders, including hdmv_pgs_subtitle,
    so PGS/SUP graphic subtitles are silently dropped. This script downloads shinchiro's full mpv dev
    package and replaces libmpv-2.dll in the Flutter Windows build output.

    Usage after build:
        .\windows\scripts\upgrade_libmpv_for_pgs.ps1

    From CMake build this script runs by default. To skip, set:
        $env:LINPLAYER_SKIP_LIBMPV_UPGRADE = "1"
        flutter build windows

.PARAMETER BuildOutput
    Flutter Windows build output directory. If omitted, Release/Debug under build/windows/x64/runner are searched.

.PARAMETER DownloadUrl
    Direct URL to a shinchiro mpv-dev-x86_64 .7z archive. Defaults to the latest known release.
#>
[CmdletBinding()]
param(
    [string]$BuildOutput = "",
    [string]$DownloadUrl = "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20260610/mpv-dev-x86_64-20260610-git-304426c.7z"
)

$ErrorActionPreference = "Stop"

function Find-BuildOutputDirectory {
    param([string]$hint)
    if ($hint -and (Test-Path -LiteralPath $hint)) {
        return $hint
    }
    $candidates = @(
        "..\..\build\windows\x64\runner\Release"
        "..\..\build\windows\x64\runner\Debug"
    )
    foreach ($c in $candidates) {
        $p = Join-Path $PSScriptRoot $c
        if (Test-Path -LiteralPath $p) {
            return $p
        }
    }
    throw "Flutter Windows build output directory not found. Please specify -BuildOutput."
}

function Invoke-DownloadFile {
    param([string]$url, [string]$outFile)
    Write-Host "Downloading full libmpv package: $url"
    $progressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
    } finally {
        $ProgressPreference = $progressPreference
    }
    if (-not (Test-Path -LiteralPath $outFile)) {
        throw "Download failed: $outFile does not exist"
    }
    Write-Host "Downloaded: $outFile ($((Get-Item $outFile).Length) bytes)"
}

function Expand-SevenZipArchive {
    param([string]$archive, [string]$destination)
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if ($tar) {
        Write-Host "Extracting with tar: $archive"
        & tar -xf "$archive" -C "$destination"
        if ($LASTEXITCODE -ne 0) {
            throw "tar extraction failed (exit=$LASTEXITCODE)"
        }
        return
    }
    $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
    if (-not $sevenZip) {
        $sevenZip = Get-Command "${env:ProgramFiles}\7-Zip\7z.exe" -ErrorAction SilentlyContinue
    }
    if (-not $sevenZip) {
        $sevenZip = Get-Command "${env:ProgramFiles(x86)}\7-Zip\7z.exe" -ErrorAction SilentlyContinue
    }
    if (-not $sevenZip) {
        throw "Neither tar nor 7-Zip found. Install 7-Zip or use Windows 11 to extract .7z files."
    }
    Write-Host "Extracting with 7-Zip: $archive"
    & $sevenZip x "$archive" -o"$destination" -y
    if ($LASTEXITCODE -ne 0) {
        throw "7z extraction failed (exit=$LASTEXITCODE)"
    }
}

function Get-LibmpvDllPath {
    param([string]$extractDir)
    $dll = Get-ChildItem -Path $extractDir -Recurse -Filter "libmpv-2.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dll) {
        throw "libmpv-2.dll not found in extracted archive"
    }
    return $dll.FullName
}

# ---------------------------------------------------------------------------
$outDir = Find-BuildOutputDirectory $BuildOutput
Write-Host "Target directory: $outDir"

$targetDll = Join-Path $outDir "libmpv-2.dll"
if (-not (Test-Path -LiteralPath $targetDll)) {
    throw "libmpv-2.dll not found in target directory. Run 'flutter build windows' first."
}

$backup = "$targetDll.orig"
if ((Test-Path -LiteralPath $backup) -and (Test-Path -LiteralPath $targetDll)) {
    $targetInfo = Get-Item -LiteralPath $targetDll
    $backupInfo = Get-Item -LiteralPath $backup
    if ($targetInfo.Length -gt $backupInfo.Length) {
        Write-Host "libmpv-2.dll 已经是完整版，跳过升级。"
        return
    }
}

$tempRoot = Join-Path $env:TEMP "linplayer_libmpv_upgrade"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$archiveFile = Join-Path $tempRoot "mpv-dev-full.7z"
$extractDir = Join-Path $tempRoot "mpv-dev-full"

if (Test-Path -LiteralPath $archiveFile) {
    Remove-Item -LiteralPath $archiveFile -Force
}
if (Test-Path -LiteralPath $extractDir) {
    Remove-Item -LiteralPath $extractDir -Recurse -Force
}

Invoke-DownloadFile -url $DownloadUrl -outFile $archiveFile
Expand-SevenZipArchive -archive $archiveFile -destination $extractDir
$sourceDll = Get-LibmpvDllPath -extractDir $extractDir

$backup = "$targetDll.orig"
if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $targetDll -Destination $backup -Force
    Write-Host "Backed up original libmpv-2.dll to $backup"
}

Copy-Item -LiteralPath $sourceDll -Destination $targetDll -Force
Write-Host "Replaced libmpv-2.dll with the full build. PGS/SUP decoder (hdmv_pgs_subtitle) should now be available."

Remove-Item -LiteralPath $archiveFile -Force
Remove-Item -LiteralPath $extractDir -Recurse -Force
Write-Host "Temporary files cleaned up."
