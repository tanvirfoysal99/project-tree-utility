# Strict dependency-free tree YAML subset: block maps/sequences, scalar values,
# JSON-compatible double quotes, YAML single quotes, and literal block strings.
function Read-TreeYamlDocument {
    param([string]$FilePath)
    $lines = [IO.File]::ReadAllLines($FilePath)
    $tokens = New-Object 'System.Collections.Generic.List[object]'
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $raw = $lines[$lineIndex]
        if (-not $raw.Trim() -or $raw.TrimStart().StartsWith('#')) { continue }
        if ($raw -match '^ *\t') { throw ('YAML tabs are unsupported at line ' + ($lineIndex + 1)) }
        $indent = $raw.Length - $raw.TrimStart(' ').Length
        $text = $raw.Trim()
        if ($text -match '^-\s+([A-Za-z_][\w]*\s*:.*)$') {
            $tokens.Add([pscustomobject]@{ Indent=$indent; Text='-'; Line=$lineIndex+1; Block=$false; Value=$null })
            $text = $Matches[1]; $indent += 2
        }
        $token = [pscustomobject]@{ Indent=$indent; Text=$text; Line=$lineIndex+1; Block=$false; Value=$null }
        if ($text -match '^([A-Za-z_][\w]*)\s*:\s*\|([-+]?)$') {
            $key = $Matches[1]; $chomp = $Matches[2]
            $blockLines = New-Object 'System.Collections.Generic.List[string]'
            $blockIndent = -1
            while ($lineIndex + 1 -lt $lines.Count) {
                $next = $lines[$lineIndex + 1]
                $nextIndent = $next.Length - $next.TrimStart(' ').Length
                if ($next.Trim() -and $nextIndent -le $indent) { break }
                if ($next.Trim() -and $blockIndent -eq -1) { $blockIndent = $nextIndent }
                if ($next.Trim() -and $nextIndent -lt $blockIndent) { throw 'Inconsistent YAML literal block indentation.' }
                $lineIndex++
                $blockLines.Add($(if ($next.Trim()) { $next.Substring($blockIndent) } else { '' }))
            }
            $value = $blockLines -join "`n"
            if ($blockLines.Count) { $value += "`n" }
            if ($chomp -eq '-') { $value = $value.TrimEnd("`n") }
            elseif ($chomp -ne '+' -and $blockLines.Count) { $value = $value.TrimEnd("`n") + "`n" }
            $token.Text = $key + ':'; $token.Block = $true; $token.Value = $value
        }
        $tokens.Add($token)
    }
    function Read-Scalar([string]$Text) {
        $v = $Text.Trim()
        if ($v -eq '[]') { return ,@() }
        if ($v.StartsWith('"')) {
            try { return (ConvertFrom-Json -InputObject $v -ErrorAction Stop) } catch { throw 'Invalid YAML quoted scalar (use JSON escapes).' }
        }
        if ($v.StartsWith("'")) {
            if ($v -notmatch "^'(?:[^']|'')*'$" ) { throw 'Invalid YAML single-quoted scalar.' }
            return $v.Substring(1,$v.Length-2).Replace("''", "'")
        }
        if ($v -match '^(null|~)$') { return $null }
        if ($v -eq 'true') { return $true }
        if ($v -eq 'false') { return $false }
        if ($v -match '^[#\[\]{}&*!>|%@`]' -or $v -match ':\s' -or $v -match '\s#') {
            throw 'Unsupported YAML scalar syntax; quote the value.'
        }
        return $v
    }
    function Read-Block([ref]$Index, [int]$Indent) {
        if ($Index.Value -ge $tokens.Count) { throw 'Missing YAML block.' }
        $listMode = $tokens[$Index.Value].Text -match '^-(?:\s|$)'
        $list = New-Object 'System.Collections.Generic.List[object]'
        $map = [ordered]@{}
        while ($Index.Value -lt $tokens.Count) {
            $token = $tokens[$Index.Value]
            if ($token.Indent -lt $Indent) { break }
            if ($token.Indent -ne $Indent) { throw ('Unexpected YAML indentation at line ' + $token.Line) }
            $isList = $token.Text -match '^-(?:\s|$)'
            if ($isList -ne $listMode) { throw ('Mixed YAML mapping and sequence at line ' + $token.Line) }
            $Index.Value++
            if ($listMode) {
                $text = $token.Text.Substring(1).Trim()
                if ($text) { $list.Add((Read-Scalar $text)) }
                elseif ($Index.Value -lt $tokens.Count -and $tokens[$Index.Value].Indent -gt $Indent) {
                    $list.Add((Read-Block $Index $tokens[$Index.Value].Indent))
                } else { throw ('Empty YAML sequence item at line ' + $token.Line) }
            } else {
                if ($token.Text -notmatch '^([A-Za-z_][\w]*)\s*:\s*(.*)$') { throw ('Unsupported YAML mapping at line ' + $token.Line) }
                $key = $Matches[1]; $valueText = $Matches[2]
                if ($key -notin @('name','path','type','isdir','children','entries','template','content','contentDirective')) { throw ('Unsupported tree YAML key: ' + $key) }
                if ($map.Contains($key)) { throw ('Duplicate YAML key: ' + $key) }
                if ($token.Block) { $map[$key] = $token.Value }
                elseif ($valueText) { $map[$key] = Read-Scalar $valueText }
                elseif ($Index.Value -lt $tokens.Count -and $tokens[$Index.Value].Indent -gt $Indent) {
                    $map[$key] = Read-Block $Index $tokens[$Index.Value].Indent
                } else { $map[$key] = $null }
            }
        }
        if ($listMode) { return ,($list.ToArray()) }
        return [pscustomobject]$map
    }
    if (-not $tokens.Count) { throw 'Tree YAML document is empty.' }
    if ($tokens[0].Indent -ne 0) { throw 'Tree YAML must start at indentation zero.' }
    $index = 0
    $document = Read-Block ([ref]$index) 0
    if ($index -ne $tokens.Count) { throw 'Unconsumed YAML input.' }
    return ,$document
}
