#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds fieldkit.slnx and packs every package into artifacts/packages.
.EXAMPLE
    ./build.ps1
.EXAMPLE
    ./build.ps1 -Configuration Debug
#>
param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$solution = 'fieldkit.slnx'
$packages = Join-Path $PSScriptRoot 'artifacts/packages'

function Invoke-Dotnet {
    & dotnet @args
    if ($LASTEXITCODE -ne 0) { throw "dotnet $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

# start from an empty output folder, so only this build's packages are in it
if (Test-Path $packages) { Remove-Item $packages -Recurse -Force }

Invoke-Dotnet restore $solution
Invoke-Dotnet build $solution --configuration $Configuration --no-restore '-p:FieldKitRelease=true'
Invoke-Dotnet pack $solution --configuration $Configuration --no-build '-p:FieldKitRelease=true'

Write-Host ''
Write-Host "Packages in ${packages}:"
Get-ChildItem $packages -Filter '*.*nupkg' | ForEach-Object { Write-Host "  $($_.Name)" }
