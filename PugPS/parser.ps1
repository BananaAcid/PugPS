<#
.SYNOPSIS
    PugPS - A Pug to HTML converter for PowerShell and Pode.
    
.DESCRIPTION
    Copyright (c) 2026 Nabil Redmann
    Licensed under the MIT License.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files.
#>
function Get-PugErrorContext {
    param(
        [string]$Path,
        [int]$LineNumber,
        [string]$Detail,
        [int]$ContextRange = 2
    )

    if (-not (Test-Path $Path)) {
        return "Error: $Detail`n(File not found: $($Path):$($LineNumber))"
    }

    $allLines = Get-Content $Path
    $errorIdx = $LineNumber - 1
    
    $start = [Math]::Max(0, $errorIdx - $ContextRange)
    $end = [Math]::Min($allLines.Count - 1, $errorIdx + $ContextRange)
    
    $maxDigits = ($end + 1).ToString().Length

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("$($Path):$LineNumber")

    for ($i = $start; $i -le $end; $i++) {
        $currentLineNum = $i + 1
        $lineText = $allLines[$i]
        $marker = if ($currentLineNum -eq $LineNumber) { "> " } else { "  " }
        $lineNumStr = $currentLineNum.ToString().PadLeft($maxDigits)
        [void]$sb.AppendLine("$marker$lineNumStr | $lineText")
    }

    [void]$sb.AppendLine("`n$Detail")
    return $sb.ToString()
}

function New-PugError {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$LineObj, 
        [Parameter(Mandatory=$true)]
        [string]$Detail,
        [int]$ContextRange = 2
    )

    $niceMsg = Get-PugErrorContext -Path $LineObj.Path -LineNumber $LineObj.Line -Detail $Detail -ContextRange $ContextRange
    
    $ex = New-Object System.Exception($niceMsg)
    $ex | Add-Member -NotePropertyName "Detail" -NotePropertyValue $Detail -Force
    $ex | Add-Member -NotePropertyName "Path" -NotePropertyValue $LineObj.Path -Force
    $ex | Add-Member -NotePropertyName "Line" -NotePropertyValue $LineObj.Line -Force
    
    return $ex
}

