<#
.SYNOPSIS
    PugPS - A Pug to HTML converter for PowerShell and Pode.
    
.DESCRIPTION
    Copyright (c) 2026 Nabil Redmann
    Licensed under the MIT License.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files.
#>

# This is the Root Module that loads all components

. $PSScriptRoot\CLI.ps1
. $PSScriptRoot\pode-pug-engine.ps1

Export-ModuleMember -Function 'Invoke-PUG', 'Set-PodeViewEnginePug'