<#
.SYNOPSIS
    PugPS - A Pug to HTML converter for PowerShell and Pode.
    
.DESCRIPTION
    Copyright (c) 2026 Nabil Redmann
    Licensed under the MIT License.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files.
#>

# @{ filenameStr.. = @{sb = scriptblock; LastWriteTime = datetime, Dependencies = @{filenamestr.. = fileinfo}} }
$cache = [Hashtable]@{}

# ADD a view engine for Pug, and SET as default and only view engine for files without extension
# inbuild engines can still be used, if `Write-PodeViewResponse -Path 'index.EXTENSION'` is used
Function Set-PodeViewEnginePug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Extension,

        [Parameter(Mandatory=$false, HelpMessage="The root directory used to resolve absolute include/extend paths (those starting with / or \). If empty, absolute paths are resolved relative to the current file.")]
        [string]$BaseDir = "",

        [Parameter(Mandatory=$false, HelpMessage="The path to the filters file (ps1) to be imported or a scriptblock with the filter functions.")]
        [AllowNull()]
        $Filters = $Null,

        [Parameter(Mandatory=$false, HelpMessage="When true (default), boolean attributes are rendered as 'attr'. When false, they are rendered as 'attr=''attr'''.")]
        [bool]$Properties = $true,

        [Parameter(Mandatory=$false, HelpMessage="When true, standard void tags (like img, br) are rendered with a self-closing slash (e.g., <img />). Default is false.")]
        [bool]$VoidTagsSelfClosing = $false,

        [Parameter(Mandatory=$false, HelpMessage="When true, empty container tags (like div, span) with no content or children are rendered as self-closing (e.g., <div />). Default is false.")]
        [bool]$ContainerTagsSelfClosing = $false,

        [Parameter(Mandatory=$false, HelpMessage="When true, CamelCase in PUG is converted to kebab-case. Default is true.")]
        [bool]$KebabCaseHTML = $true,

        [Parameter(Mandatory=$false, HelpMessage="When text, an empty page with ony the error is generated, if `"rethrow`" is used, the Pode errorpage for 422 is triggered. Default is `"text`".")]
        [ValidateSet("text", "rethrow")]
        [string]$ErrorOutput = "rethrow",
        
        [Parameter(Mandatory=$false, HelpMessage="Number of context lines to show before and after the error line.")]
        [int]$ErrorContextRange = 2,

        [Parameter(Mandatory=$false, HelpMessage="When true, the internal cache is not used. Default is false.")]
        [switch]$NoCache = $false,

        [Parameter(Mandatory=$false, HelpMessage="Debug switch for showing cache info.")]
        [switch]$CacheDebug = $false,

        [Parameter(Mandatory=$false, HelpMessage="Debug switch for saving converted PUG content.")]
        [switch]$ConvertDebug = $false
    )

    Set-PodeViewEngine -Type 'Pug' -Extension $Extension -ScriptBlock {
        param($path, $data)

        # Ensure parser functions are available
        . $using:PSScriptRoot\parser.ps1

        if ([string]::IsNullOrWhiteSpace($using:Filters)) {
            # param not used.
        }
        # 1. Import filter from scriptblock
        # elseif (($using:Filters).getType().Name -eq 'ScriptBlock') {
        #     . ($using:Filters)

        #     write-host "Filters imported : " ($using:Filters).ToString()
        #     #! WHY DOES THIS NOT WORK ??
        #     write-host "Filters fn exists : ", ((Get-Command "TestFN2") ?  "True" : "False")
        # }
        # 1. Import filters file if it exists
        elseif (($using:Filters).getType().Name -eq 'String' -and (Test-Path (Join-Path $PWD $using:Filters) -PathType Leaf)) {
            . (Join-Path $PWD $using:Filters)
        }
        else {
            $exFn = New-Object System.Exception("Filters not found: " + $using:Filters)
            throw $exFn
        }

        try {
            $cached = $false

            if (-not $using:NoCache) {
                
                if ($using:CacheDebug) {
                    Write-Host ("[PUG:CACHE] Cache length: " + ($using:cache).Count) -ForegroundColor Green
                    Write-Host ("[PUG:CACHE] Check for $path - In cache: " + ($using:cache).ContainsKey($path)) -ForegroundColor Green
                }

                if (($using:cache).ContainsKey($path) -and `
                    ($using:cache)[$path].LastWriteTime -eq (Get-Item $path).LastWriteTime)
                {
                    $cached = $true
                    # 1. check for changed Dependencies
                    foreach ($dep in ($using:cache)[$path].Dependencies.GetEnumerator()) {
                        if ($using:CacheDebug) { Write-Host ("[PUG:CACHE]  - Check for $($dep.Key): unchanged ") -ForegroundColor Green -NoNewline }

                        if ($dep.Value.LastWriteTime -ne (Get-Item $dep.Key).LastWriteTime) {
                            if ($using:CacheDebug) { Write-Host "False" -ForegroundColor Red }
                            $cached = $false
                            break
                        }
                        else {
                            if ($using:CacheDebug) { Write-Host "True" -ForegroundColor Green }
                        }
                    }

                    if ($cached) {
                        if ($using:CacheDebug) { Write-Host "[PUG:CACHE] = Use cached" -ForegroundColor Green }
                        # 2. get from cache, is a created scriptblock
                        $sb = ($using:cache)[$path].sb                
                    }
                }
            }

            if (-not $cached) {
                $RefIncludes = @{}

                # 1. Transpile
                $psCode = Convert-PugToPowerShell `
                    -Path $path `
                    -Extension $using:Extension `
                    -BaseDir $using:BaseDir `
                    -Properties $using:Properties `
                    -VoidTagsSelfClosing $using:VoidTagsSelfClosing `
                    -ContainerTagsSelfClosing $using:ContainerTagsSelfClosing `
                    -KebabCaseHTML $using:KebabCaseHTML `
                    -ErrorContextRange $using:ErrorContextRange `
                    -RefIncludes $RefIncludes
                
                    
                if ($using:ConvertDebug) {
                    # Replace any problematic pathstr chars for filename
                    $tempdir = (Get-Item ([System.IO.Path]::GetTempPath())).FullName
                    $saveFilenamePath = $path -replace "[^a-zA-Z0-9]","_"
                    $tempFile = Join-Path $tempdir ("_generated_template_" + $saveFilenamePath + ".ps1")

                    # save to OS Temp with save filename
                    $psCode | Out-File $tempFile
                    Write-Host "[PUG:CONVERT] Generated file (for debugging): $tempFile" -ForegroundColor Green
                }

                
                # 2. Create ScriptBlock
                $sb = [scriptblock]::Create($psCode)

                if (-not $using:NoCache) {
                    ($using:cache)[$path] = @{sb = $sb; LastWriteTime = (Get-Item $path).LastWriteTime; Dependencies = $RefIncludes}

                    if ($using:CacheDebug) {
                        Write-Host "[PUG:CACHE] = Add to cache" -ForegroundColor Green
                        Write-Host ("[PUG:CACHE]   - Dependencies added: " + $RefIncludes.Count) -ForegroundColor Green
                    }
                }

            }

            # 3. Execute, passing $data into the scope
            $html = (& $sb $data)

            return $html

        }
        catch {
            # remove faulty scriptblock from cache
            if ($using:CacheDebug) { Write-Host "[PUG:CACHE] Error -> Remove $path" -ForegroundColor Green }
            ($using:cache).Remove($path)

            $ex = $_.Exception
            $niceMsg = ""

            # Check if this is a Parser-thrown error (already has custom data fields)
            if ($ex.Data.Contains('Line')) {
                # Just re-use the formatted message if it was a New-PugError
                $niceMsg = $ex.Message
            } 
            # Check if this is a Runtime-thrown error (caught inside the generated script)
            elseif ($ex.Data.Contains('PugLine') -and $ex.Data['PugLine'] -gt 0) {
                $runtimeLine = $ex.Data['PugLine']
                $runtimePath = $ex.Data['PugPath']
                
                # Use the parser helper to generate the nice message
                $niceMsg = Get-PugErrorContext `
                    -Path $runtimePath `
                    -LineNumber $runtimeLine `
                    -Detail $ex.Message `
                    -ContextRange $using:ErrorContextRange
            }
            else {
                # Fallback for errors that didn't get tracked
                $niceMsg = "An unexpected error occurred:`n$($ex.Message)`n$($ex.StackTrace)"
            }

            if ($using:ErrorOutput -eq "text") {
                # Set-PodeResponseStatus -Code 400+  --- pode will block output ... -NoErrorPage lets us output what we want
                Set-PodeResponseStatus -Code 422 -NoErrorPage
                # Set-PodeHeader -Name "Content-Type" -Value "text/plain" ... BROKEN ...
                # Return the clean message to be rendered as plain text
                $escapedMsg = [System.Net.WebUtility]::HtmlEncode($niceMsg)
                return "<pre>$escapedMsg</pre>"
            }
            else {
                # Rethrow specifically
                $newEx = New-Object System.Exception($niceMsg, $ex)
                throw $newEx
            }
        }
    }
}



#Export-ModuleMember -Function Set-PodeViewEnginePug