param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist'),
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustProject = (Resolve-Path (Join-Path $projectRoot '..\pomodoro')).Path
$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$outputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$stagingDirectory = Join-Path $projectRoot (Join-Path 'build' ([System.IO.Path]::GetRandomFileName()))

if (-not (Test-Path (Join-Path $rustProject 'Cargo.toml'))) {
    throw "Rust project manifest was not found at $rustProject."
}

Push-Location $projectRoot
try {
    if (-not (Test-Path (Join-Path $projectRoot 'windows\CMakeLists.txt'))) {
        flutter create --platforms=windows --no-pub .
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Windows runner generation failed with exit code $LASTEXITCODE."
        }
    }

    if (-not $SkipBuild) {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Windows release build failed with exit code $LASTEXITCODE."
        }
    }

    if (-not (Test-Path (Join-Path $releaseDirectory 'pomodoro_gui.exe')) -or
        -not (Test-Path (Join-Path $releaseDirectory 'flutter_windows.dll')) -or
        -not (Test-Path (Join-Path $releaseDirectory 'pomodoro_gui_native.dll')) -or
        -not (Test-Path (Join-Path $releaseDirectory 'data') -PathType Container)) {
        throw 'The Flutter release output is missing required runtime files.'
    }

    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $packageDirectory = Join-Path $stagingDirectory 'Pomodoro'
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
    Copy-Item -Path (Join-Path $releaseDirectory '*') -Destination $packageDirectory -Recurse -Force

    $distributionFile = Join-Path $outputDirectory 'Pomodoro.zip'
    Compress-Archive -LiteralPath $packageDirectory -DestinationPath $distributionFile `
        -CompressionLevel Optimal -Force
    Write-Output "Created Windows package: $distributionFile"
}
finally {
    $buildDirectory = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'build'))
    $stagingPath = [System.IO.Path]::GetFullPath($stagingDirectory)
    if (-not $stagingPath.StartsWith($buildDirectory + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Staging directory is outside the build directory: $stagingPath"
    }
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
    Pop-Location
}
