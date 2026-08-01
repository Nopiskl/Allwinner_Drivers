param(
    [string]$Workspace = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path,
    [string]$ArchiveName = "radxa-a7a-meizu-e3-pre-t4-handoff-20260731.tar.gz"
)

$ErrorActionPreference = "Stop"
$workspaceRoot = [System.IO.Path]::GetFullPath($Workspace).TrimEnd("\")
$handoffRoot = Join-Path $workspaceRoot "handoff"
$archiveDirectory = Join-Path $handoffRoot "archives"
$archivePath = Join-Path $archiveDirectory $ArchiveName
$archiveHashPath = "$archivePath.sha256"
$fileListPath = Join-Path $handoffRoot "PORTABLE_FILE_LIST.txt"
$manifestPath = Join-Path $handoffRoot "PORTABLE_SHA256SUMS.txt"

if (-not (Test-Path -LiteralPath $handoffRoot -PathType Container)) {
    throw "Missing handoff directory: $handoffRoot"
}
if (-not (Test-Path -LiteralPath $archiveDirectory)) {
    New-Item -ItemType Directory -Path $archiveDirectory | Out-Null
}
if (Test-Path -LiteralPath $archivePath) {
    throw "Refusing to overwrite existing archive: $archivePath"
}

$directoryTargets = @(
    "handoff",
    "log",
    "radxa-meizu-e3",
    "meizu-e3-dkms_0.1.6_all.unpacked",
    "meizu-e3-dkms_0.1.7_staging",
    "meizu-e3-dkms_0.1.8_staging",
    "meizu-e3-dkms_0.1.9_staging",
    "meizu-e3-dkms_0.1.10_staging",
    "radxa-overlays-official",
    "radxa-allwinner-bsp",
    "radxa-allwinner-device-a733"
)

$rootFilePatterns = @(
    "*.md",
    "*.sh",
    "*.ps1",
    "*.service",
    "*.conf",
    "*.deb",
    "*.dtso",
    "*.tar.gz",
    "radxa-reflash-known-hosts",
    "radxa-netconsole.log"
)

function Get-WorkspaceRelativePath {
    param([Parameter(Mandatory = $true)][string]$FullName)
    $resolved = [System.IO.Path]::GetFullPath($FullName)
    if (-not $resolved.StartsWith(
        $workspaceRoot + "\",
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Path escaped workspace: $resolved"
    }
    return $resolved.Substring($workspaceRoot.Length + 1).Replace("\", "/")
}

$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($relativeTarget in $directoryTargets) {
    $target = Join-Path $workspaceRoot $relativeTarget
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        continue
    }
    foreach ($file in Get-ChildItem -LiteralPath $target -Recurse -File -Force) {
        $relative = Get-WorkspaceRelativePath $file.FullName
        if ($relative -match '(^|/)\.git(/|$)') {
            continue
        }
        if ($relative -like "handoff/archives/*") {
            continue
        }
        if ($relative -like "handoff/snapshots/*/extracted/*") {
            continue
        }
        if ($relative -match '(^|/)__pycache__(/|$)') {
            continue
        }
        if ($relative -in @(
            "handoff/PORTABLE_FILE_LIST.txt",
            "handoff/PORTABLE_SHA256SUMS.txt"
        )) {
            continue
        }
        $files.Add($file)
    }
}

foreach ($pattern in $rootFilePatterns) {
    foreach ($file in Get-ChildItem -LiteralPath $workspaceRoot -File -Filter $pattern) {
        $files.Add($file)
    }
}

$uniqueFiles = $files |
    Sort-Object FullName -Unique
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$checksumLines = foreach ($file in $uniqueFiles) {
    $relative = Get-WorkspaceRelativePath $file.FullName
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
}
[System.IO.File]::WriteAllLines($manifestPath, $checksumLines, $utf8NoBom)

$finalRelativeFiles = @(
    $uniqueFiles | ForEach-Object { Get-WorkspaceRelativePath $_.FullName }
    "handoff/PORTABLE_SHA256SUMS.txt"
    "handoff/PORTABLE_FILE_LIST.txt"
) | Sort-Object -Unique
[System.IO.File]::WriteAllLines($fileListPath, $finalRelativeFiles, $utf8NoBom)

Push-Location $workspaceRoot
try {
    $archiveTargets = @(
        $directoryTargets | Where-Object {
            Test-Path -LiteralPath (Join-Path $workspaceRoot $_)
        }
        $uniqueFiles |
            Where-Object { $_.DirectoryName -eq $workspaceRoot } |
            ForEach-Object { $_.Name }
    ) | Sort-Object -Unique

    & tar.exe -czf $archivePath `
        "--exclude=*/.git" `
        "--exclude=*/.git/*" `
        "--exclude=handoff/archives" `
        "--exclude=handoff/archives/*" `
        "--exclude=handoff/snapshots/*/extracted" `
        "--exclude=handoff/snapshots/*/extracted/*" `
        "--exclude=*/__pycache__" `
        "--exclude=*/__pycache__/*" `
        @archiveTargets
    if ($LASTEXITCODE -ne 0) {
        if (
            $archivePath.StartsWith(
                $archiveDirectory + "\",
                [System.StringComparison]::OrdinalIgnoreCase
            ) -and
            (Test-Path -LiteralPath $archivePath -PathType Leaf)
        ) {
            Remove-Item -LiteralPath $archivePath -Force
        }
        throw "tar.exe failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$archiveBytes = (Get-Item -LiteralPath $archivePath).Length
[System.IO.File]::WriteAllText(
    $archiveHashPath,
    "$archiveHash  $ArchiveName`n",
    $utf8NoBom
)

[pscustomobject]@{
    Archive = $archivePath
    Bytes = $archiveBytes
    Files = $finalRelativeFiles.Count
    SHA256 = $archiveHash
    HashFile = $archiveHashPath
}
