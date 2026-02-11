<#
.SYNOPSIS
    PugPS - A Pug to HTML converter for PowerShell and Pode.
    
.DESCRIPTION
    Copyright (c) 2026 Nabil Redmann
    Licensed under the MIT License.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files.
#>

Function Invoke-PUG {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(ParameterSetName='Path', Mandatory=$true, Position=0, HelpMessage="The path to the Pug template file.")]
        [string]$Path,

        [Parameter(ParameterSetName='Content', Mandatory=$true, ValueFromPipeline=$true, HelpMessage="The raw Pug template content.")]
        [string[]]$InputContent,

        [Parameter(ParameterSetName='Path', Mandatory=$false, Position=1, HelpMessage="The data to be passed to the Pug template as `$data. Can be a hashtable. Default is an empty hashtable.")]
        [Parameter(ParameterSetName='Content', Mandatory=$false, Position=0, HelpMessage="The data to be passed to the Pug template as `$data. Can be a hashtable. Default is an empty hashtable.")]
        [hashtable]$Data = @{},

        [Parameter(Mandatory=$false, HelpMessage="The path to the filters file (ps1) to be imported or a scriptblock with the filter functions.")]
        [AllowNull()]
        $Filters = $Null,

        [Parameter(Mandatory=$false, HelpMessage="The default file extension to use for included files if not specified.")]
        [string]$Extension = 'pug',

        [Parameter(Mandatory=$false, HelpMessage="The root directory used to resolve absolute include/extend paths (those starting with / or \). If empty, absolute paths are resolved relative to the current file.")]
        [string]$BaseDir = "",

        [Parameter(Mandatory=$false, HelpMessage="When true (default), boolean attributes are rendered as 'attr'. When false, they are rendered as 'attr=''attr'''.")]
        [bool]$Properties = $true,

        [Parameter(Mandatory=$false, HelpMessage="When true, standard void tags (like img, br) are rendered with a self-closing slash (e.g., <img />). Default is false.")]
        [bool]$VoidTagsSelfClosing = $false,

        [Parameter(Mandatory=$false, HelpMessage="When true, empty container tags (like div, span) with no content or children are rendered as self-closing (e.g., <div />). Default is false.")]
        [bool]$ContainerTagsSelfClosing = $false,

        [Parameter(Mandatory=$false, HelpMessage="When true, CamelCase in PUG is converted to kebab-case. Default is true.")]
        [bool]$KebabCaseHTML = $true,

        [Parameter(Mandatory=$false, HelpMessage="Number of context lines to show before and after the error line.")]
        [int]$ErrorContextRange = 2
    )

    begin {
        $accumulatedContent = New-Object System.Collections.Generic.List[string]
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Content') {
            if ($InputContent) {
                $accumulatedContent.AddRange($InputContent)
            }
        }
    }

    end {
        . $PSScriptRoot\parser.ps1

        try {

            if ([string]::IsNullOrWhiteSpace($Filters)) {
                # param not used.
            }
            # 1. Import filter from scriptblock
            elseif (($Filters).getType().Name -eq 'ScriptBlock') {
                . $Filters
            }
            # 1. Import filters file if it exists
            elseif (($Filters).getType().Name -eq 'String' -and (Test-Path (Join-Path $PWD $Filters) -PathType Leaf)) {
                . (Join-Path $PWD $Filters)

                #Import-PodeModule -Path $Filters # .\helpers\helper.ps1
            }
            else {
                $exFn = New-Object System.Exception("Filters not found: " + $Filters)
                throw $exFn
            }

            if ($PSCmdlet.ParameterSetName -eq 'Path') {
                $psCode = Convert-PugToPowerShell `
                    -Path $path `
                    -Extension $Extension `
                    -BaseDir $BaseDir `
                    -Properties $Properties `
                    -VoidTagsSelfClosing $VoidTagsSelfClosing `
                    -ContainerTagsSelfClosing $ContainerTagsSelfClosing `
                    -KebabCaseHTML $KebabCaseHTML `
                    -ErrorContextRange $ErrorContextRange
            }
            else {
                $psCode = $accumulatedContent | Convert-PugToPowerShell `
                    -Extension $Extension `
                    -BaseDir $BaseDir `
                    -Properties $Properties `
                    -VoidTagsSelfClosing $VoidTagsSelfClosing `
                    -ContainerTagsSelfClosing $ContainerTagsSelfClosing `
                    -KebabCaseHTML $KebabCaseHTML `
                    -ErrorContextRange $ErrorContextRange
            }


            $sb = [scriptblock]::Create($psCode)

            # 3. Execute, passing $Data into the scope
            $html = (& $sb $Data)

            return $html

        } catch {
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
                    -ContextRange $ErrorContextRange
            }
            else {
                # Fallback for errors that didn't get tracked
                $niceMsg = "An unexpected error occurred:`n$($ex.Message)`n$($ex.StackTrace)"
            }
            
            return $niceMsg
        }
    }
}

#Export-ModuleMember -Function Invoke-PUG