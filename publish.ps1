
Test-ModuleManifest -Path ".\PugPS\PugPS.psd1"
pause
Publish-Module -Path ".\PugPS" -NuGetApiKey $env:NUGET_API_KEY -Verbose

<#
# find module
Find-Module PugPS

# install test
Install-Module PugPS -Scope CurrentUser

# Import test
Import-Module PugPS
#>



<# 
New-ModuleManifest -Path ".\PugPS\PugPS.psd1" `
    -RootModule "PugPS.psm1" `
    -Author "Nabil Redmann (BananaAcid)" `
    -Description "Unleash Pug templates in PowerShell. A versatile CLI for HTML pipelines and a loyal View Engine for your Pode Server projects. 🐾" `
    -CompanyName "Nabil Redmann" `
    -ModuleVersion "1.0.0" `
    -FunctionsToExport "*" `
    -PowerShellVersion "5.1"
#>