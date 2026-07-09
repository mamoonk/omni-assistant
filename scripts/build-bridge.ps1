# Cross-compiles the Nexus Bridge for all supported targets into dist/.
# Usage: powershell -File scripts/build-bridge.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bridge = Join-Path $root 'bridge'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

$targets = @(
    @{ os = 'linux';   arch = 'arm64'; name = 'nexus-bridge-linux-arm64' },      # Raspberry Pi 4/5
    @{ os = 'linux';   arch = 'amd64'; name = 'nexus-bridge-linux-amd64' },
    @{ os = 'darwin';  arch = 'arm64'; name = 'nexus-bridge-darwin-arm64' },
    @{ os = 'windows'; arch = 'amd64'; name = 'nexus-bridge-windows-amd64.exe' }
)

Set-Location $bridge
foreach ($t in $targets) {
    $env:GOOS = $t.os
    $env:GOARCH = $t.arch
    $env:CGO_ENABLED = '0'
    $out = Join-Path $dist $t.name
    Write-Host "building $($t.name)..."
    go build -trimpath -ldflags '-s -w' -o $out .
    if (-not $?) { exit 1 }
}
Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED -ErrorAction SilentlyContinue
Write-Host "done -> $dist"
