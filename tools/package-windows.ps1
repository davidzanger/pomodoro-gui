param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rustProject = (Resolve-Path (Join-Path $projectRoot '..\..\pomodoro')).Path
$launcherManifest = Join-Path $PSScriptRoot 'single-file-launcher\Cargo.toml'
$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$payloadArchive = Join-Path $projectRoot 'build\pomodoro-payload.zip'
$outputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

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

    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows release build failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path (Join-Path $releaseDirectory 'pomodoro_gui_native.dll'))) {
        throw 'The FRB native library is missing from the Flutter release output.'
    }

    if (Test-Path $payloadArchive) {
        Remove-Item -LiteralPath $payloadArchive -Force
    }
    Compress-Archive -Path (Join-Path $releaseDirectory '*') `
        -DestinationPath $payloadArchive -CompressionLevel Optimal

    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $env:POMODORO_PAYLOAD_ZIP = $payloadArchive
    cargo build --release --manifest-path $launcherManifest
    if ($LASTEXITCODE -ne 0) {
        throw "Self-extractor build failed with exit code $LASTEXITCODE."
    }

    $launcher = Join-Path (Split-Path $launcherManifest -Parent) 'target\release\pomodoro_gui_launcher.exe'
    $distributionFile = Join-Path $outputDirectory 'Pomodoro.exe'
    Copy-Item -LiteralPath $launcher -Destination $distributionFile -Force
    Write-Output "Created single-file package: $distributionFile"
}
finally {
    Remove-Item Env:\POMODORO_PAYLOAD_ZIP -ErrorAction SilentlyContinue
    if (Test-Path $payloadArchive) {
        Remove-Item -LiteralPath $payloadArchive -Force
    }
    Pop-Location
}