function Convert-PugToPowerShell {
    [CmdletBinding(DefaultParameterSetName='Path')]
    param(
        [Parameter(ParameterSetName='Path', Mandatory=$true, Position=0, HelpMessage="The path to the Pug template file.")]
        [string]$Path,

        [Parameter(ParameterSetName='Content', Mandatory=$true, ValueFromPipeline=$true, HelpMessage="The raw Pug template content.")]
        [string[]]$InputContent,

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
                $accumulatedContent.AddRange($InputContent -split "`n")
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path $Path)) { throw "Template not found: $Path" }
        } else {
            $Path = "Stream"
            # Default BaseDir to PWD if we are processing content directly and BaseDir wasn't provided
            if ([string]::IsNullOrEmpty($BaseDir)) {
                $BaseDir = (Get-Location).Path
            }
        }

        $voidTags = @('area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr')
        $literalTags = @('pre', 'code', 'textarea', 'xmp')
        
        # Regex updated: Tags must start with a letter [a-zA-Z]. 
        # Prevents numeric start (123tag) or symbol start (&tag) from being parsed as tags.
        $tagRegex = '^([a-zA-Z][a-zA-Z0-9_-]*(?::[a-zA-Z0-9_-]+)*|#[a-zA-Z0-9_-]+|\.[a-zA-Z0-9\._-]+)(?:#([a-zA-Z0-9_-]+))?(?:\.([a-zA-Z0-9\._-]+))?(?:\((.*)\))?(\/)?(!?=)?\s?(.*)?$'

        # --- PHASE 1: Resolve Inheritance & Includes ---
        function Resolve-SourceRecursive {
            param(
                [string]$CurrentPath,
                [string[]]$InjectContent = $null
            )

            $rawLines = if ($InjectContent) { $InjectContent } else { Get-Content $CurrentPath }
            $lines = New-Object System.Collections.Generic.List[PSObject]
            
            for ($r=0; $r -lt $rawLines.Count; $r++) {
                $lines.Add([PSCustomObject]@{
                    Text = [string]$rawLines[$r]
                    Path = $CurrentPath
                    Line = $r + 1
                })
            }

            $processed = New-Object System.Collections.Generic.List[PSObject]
            
            # Determine directory for relative resolution
            $currentFileDir = if ($InjectContent) {
                # If content is injected (Stream), use PWD or BaseDir if set globally
                if ($BaseDir) { $BaseDir } else { (Get-Location).Path }
            } else {
                Split-Path $CurrentPath
            }

            $ResolvePath = {
                param([string]$target)
                if ($target -match '^(/|\\)') {
                    $stripped = $target.TrimStart('/\')
                    if (![string]::IsNullOrEmpty($BaseDir)) { return Join-Path $BaseDir $stripped }
                    return Join-Path $currentFileDir $stripped
                }
                return Join-Path $currentFileDir $target
            }
            
            if ($lines.Count -gt 0 -and $lines[0].Text -match '^extends\s+(.+)') {
                $parentName = $matches[1].Trim()
                $parentPath = &$ResolvePath $parentName
                
                if (-not (Test-Path $parentPath)) {
                    $tryPath = "$parentPath.$Extension"
                    if (Test-Path $tryPath) { $parentPath = $tryPath }
                    else { $parentPath = "$parentPath.pug" }
                }

                $parentLineObjs = Resolve-SourceRecursive -CurrentPath $parentPath
                
                $childBlocks = @{}
                $childMixins = New-Object System.Collections.Generic.List[PSObject]
                
                $i = 1 
                while ($i -lt $lines.Count) {
                    $lineObj = $lines[$i]
                    $lineText = $lineObj.Text
                    if ([string]::IsNullOrWhiteSpace($lineText)) { $i++; continue }
                    
                    $indent = ($lineText -split '\S', 2)[0].Length

                    # Ignore unbuffered comment blocks in scan
                    if ($lineText -match '^(\s*)//-') {
                        $cIndent = $matches[1].Length
                        $i++
                        while ($i -lt $lines.Count) {
                            if ($lines[$i].Text.Trim().Length -eq 0) { $i++; continue }
                            $nIndent = ($lines[$i].Text -split '\S', 2)[0].Length
                            if ($nIndent -gt $cIndent) { $i++ } else { break }
                        }
                        continue
                    }
                    
                    if ($lineText -match '^\s*block\s+([a-zA-Z0-9_-]+)') {
                        $blockName = $matches[1]
                        $blockContent = New-Object System.Collections.Generic.List[PSObject]
                        $i++
                        while ($i -lt $lines.Count) {
                            $nextObj = $lines[$i]
                            if ($nextObj.Text.Trim().Length -eq 0) {
                                $blockContent.Add($nextObj)
                                $i++
                                continue 
                            }
                            if (($nextObj.Text -split '\S', 2)[0].Length -le $indent) { break }
                            $blockContent.Add($nextObj)
                            $i++
                        }
                        $childBlocks[$blockName] = $blockContent
                    } elseif ($lineText -match '^\s*mixin\s+') {
                        $childMixins.Add($lineObj)
                        $mIndent = $indent
                        $i++
                        while ($i -lt $lines.Count) {
                            $nextObj = $lines[$i]
                            if ($nextObj.Text.Trim().Length -eq 0) { $childMixins.Add($nextObj); $i++; continue }
                            if (($nextObj.Text -split '\S', 2)[0].Length -le $mIndent) { break }
                            $childMixins.Add($nextObj)
                            $i++
                        }
                    } else { $i++ }
                }

                foreach($m in $childMixins) { $processed.Add($m) }
                
                foreach ($pObj in $parentLineObjs) {
                    if ($pObj.Text -match '^(\s*)block\s+([a-zA-Z0-9_-]+)') {
                        $pIndent = $matches[1].Length
                        $pBlockName = $matches[2]
                        
                        if ($childBlocks.ContainsKey($pBlockName)) {
                            $cObjs = $childBlocks[$pBlockName]
                            if ($cObjs.Count -gt 0) {
                                $minC = 999
                                foreach($co in $cObjs) { 
                                    if ($co.Text.Trim().Length -gt 0) { 
                                        $val = ($co.Text -split '\S', 2)[0].Length
                                        if ($val -lt $minC) { $minC = $val } 
                                    } 
                                }
                                if ($minC -eq 999) { $minC = 0 }

                                foreach($co in $cObjs) {
                                    $newObj = $co.PSObject.Copy()
                                    if ($co.Text.Trim().Length -eq 0) { 
                                        $newObj.Text = "" 
                                    } else { 
                                        $currC = ($co.Text -split '\S', 2)[0].Length
                                        $calcIndent = [Math]::Max(0, ($currC - $minC))
                                        $newIndent = " " * ($pIndent + $calcIndent)
                                        $newObj.Text = $newIndent + $co.Text.Trim()
                                    }
                                    $processed.Add($newObj)
                                }
                            }
                        } else {
                            $processed.Add($pObj)
                        }
                    } else { 
                        $processed.Add($pObj) 
                    }
                }
                $lines = $processed
                $processed = New-Object System.Collections.Generic.List[PSObject]
            }

            # Include Logic
            $i = 0
            while ($i -lt $lines.Count) {
                $lineObj = $lines[$i]
                $line = $lineObj.Text
                
                # Detect block comments (both unbuffered //- and buffered //) to skip include resolution inside them
                if ($line -match '^(\s*)//') {
                    $commentIndent = $matches[1].Length
                    $processed.Add($lineObj)
                    $i++
                    while ($i -lt $lines.Count) {
                        $nLine = $lines[$i]
                        if ([string]::IsNullOrWhiteSpace($nLine.Text)) {
                            $processed.Add($nLine); $i++; continue
                        }
                        $nIndent = ($nLine.Text -split '\S', 2)[0].Length
                        # If line is indented deeper than the comment start, it is part of the comment block
                        if ($nIndent -gt $commentIndent) {
                            $processed.Add($nLine)
                            $i++
                        } else {
                            break
                        }
                    }
                    continue
                }

                if ($line -match '^(\s*)include(:[a-zA-Z0-9_:-]+)?\s+(.+)') {
                    $indentStr = $matches[1]
                    $filterChain = $matches[2]
                    $incFileName = $matches[3].Trim()
                    $incPath = &$ResolvePath $incFileName
                    
                    if (-not (Test-Path $incPath) -and $incFileName -notmatch '\.[a-zA-Z0-9]+$') {
                        $tryPath = "$incPath.$Extension"
                        if (Test-Path $tryPath) { $incPath = $tryPath }
                    }

                    if (Test-Path $incPath) {
                        if (-not [string]::IsNullOrEmpty($filterChain)) {
                            $newHeader = $lineObj.PSObject.Copy()
                            $newHeader.Text = "$indentStr$filterChain"
                            $processed.Add($newHeader)
                            
                            $incRaw = Get-Content $incPath
                            for($k=0; $k -lt $incRaw.Count; $k++) {
                                $processed.Add([PSCustomObject]@{
                                    Text = "$indentStr  $($incRaw[$k])"
                                    Path = $incPath
                                    Line = $k + 1
                                })
                            }
                        } else {
                            $regexExt = ($Extension -replace '\.', '\.') + '$'
                            if ($incPath -match $regexExt -or $incPath -match '\.pug$') {
                                $incLines = Resolve-SourceRecursive -CurrentPath $incPath
                                foreach ($il in $incLines) { 
                                    $newObj = $il.PSObject.Copy()
                                    $newObj.Text = $indentStr + $il.Text
                                    $processed.Add($newObj) 
                                }
                            } else {
                                $incRaw = Get-Content $incPath
                                for($k=0; $k -lt $incRaw.Count; $k++) {
                                    $processed.Add([PSCustomObject]@{
                                        Text = "$indentStr| $($incRaw[$k])"
                                        Path = $incPath
                                        Line = $k + 1
                                    })
                                }
                            }
                        }
                    } else {
                        throw (New-PugError -LineObj $lineObj -Detail "Included file not found: $incPath" -ContextRange $ErrorContextRange)
                    }
                    $i++
                } else { 
                    $processed.Add($lineObj) 
                    $i++
                }
            }
            return $processed
        }

        function Get-BalancedContent([string]$str, [int]$startIdx, [char]$open, [char]$close) {
            $depth = 0
            for ($j = $startIdx; $j -lt $str.Length; $j++) {
                if ($str[$j] -eq $open) { $depth++ }
                elseif ($str[$j] -eq $close) {
                    $depth--
                    if ($depth -eq 0) { return @{ Content = $str.Substring($startIdx + 1, $j - $startIdx - 1); EndIdx = $j } }
                }
            }
            return $null
        }

        function Get-PSFilterPipeline([string]$chain, [ref]$endIdx) {
            $pipelineParts = New-Object System.Collections.Generic.List[string]
            $idx = 0
            while ($idx -lt $chain.Length) {
                if ($chain[$idx] -match '\s') { break }
                if ($chain[$idx] -eq ':') { $idx++ }
                $start = $idx
                while ($idx -lt $chain.Length -and $chain[$idx] -match '[a-zA-Z0-9_-]') { $idx++ }
                $funcName = $chain.Substring($start, $idx - $start)
                $argsStr = ""
                if ($idx -lt $chain.Length -and $chain[$idx] -eq '(') {
                    $b = Get-BalancedContent $chain $idx '(' ')'
                    if ($b) {
                        $rawArgs = $b.Content
                        $psArgs = New-Object System.Collections.Generic.List[string]
                        $pairs = Get-PugAttributePairs $rawArgs
                        foreach ($pair in $pairs) {
                            if ($pair -match '^([^=]+)=(.*)$') {
                                $k = $matches[1].Trim(); $v = $matches[2].Trim()
                                $psArgs.Add("-$k $v")
                            } else { $psArgs.Add($pair) }
                        }
                        $argsStr = " " + ($psArgs -join " ")
                        $idx = $b.EndIdx + 1
                    } else { $idx++ } 
                }
                if (![string]::IsNullOrEmpty($funcName)) { $pipelineParts.Add("$funcName$argsStr") }
                if ($idx -lt $chain.Length -and $chain[$idx] -ne ':') { break }
            }
            $endIdx.Value = $idx
            return $pipelineParts -join " | "
        }

        function ConvertTo-PugInterpolatedTag {
            param([string]$inner, [bool]$xmlMode)
            if ($inner -match $tagRegex) {
                $tagMatch = $matches
                $tagName = "div"
                if ($tagMatch[1] -and $tagMatch[1] -notmatch '^[#.]') {
                    $tagName = $tagMatch[1]
                }
                
                # OPTIMIZATION: Convert CamelCase to kebab-case if not XML
                if (-not $xmlMode -and $KebabCaseHTML -and $tagName -cmatch '[A-Z]') {
                    $tagName = ($tagName -creplace '([a-zA-Z0-9-])([A-Z])', '$1-$2').ToLower()
                }

                $id = if ($tagMatch[1] -match '^#') { $tagMatch[1].Substring(1) } else { $tagMatch[2] }
                
                $rawClass = ""
                if ($tagMatch[1] -match '^\.') { $rawClass = $tagMatch[1] }
                if ($tagMatch[3]) { $rawClass += "." + $tagMatch[3] }
                
                $classes = if ($rawClass) { $rawClass.Split('.') | Where-Object { $_ } | ForEach-Object { "'$_'" } } else { @() }
                $attrString = $tagMatch[4]
                $explicitSlash = [bool]$tagMatch[5]
                $operator = $tagMatch[6]
                $inlineContent = $tagMatch[7]

                $isVoid = $voidTags -contains $tagName
                $hasContent = ![string]::IsNullOrEmpty($inlineContent)
                
                $parts = New-Object System.Collections.Generic.List[string]
                $parts.Add("'<" + $tagName + "'")
                if ($id) { $parts.Add("' id=`"$id`"'") }
                if ($classes.Count -gt 0) { $parts.Add("(Out-PugAttr 'class' @($($classes -join ',')) `$false)") }
                if ($attrString) {
                    foreach ($pair in (Get-PugAttributePairs $attrString)) {
                        if ($pair -match '^([^!=]+)\s*(!?=)\s*(.*)$') {
                            $ak = $matches[1].Trim(); $ao = $matches[2]; $val = $matches[3].Trim()
                            $parts.Add("(Out-PugAttr '$ak' ($val) " + $(if ($ao -eq '=') { '$true' } else { '$false' }) + ")")
                        } else { $parts.Add("(Out-PugAttr '$pair' `$true `$false)") }
                    }
                }
                
                if ($explicitSlash -and !$hasContent) {
                    $parts.Add("' />'")
                } else {
                    if ($isVoid) {
                        $parts.Add("`$(if (`$pug_voidSelfClose) { ' />' } else { '>' })")
                    } elseif (!$hasContent) {
                        $parts.Add("`$(if (`$pug_containerSelfClose) { ' />' } else { '>' })")
                    } else {
                        $parts.Add("'>'")
                    }

                    if ($hasContent) {
                        if ($operator -eq '=') { $parts.Add("(Out-PugEnc ($inlineContent))") }
                        elseif ($operator -eq '!=') { $parts.Add("($inlineContent)") }
                        else { $parts.Add((Out-PSEscaped $inlineContent $xmlMode)) }
                    }

                    if (!$isVoid) {
                        if (!$hasContent) {
                            $parts.Add("`$(if (-not `$pug_containerSelfClose) { '</$tagName>' } else { '' })")
                        } else {
                            $parts.Add("'</$tagName>'")
                        }
                    }
                }
                return "($($parts -join ' + '))"
            }
            return "''"
        }

        function Out-PSEscaped {
            param([string]$text, [bool]$xmlMode)
            if ($null -eq $text) { return '""' }
            $res = ""; $idx = 0
            while ($idx -lt $text.Length) {
                $char = $text[$idx]
                if (($char -eq '\' -or $char -eq '`') -and ($idx + 1 -lt $text.Length)) {
                    $next = $text[$idx+1]
                    if ($next -eq '$') { $res += '`$'; $idx += 2; continue }
                    if ($next -eq '`') { $res += '``'; $idx += 2; continue }
                    if ($next -eq '\') { $res += '\'; $idx += 2; continue }
                }
                if ($char -eq '#' -and ($idx + 1 -lt $text.Length)) {
                    $next = $text[$idx+1]
                    if ($next -eq '(' -or $next -eq '{') {
                        $closeChar = $(if($next -eq '('){')'} else {'}'})
                        $b = Get-BalancedContent $text ($idx+1) $next $closeChar
                        if ($b) { $res += '$(' + "Out-PugEnc ($($b.Content))" + ')'; $idx = $b.EndIdx + 1; continue }
                    }
                    if ($next -eq '[') {
                        $b = Get-BalancedContent $text ($idx+1) '[' ']'
                        if ($b) { $res += '$' + (ConvertTo-PugInterpolatedTag $b.Content $xmlMode); $idx = $b.EndIdx + 1; continue }
                    }
                }
                if ($char -eq '$' -and ($idx + 1 -lt $text.Length) -and $text[$idx+1] -eq '{') {
                    $b = Get-BalancedContent $text ($idx+1) '{' '}'
                    if ($b) { $res += '$(' + $b.Content + ')'; $idx = $b.EndIdx + 1; continue }
                }
                if ($char -eq '"') { $res += '`"' }
                elseif ($char -eq '`') { $res += '``' }
                else { $res += $char }
                $idx++
            }
            return "`"$res`""
        }

        function Out-PSLiteral([string]$text) {
            if ($null -eq $text) { return '""' }
            $safe = $text.Replace('`', '``').Replace('"', '`"').Replace('$', '`$')
            return "`"$safe`""
        }

        function Get-TabPrefix($stack) {
            foreach ($item in $stack) { if ($literalTags -contains $item.Tag) { return "" } }
            $count = 0
            foreach ($item in $stack) { if ($item.Tag) { $count++ } }
            return "`t" * $count
        }

        function Get-PugAttributePairs([string]$attrString) {
            $pairs = New-Object System.Collections.Generic.List[string]
            if ([string]::IsNullOrWhiteSpace($attrString)) { return $pairs }
            $current = ""; $inQuotes = $false; $quoteChar = ""; $depth = 0
            $chars = $attrString.ToCharArray()
            for ($j = 0; $j -lt $chars.Count; $j++) {
                $char = $chars[$j]
                if ($inQuotes) {
                    $current += $char
                    if ($char -eq $quoteChar) { $inQuotes = $false }
                } else {
                    if ($char -eq "'" -or $char -eq '"') { $inQuotes = $true; $quoteChar = $char; $current += $char }
                    elseif ($char -eq '(') { $depth++; $current += $char }
                    elseif ($char -eq ')') { $depth--; $current += $char }
                    elseif ($depth -eq 0 -and $char -eq ',') {
                        if ($current.Trim()) { $pairs.Add($current.Trim()) }
                        $current = ""
                    } elseif ($depth -eq 0 -and $char -eq ' ') {
                        $remaining = $attrString.Substring($j).Trim()
                        if ($remaining -match '^(!?=)') { $current += $char }
                        elseif ($current.Trim() -match '(!?=)$') { $current += $char }
                        else { if ($current.Trim()) { $pairs.Add($current.Trim()) }; $current = "" }
                    } else { $current += $char }
                }
            }
            if ($current.Trim()) { $pairs.Add($current.Trim()) }
            return $pairs
        }

        # Resolve Source (File vs Stream)
        $injection = if ($PSCmdlet.ParameterSetName -eq 'Content') { $accumulatedContent } else { $null }
        $lines = Resolve-SourceRecursive -CurrentPath $Path -InjectContent $injection

        $outputScript = New-Object System.Collections.Generic.List[string]
        $stack = New-Object System.Collections.Generic.Stack[PSObject]

        $mixinBaseStackCount = -1
        $isXmlMode = $false

        function Get-IndentExpr {
            if ($mixinBaseStackCount -gt -1) {
                foreach ($item in $stack) { if ($literalTags -contains $item.Tag) { return "`$pug_indent" } }
                $relDepth = 0
                foreach ($item in $stack) {
                    if ($item.IsDefinition) { break }
                    if ($item.Tag) { $relDepth++ }
                }
                return "(`$pug_indent + $(Out-PSLiteral ("`t" * $relDepth)))"
            }
            return Out-PSLiteral (Get-TabPrefix $stack)
        }

        function Get-TraceLine([PSObject]$l) {
            $safePath = $l.Path.Replace("'", "''")
            return "`$pug_src_line=$($l.Line);`$pug_src_path='$safePath'; "
        }

        $outputScript.Add('param($data)')
        $outputScript.Add("`$pug_src_line = 0; `$pug_src_path = ''")
        $outputScript.Add("`$pug_props = $(if($Properties){'$true'}else{'$false'})")
        $outputScript.Add("`$pug_voidSelfClose = $(if($VoidTagsSelfClosing){'$true'}else{'$false'})")
        $outputScript.Add("`$pug_containerSelfClose = $(if($ContainerTagsSelfClosing){'$true'}else{'$false'})")
        
        $outputScript.Add(@'
function Out-PugClass($items) {
    $res = New-Object System.Collections.Generic.List[string]
    foreach ($i in @($items)) {
        if ($null -eq $i -or ($i -is [bool] -and !$i)) { continue }
        if ($i -is [System.Collections.IDictionary]) {
            foreach ($entry in $i.GetEnumerator()) { if ($entry.Value) { $res.Add($entry.Key.ToString()) } }
        }
        elseif ($i -is [string]) { foreach($s in ($i -split '\s+')) { if($s.Trim()) { $res.Add($s.Trim()) } } }
        elseif ($i -is [System.Collections.IEnumerable]) { foreach($sub in $i) { $res.Add((Out-PugClass $sub)) } }
        else { $res.Add("$i") }
    }
    return (($res | Select-Object -Unique) -join " ").Trim()
}
function Out-PugStyle($v) {
    if ($null -eq $v -or ($v -is [bool] -and !$v) -or ($v -is [string] -and $v -eq "")) { return "" }
    if ($v -is [string]) { return $v.Trim() }
    if ($v -is [System.Collections.IDictionary]) {
        $res = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $v.GetEnumerator()) {
            $val = $entry.Value
            if ($null -eq $val -or ($val -is [bool] -and !$val) -or ($val -is [string] -and $val -eq "")) { continue }
            $k = $entry.Key.ToString()
            $pk = $k
            if ($k -notmatch '^--') {
                $tmp = $k.Substring(0,1).ToLower() + $k.Substring(1)
                $pk = [regex]::Replace($tmp, '([A-Z])', '-$1').ToLower()
            }
            $res.Add("$($pk): $val")
        }
        return ($res -join "; ")
    }
    return "$v"
}
function Out-PugAttr($k, $v, $e) {
    if ($null -eq $v -or ($v -is [bool] -and !$v)) { return "" }
    if ($v -is [bool] -and $v) { 
        return $(if ($pug_props) { " $k" } else { " $k=`"$k`"" })
    }
    $s = $(if ($k -eq "class") { Out-PugClass $v } 
         elseif ($k -eq "style") { Out-PugStyle $v }
         else { "$v" })
    if ($null -eq $s -or $s -eq "") { return "" }
    if ($e) { $s = [System.Net.WebUtility]::HtmlEncode($s) }
    return " $k=`"$s`""
}
function Out-PugEnc($v) { return [System.Net.WebUtility]::HtmlEncode("$v") }
function Out-PugMergedAttrs($inline, $exploded) {
    if ($null -eq $exploded) {
        $res = New-Object System.Collections.Generic.List[string]
        if ($null -ne $inline) {
            foreach($k in $inline.Keys) { 
                $enc = ($k -eq 'class' -or $k -eq 'style')
                $res.Add((Out-PugAttr $k $inline[$k] $enc)) 
            }
        }
        return $res -join ""
    }
    if ($null -eq $inline) { $inline = @{} }
    $exDict = @{}
    if ($exploded -is [System.Collections.IDictionary]) {
         $exploded.Keys | ForEach-Object { $exDict[$_] = $exploded[$_] }
    } elseif ($exploded -ne $null) {
         if ($exploded.PSObject) {
            foreach($prop in $exploded.PSObject.Properties) {
                if ($prop.CanRead) { $exDict[$prop.Name] = $prop.Value }
            }
         }
    }
    if ($exDict.Contains("class")) {
        $existing = $(if ($inline.Contains("class")) { @($inline["class"]) } else { @() })
        $new = $exDict["class"]
        $inline["class"] = $existing + $new
        $exDict.Remove("class")
    }
    if ($exDict.Contains("style")) {
        $iS = $(if ($inline.Contains("style")) { Out-PugStyle $inline["style"] } else { "" })
        $eS = Out-PugStyle $exDict["style"]
        $merged = $(if ($iS -and $eS) { "$iS; $eS" } elseif ($iS) { $iS } else { $eS })
        $inline["style"] = $merged
        $exDict.Remove("style")
    }
    foreach($k in $exDict.Keys) {
        $inline[$k] = $exDict[$k]
    }
    $res = New-Object System.Collections.Generic.List[string]
    foreach($k in $inline.Keys) {
        $enc = ($k -eq 'class' -or $k -eq 'style')
        $res.Add((Out-PugAttr $k $inline[$k] $enc))
    }
    return $res -join ""
}
'@)

        $outputScript.Add("try {")
        $outputScript.Add("@(")

        $i = 0
        while ($i -lt $lines.Count) {
            $lineObj = $lines[$i]; $i++
            $rawLine = $lineObj.Text
            if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
            $indent = ($rawLine -split '\S', 2)[0].Length
            $line = $rawLine.Trim()

            # Peek ahead to find next content indentation (skipping empty lines)
            $peekI = $i
            while ($peekI -lt $lines.Count -and $lines[$peekI].Text.Trim().Length -eq 0) { $peekI++ }
            $nextContentIndent = -1
            if ($peekI -lt $lines.Count) {
                $nextContentIndent = ($lines[$peekI].Text -split '\S', 2)[0].Length
            }
            
            # Calculate parentIsSwitch Context for this iteration
            $parentIsSwitch = $false
            if ($stack.Count -gt 0) { $parent = $stack.Peek(); if ($parent.IsSwitch) { $parentIsSwitch = $true } }

            # Handle multiline parens
            $parenIdx = $line.IndexOf('(')
            if ($parenIdx -ge 0 -and ($line -match '^[a-zA-Z0-9.#+-]')) {
                $balanced = Get-BalancedContent $line $parenIdx '(' ')'
                if ($null -eq $balanced) {
                    while ($i -lt $lines.Count) {
                        $nextLineObj = $lines[$i]
                        $nextLine = $nextLineObj.Text.Trim()
                        $line += " " + $nextLine
                        $rawLine += " " + $nextLine 
                        $i++
                        if (Get-BalancedContent $line $parenIdx '(' ')') { break }
                    }
                }
            }

            # Hidden Comments (//-)
            if ($line.StartsWith("//-")) {
                $currI = $indent
                while($i -lt $lines.Count -and (($lines[$i].Text.Trim().Length -eq 0) -or ($lines[$i].Text -split '\S', 2)[0].Length -gt $currI)) { $i++ }
                continue
            }

            while ($stack.Count -gt 0 -and $stack.Peek().Indent -ge $indent) {
                $top = $stack.Pop()
                if ($top.IsDefinition) { $mixinBaseStackCount = -1 }
                if ($top.IsCode -or $top.IsMixin) { 
                    if (-not $top.IsExplicit) { $outputScript.Add("}") }
                }
                else { 
                    $closeIndent = if ($literalTags -contains $top.Tag) { "''" } else { Get-IndentExpr }
                    $outputScript.Add($closeIndent + " + " + (Out-PSLiteral "</$($top.Tag)>")) 
                }
            }
            # Recalculate parentIsSwitch after popping
            $parentIsSwitch = $false
            if ($stack.Count -gt 0) { $parent = $stack.Peek(); if ($parent.IsSwitch) { $parentIsSwitch = $true } }

            # Unbuffered Code Block (-)
            if ($line -eq "-") {
                $currI = $indent
                while($i -lt $lines.Count -and (($lines[$i].Text.Trim().Length -eq 0) -or ($lines[$i].Text -split '\S', 2)[0].Length -gt $currI)) {
                    if ($lines[$i].Text.Trim()) { 
                        $outputScript.Add($lines[$i].Text.Trim()) 
                    }; $i++
                }
                continue
            }

            # Unbuffered Code Line (- ...)
            if ($line.StartsWith("- ")) {
                $code = $line.Substring(2).Trim()
                $hasExplicitBlock = $code.EndsWith("{")
                $isControlKeyword = $code -match '^\s*(if|elseif|foreach|for|while|switch|else|try|catch|finally|default)\b'
                
                $isSwitchCase = $parentIsSwitch -and -not $isControlKeyword -and ($code -notmatch '^}')
                $shouldAutoBlock = ($isControlKeyword -or $isSwitchCase) -and -not $hasExplicitBlock
                $shouldTrackExplicit = $hasExplicitBlock -and ($isControlKeyword -or $isSwitchCase)
                
                $isContinuation = $code -match '^\s*(catch|finally|else|elseif)\b'

                # Suppress trace if: inside switch (structural), line starts with }, or is a continuation keyword
                if (-not $parentIsSwitch -and $code -notmatch '^}' -and -not $isContinuation) {
                    $outputScript.Add((Get-TraceLine $lineObj) + $code)
                } else {
                    $outputScript.Add($code)
                }

                if ($shouldAutoBlock) { 
                    $isSwitchLine = $code -match '^\s*switch\b'
                    $outputScript.Add("{")
                    $stack.Push(@{ Indent = $indent; IsCode = $true; IsMixin = $false; IsDefinition = $false; IsSwitch = $isSwitchLine; IsExplicit = $false }) 
                } elseif ($shouldTrackExplicit) {
                    $isSwitchLine = $code -match '^\s*switch\b'
                    $stack.Push(@{ Indent = $indent; IsCode = $true; IsMixin = $false; IsDefinition = $false; IsSwitch = $isSwitchLine; IsExplicit = $true }) 
                }
                continue
            }
            
            # Filter
            if ($line.StartsWith(":")) {
                $consumedIdx = 0
                $pipelineCmd = Get-PSFilterPipeline $line ([ref]$consumedIdx)
                $inlineContent = if ($consumedIdx -lt $line.Length) { $line.Substring($consumedIdx).Trim() } else { "" }
                $prefixExpr = Get-IndentExpr
                $blockLines = New-Object System.Collections.Generic.List[string]; $currI = $indent
                while ($i -lt $lines.Count -and (($lines[$i].Text.Trim().Length -eq 0) -or ($lines[$i].Text -split '\S', 2)[0].Length -gt $currI)) { $blockLines.Add($lines[$i].Text); $i++ }
                
                $stripCount = 999
                foreach($bl in $blockLines) { if ($bl.Trim()) { $val = ($bl -split '\S', 2)[0].Length; if ($val -lt $stripCount) { $stripCount = $val } } }
                if ($stripCount -eq 999) { $stripCount = 0 }
                
                $psContentArray = New-Object System.Collections.Generic.List[string]
                if ($inlineContent) { $psContentArray.Add((Out-PSEscaped $inlineContent $isXmlMode)) }
                foreach($bl in $blockLines) { 
                    $content = if ($bl.Length -ge $stripCount) { $bl.Substring($stripCount) } else { "" }
                    $psContentArray.Add((Out-PSEscaped $content $isXmlMode)) 
                }
                while ($psContentArray.Count -gt 1 -and ($psContentArray[-1] -eq '""')) { $psContentArray.RemoveAt($psContentArray.Count - 1) }
                $contentString = "(" + ($psContentArray -join "+ `"``n`" +") + ")"
                
                if (-not $parentIsSwitch) { $outputScript.Add((Get-TraceLine $lineObj)) }
                $outputScript.Add($prefixExpr + " + ($contentString | $pipelineCmd | Out-String)")
                continue
            }

            # HTML Comments (//)
            if ($line.StartsWith("//")) {
                $prefixExpr = Get-IndentExpr; $inline = $line.Substring(2).Trim()
                $hasIndentedContent = ($nextContentIndent -gt $indent)
                
                $inSwitch = ($stack.Count -gt 0 -and $stack.Peek().IsSwitch)
                if ($inSwitch) {
                    if ($inline) { $outputScript.Add("# $inline") }
                    if ($hasIndentedContent) {
                        $currI = $indent
                        while($i -lt $lines.Count -and (($lines[$i].Text.Trim().Length -eq 0) -or ($lines[$i].Text -split '\S', 2)[0].Length -gt $currI)) { 
                            if ($lines[$i].Text.Trim()) { $outputScript.Add("# " + $lines[$i].Text.Trim()) }; $i++ 
                        }
                    }
                } else {
                    if ($hasIndentedContent) {
                        $commentBody = New-Object System.Collections.Generic.List[string]
                        $commentBody.Add($prefixExpr + " + " + (Out-PSLiteral "<!--"))
                        if ($inline) { $commentBody.Add((Out-PSLiteral " ") + " + " + (Out-PSLiteral $inline)) }
                        
                        $stripLen = $nextContentIndent
                        $currI = $indent
                        while($i -lt $lines.Count -and (($lines[$i].Text.Trim().Length -eq 0) -or ($lines[$i].Text -split '\S', 2)[0].Length -gt $currI)) {
                            $lText = $lines[$i].Text
                            if ($lText.Trim().Length -gt 0) {
                                $len = ($lText -split '\S', 2)[0].Length
                                $relContent = if ($len -ge $stripLen) { $lText.Substring($stripLen) } else { $lText.TrimStart() }
                                $commentBody.Add((Out-PSLiteral "`n") + " + " + (Get-IndentExpr) + " + " + (Out-PSLiteral "`t") + " + " + (Out-PSLiteral $relContent))
                            }
                            $i++
                        }
                        
                        $commentBody.Add((Out-PSLiteral "`n") + " + " + (Get-IndentExpr) + " + " + (Out-PSLiteral "-->"))
                        $outputScript.Add($commentBody -join " + ")
                    } else { $outputScript.Add($prefixExpr + " + " + (Out-PSLiteral "<!-- ") + " + " + (Out-PSLiteral $inline) + " + " + (Out-PSLiteral " -->")) }
                }
                continue
            }

            # Dot Block (tag.)
            # Updated Regex to require tag start with letter
            if ($line -match '^([a-zA-Z][a-zA-Z0-9]*)?\.$') {
                $tagName = $matches[1]; $prefixExpr = Get-IndentExpr
                
                # OPTIMIZATION: Convert CamelCase to kebab-case if not XML
                if ($tagName -and -not $isXmlMode -and $KebabCaseHTML -and $tagName -cmatch '[A-Z]') {
                    $tagName = ($tagName -creplace '([a-zA-Z0-9-])([A-Z])', '$1-$2').ToLower()
                }

                if ($tagName) { $outputScript.Add($prefixExpr + " + " + (Out-PSLiteral "<$tagName>")) }
                
                $blockLines = New-Object System.Collections.Generic.List[string]; $currI = $indent
                while ($i -lt $lines.Count -and (($lines[$i].Text.Trim().Length -eq 0) -or ($lines[$i].Text -split '\S', 2)[0].Length -gt $indent)) { $blockLines.Add($lines[$i].Text); $i++ }
                
                $stripCount = 999
                foreach($bl in $blockLines) { if ($bl.Trim()) { $val = ($bl -split '\S', 2)[0].Length; if ($val -lt $stripCount) { $stripCount = $val } } }
                if ($stripCount -eq 999) { $stripCount = 0 }
                
                if ($tagName -and $voidTags -notcontains $tagName) { $stack.Push(@{ Indent = $indent; Tag = $tagName; IsCode = $false; IsMixin = $false; IsDefinition = $false; IsSwitch = $false; IsExplicit = $false }) }
                
                foreach($bl in $blockLines) {
                    $content = if ($bl.Length -ge $stripCount) { $bl.Substring($stripCount) } else { "" }
                    $outputScript.Add((Get-IndentExpr) + " + " + (Out-PSEscaped $content $isXmlMode))
                }
                if ($tagName -and $voidTags -notcontains $tagName) {
                    $top = $stack.Pop(); $closeIndent = if ($literalTags -contains $top.Tag) { "''" } else { Get-IndentExpr }
                    $outputScript.Add($closeIndent + " + " + (Out-PSLiteral "</$($top.Tag)>"))
                }
                continue
            }

            # Mixin Def
            if ($line -match '^mixin\s+([a-zA-Z0-9_-]+)(?:\((.*)\))?') {
                $mName = $matches[1]; $rArgs = $matches[2]; $parsedArgs = New-Object System.Collections.Generic.List[string]
                if ($rArgs) {
                    foreach ($rawArg in ($rArgs -split ',')) {
                        $arg = $rawArg.Trim(); if(!$arg){continue}
                        if ($arg -match '^(\$?[a-zA-Z0-9_-]+)\s*(?:=\s*(.*))?$') {
                            $varName = $matches[1]; $defaultVal = $matches[2]
                            if (-not $varName.StartsWith('$')) { $varName = "`$$varName" }
                            if ($defaultVal) { $parsedArgs.Add("$varName = $defaultVal") } else { $parsedArgs.Add($varName) }
                        }
                    }
                }
                $pArgs = if ($parsedArgs.Count -gt 0) { ($parsedArgs -join ", ") + ", " } else { "" }
                $outputScript.Add("function mixin_$($mName) { param(`$pug_indent, $($pArgs)[scriptblock]`$mixinBlock)")
                $stack.Push(@{ Indent = $indent; IsCode = $false; IsMixin = $true; IsDefinition = $true; IsSwitch = $false; IsExplicit = $false })
                $mixinBaseStackCount = $stack.Count; continue
            }

            # Block keyword
            if ($line -eq "block") { 
                $relDepth = 0
                foreach ($item in $stack) { if ($item.IsDefinition) { break }; if ($item.Tag) { $relDepth++ } }
                $outputScript.Add("if (`$mixinBlock) { (`& `$mixinBlock) | ForEach-Object { " + (Out-PSLiteral ("`t" * $relDepth)) + " + `$_ } }")
                continue 
            }

            # Mixin Call (+mixin)
            if ($line -match '^\+([a-zA-Z0-9_-]+)(?:\((.*)\))?') {
                $mName = $matches[1]; $caRaw = $matches[2]; $indentToPass = Get-IndentExpr
                $psArgs = if ($caRaw) { (($caRaw -split ',').Trim()) -join " " } else { "" }
                
                if (-not $parentIsSwitch) { $outputScript.Add((Get-TraceLine $lineObj)) }
                
                if ($nextContentIndent -gt $indent) {
                    $outputScript.Add("mixin_$($mName) $indentToPass $psArgs {"); $stack.Push(@{ Indent = $indent; IsCode = $false; IsMixin = $true; IsDefinition = $false; IsSwitch = $false; IsExplicit = $false })
                } else { $outputScript.Add("mixin_$($mName) $indentToPass $psArgs") }
                continue
            }

            # Buffered code (=, !=, |)
            if ($line -match '^(=|!=|\|)(?:\s(.*)|(.*))$') {
                $op = $matches[1]; $content = if($matches[2]){$matches[2]}else{$matches[3]}
                $prefixExpr = Get-IndentExpr
                if ($op -eq "|") { $outputScript.Add($prefixExpr + " + " + (Out-PSEscaped $content $isXmlMode)) }
                elseif ($op -eq "=") { 
                    if (-not $parentIsSwitch) { $outputScript.Add((Get-TraceLine $lineObj)) }
                    $outputScript.Add($prefixExpr + " + (Out-PugEnc ($content))") 
                }
                else { 
                    if (-not $parentIsSwitch) { $outputScript.Add((Get-TraceLine $lineObj)) }
                    $outputScript.Add($prefixExpr + " + ($content)") 
                }
                continue
            }

            # Doctype
            if ($line -match '^doctype\s+(.*)') {
                $dtType = $matches[1].Trim()
                $dtLower = $dtType.ToLower()
                if ($dtLower -eq 'html5') { $dtLower = 'html' }
                $doctypes = @{
                    'html'         = '<!DOCTYPE html>'
                    '5'            = '<!DOCTYPE html>'
                    'xml'          = '<?xml version="1.0" encoding="utf-8" ?>'
                    'transitional' = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">'
                    'strict'       = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'
                    'frameset'     = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">'
                    '1.1'          = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'
                    'basic'        = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">'
                    'mobile'       = '<!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">'
                    'plist'        = '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
                    'svg1.1'       = '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">'
                    'smil1'        = '<!DOCTYPE smil PUBLIC "-//W3C//DTD SMIL 1.0//EN" "http://www.w3.org/TR/REC-smil/SMIL10.dtd">'
                    'smil2'        = '<!DOCTYPE smil PUBLIC "-//W3C//DTD SMIL 2.0//EN" "http://www.w3.org/2001/SMIL20/WD/SMIL20.dtd">'
                }
                $dtString = if ($doctypes.ContainsKey($dtLower)) { $doctypes[$dtLower] } else { "<!DOCTYPE $dtType>" }

                if ($dtLower -eq 'xml') {
                    $isXmlMode = $true
                    $outputScript.Add("`$pug_voidSelfClose = `$true")
                    $outputScript.Add("`$pug_containerSelfClose = `$true")
                    $outputScript.Add("`$pug_props = `$false")
                } elseif ($dtLower -ne 'html' -and $dtLower -ne '5') {
                    $outputScript.Add("`$pug_props = `$false")
                }
                $outputScript.Add((Out-PSLiteral $dtString))
                continue
            }

            # HTML Literal
            if ($line.StartsWith("<")) { $prefixExpr = Get-IndentExpr; $outputScript.Add($prefixExpr + " + " + (Out-PSLiteral $line)); continue }

            $explodedAttrsExpr = $null
            $lineForTag = $line
            $attrMatch = [regex]::Match($line, '&attributes\s*\(')
            if ($attrMatch.Success) {
                $attrIdx = $attrMatch.Index
                $b = Get-BalancedContent $line ($attrIdx + $attrMatch.Length - 1) '(' ')'
                if ($b) {
                    $explodedAttrsExpr = $b.Content
                    $lineForTag = $line.Substring(0, $attrIdx) + $line.Substring($b.EndIdx + 1)
                }
            }

            if ($lineForTag -match $tagRegex) {
                $tagMatch = $matches
                $tagName = "div"
                if ($tagMatch[1] -and $tagMatch[1] -notmatch '^[#.]') {
                    $tagName = $tagMatch[1]
                }
                
                # OPTIMIZATION: Convert CamelCase to kebab-case if not XML
                if (-not $isXmlMode -and $KebabCaseHTML -and $tagName -cmatch '[A-Z]') {
                    $tagName = ($tagName -creplace '([a-zA-Z0-9-])([A-Z])', '$1-$2').ToLower()
                }

                $id = if ($tagMatch[1] -match '^#') { $tagMatch[1].Substring(1) } else { $tagMatch[2] }

                $rawClass = ""
                if ($tagMatch[1] -match '^\.') { $rawClass = $tagMatch[1] }
                if ($tagMatch[3]) { $rawClass += "." + $tagMatch[3] }

                $classes = if ($rawClass) { $rawClass.Split('.') | Where-Object { $_ } | ForEach-Object { Out-PSLiteral $_ } } else { @() }
                $attrString = $tagMatch[4]
                $explicitSlash = [bool]$tagMatch[5]
                $operator = $tagMatch[6]
                $inlineContent = $tagMatch[7]
                
                $hasNested = ($nextContentIndent -gt $indent)

                # Block Expansion (: tag)
                if ($inlineContent -match '^:\s*(.*)') {
                    $remaining = $matches[1]; $prefixExpr = Get-IndentExpr
                    $cParts = New-Object System.Collections.Generic.List[string]; $cParts.Add($prefixExpr + " + " + (Out-PSLiteral "<$tagName"))
                    if($id){ $cParts.Add((Out-PSLiteral " id=`"$id`"")) }
                    if($classes.Count -gt 0){ $cParts.Add("(Out-PugAttr 'class' @($($classes -join ', ')) `$false)") }
                    $cParts.Add((Out-PSLiteral ">")); $outputScript.Add($cParts -join " + ")
                    $stack.Push(@{ Indent = $indent; Tag = $tagName; IsCode = $false; IsMixin = $false; IsDefinition = $false; IsSwitch = $false; IsExplicit = $false })
                    
                    $lines[$i-1].Text = (" " * ($indent + 2)) + $remaining
                    $i--; continue
                }

                $isVoid = $voidTags -contains $tagName
                $hasContentOrChildren = (![string]::IsNullOrEmpty($inlineContent)) -or $hasNested
                
                $exprs = New-Object System.Collections.Generic.List[string]; $prefixExpr = Get-IndentExpr
                $exprs.Add($prefixExpr + " + " + (Out-PSLiteral "<$tagName"))
                
                if ($explodedAttrsExpr) {
                    if (-not $parentIsSwitch) { $outputScript.Add((Get-TraceLine $lineObj)) }
                    $htEntries = New-Object System.Collections.Generic.List[string]
                    if ($id) { $htEntries.Add("'id' = `"$id`"") }
                    $clsList = New-Object System.Collections.Generic.List[string]
                    foreach($c in $classes) { $clsList.Add($c) }
                    if ($attrString) {
                        foreach ($pair in (Get-PugAttributePairs $attrString)) {
                            if ($pair -match '^([^!=]+)\s*(!?=)\s*(.*)$') {
                                $ak = $matches[1].Trim(); $ao = $matches[2]; $val = $matches[3].Trim()
                                if ($ak -eq "class") { 
                                    $classVal = if($val){$val}else{'""'}
                                    $clsList.Add($classVal) 
                                }
                                elseif ($ak -eq "style") { 
                                    $styleVal = if($val){$val}else{'""'}
                                    $htEntries.Add("'style' = $styleVal") 
                                }
                                else {
                                    $psVal = if($val){$val}else{'$true'}
                                    if ($ao -eq '=') { $psVal = "[System.Net.WebUtility]::HtmlEncode($psVal)" }
                                    $htEntries.Add("'$ak' = $psVal")
                                }
                            } else {
                                $ak = $pair.Trim(); if ($ak) { $htEntries.Add("'$ak' = `$true") }
                            }
                        }
                    }
                    if ($clsList.Count -gt 0) { $htEntries.Add("'class' = @(" + ($clsList -join ", ") + ")") }
                    $inlineHt = "@{" + ($htEntries -join "; ") + "}"
                    $exprs.Add("(Out-PugMergedAttrs $inlineHt ($explodedAttrsExpr))")
                } else {
                    if ($id) { $exprs.Add((Out-PSLiteral " id=`"$id`"" )) }
                    $dynClasses = New-Object System.Collections.Generic.List[string]
                    foreach($c in $classes) { $dynClasses.Add($c) }
                    if ($attrString) {
                        foreach ($pair in (Get-PugAttributePairs $attrString)) {
                            if ($pair -match '^([^!=]+)\s*(!?=)\s*(.*)$') {
                                $ak = $matches[1].Trim(); $ao = $matches[2]; $val = $matches[3].Trim(); $psVal = ""
                                if ($val -eq "") { $psVal = '""' }
                                elseif (($val.StartsWith("'") -and $val.EndsWith("'")) -or ($val.StartsWith('"') -and $val.EndsWith('"'))) {
                                    $inner = $val.Substring(1, $val.Length - 2); $psVal = Out-PSEscaped $inner $isXmlMode
                                } else { 
                                    if (-not $parentIsSwitch) { $outputScript.Add((Get-TraceLine $lineObj)) }
                                    $psVal = $val 
                                }
                                if ($ak -eq "class") { $dynClasses.Add($psVal) }
                                else { $exprs.Add("(Out-PugAttr '$ak' ($psVal) " + $(if ($ao -eq '=') { '$true' } else { '$false' }) + ")") }
                            } else { $ak = $pair.Trim(); if ($ak) { $exprs.Add("(Out-PugAttr '$ak' `$true `$false)") } }
                        }
                    }
                    if ($dynClasses.Count -gt 0) { $exprs.Add("(Out-PugAttr 'class' @($($dynClasses -join ', ')) `$false)") }
                }
                
                if ($explicitSlash -and !$hasContentOrChildren) {
                    $exprs.Add((Out-PSLiteral " />"))
                } else {
                    if ($isVoid) {
                        $exprs.Add("`$(if (`$pug_voidSelfClose) { ' />' } else { '>' })")
                    } elseif (!$hasContentOrChildren) {
                        $exprs.Add("`$(if (`$pug_containerSelfClose) { ' />' } else { '>' })")
                    } else {
                        $exprs.Add((Out-PSLiteral ">"))
                    }

                    if ($inlineContent) {
                        if (-not $parentIsSwitch) { $outputScript.Add((Get-TraceLine $lineObj)) }
                        if ($operator -eq '=') { $exprs.Add("(Out-PugEnc ($inlineContent))") }
                        elseif ($operator -eq '!=') { $exprs.Add("($inlineContent)") }
                        else { $exprs.Add((Out-PSEscaped $inlineContent $isXmlMode)) }
                    }

                    if (!$isVoid) {
                        if ($hasNested) {
                            $stack.Push(@{ Indent = $indent; Tag = $tagName; IsCode = $false; IsMixin = $false; IsDefinition = $false; IsSwitch = $false; IsExplicit = $false })
                        } else {
                            if (!$hasContentOrChildren) {
                                $exprs.Add("`$(if (-not `$pug_containerSelfClose) { " + (Out-PSLiteral "</$tagName>") + " } else { '' })")
                            } else {
                                $exprs.Add((Out-PSLiteral "</$tagName>"))
                            }
                        }
                    }
                }
                $outputScript.Add($exprs -join " + "); continue
            }
            
            # If we reach here, the line was not matched by any parser rule
            throw (New-PugError -LineObj $lineObj -Detail "PUG parsing error: '$line'" -ContextRange $ErrorContextRange)
        }
        while ($stack.Count -gt 0) {
            $top = $stack.Pop(); if ($top.IsCode -or $top.IsMixin) { if (-not $top.IsExplicit) { $outputScript.Add("}") } }
            else { $closeIndent = if ($literalTags -contains $top.Tag) { "''" } else { Get-IndentExpr }
                $outputScript.Add($closeIndent + " + " + (Out-PSLiteral "</$($top.Tag)>")) }
        }
        
        $outputScript.Add(') -join "`n"')

        $outputScript.Add(@'
} catch {
    $_.Exception.Data["PugLine"] = $pug_src_line
    $_.Exception.Data["PugPath"] = $pug_src_path
    throw
}
'@)

        return [string]::Join("`n", $outputScript)
    }
}