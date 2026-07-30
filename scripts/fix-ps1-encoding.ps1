<#
.SYNOPSIS
    Make PowerShell scripts safe for Windows PowerShell 5.1.

.DESCRIPTION
    Windows PowerShell 5.1 decodes a BOM-less file as ANSI (Windows-1252), not UTF-8.
    An em-dash saved as UTF-8 (E2 80 94) then decodes to "a-EUR-rdquo", and that trailing
    U+201D is accepted by the tokenizer as a closing double quote - so the string ends
    early and the whole file fails to parse.

    Two passes:
      1. Replace typographic characters with ASCII equivalents.
      2. Any file that still holds non-ASCII (e.g. Persian UI strings) gets a UTF-8 BOM
         so 5.1 decodes it as UTF-8.

.PARAMETER Path
    Root folder to scan. Defaults to the repository root.

.PARAMETER WhatIf
    Report what would change without writing.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Path
)

if (-not $Path -or $Path.Count -eq 0) {
    $root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $Path = @((Resolve-Path (Join-Path $root '..')).Path)
}

$replacements = [ordered]@{
    [char]0x2014 = '-'    # em dash
    [char]0x2013 = '-'    # en dash
    [char]0x2026 = '...'  # ellipsis
    [char]0x2192 = '->'   # right arrow
    [char]0x00A0 = ' '    # non-breaking space
}

$skip = '\\(build|build-linux|node_modules|vendor|bin|obj|_deps|graphify-out)\\'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$normalized = 0
$bommed = 0
$scanned = 0

foreach ($root in $Path) {
    if (-not (Test-Path $root)) {
        Write-Warning "Skipping missing path: $root"
        continue
    }

    Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psm1, *.psd1 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skip } |
        ForEach-Object {
            $scanned++
            $file = $_.FullName
            $bytes = [System.IO.File]::ReadAllBytes($file)
            $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

            # Read as UTF-8 regardless: that is how the file was written on disk.
            $text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
            $original = $text

            foreach ($pair in $replacements.GetEnumerator()) {
                if ($text.IndexOf($pair.Key) -ge 0) {
                    $text = $text.Replace([string]$pair.Key, $pair.Value)
                }
            }

            $changedText = $text -ne $original
            $stillNonAscii = [regex]::IsMatch($text, '[^\x00-\x7F]')
            $needsBom = $stillNonAscii -and -not $hasBom

            if (-not $changedText -and -not $needsBom) {
                return
            }

            $reason = @()
            if ($changedText) { $reason += 'ascii-normalize' }
            if ($needsBom) { $reason += 'add-utf8-bom' }
            $rel = $file.Substring($root.Length).TrimStart('\')

            if ($PSCmdlet.ShouldProcess($rel, ($reason -join ' + '))) {
                # Keep the BOM when the file needs one (or already had one); otherwise stay pure ASCII.
                $encoding = if ($stillNonAscii) { $utf8Bom } else { New-Object System.Text.UTF8Encoding($false) }
                [System.IO.File]::WriteAllText($file, $text, $encoding)
                if ($changedText) { $script:normalized++ }
                if ($needsBom) { $script:bommed++ }
                Write-Host ("  fixed [{0}] {1}" -f ($reason -join ' + '), $rel)
            }
        }
}

Write-Host ""
Write-Host ("Scanned {0} script(s): {1} ascii-normalized, {2} given a UTF-8 BOM." -f $scanned, $normalized, $bommed)

# Fail loudly if anything still cannot be parsed by the local PowerShell.
$broken = @()
foreach ($root in $Path) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psm1 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $skip } |
        ForEach-Object {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
            if ($errors -and $errors.Count -gt 0) {
                $broken += "$($_.FullName): $($errors[0].Message)"
            }
        }
}

if ($broken.Count -gt 0) {
    Write-Host ""
    Write-Warning "Scripts still failing to parse:"
    $broken | ForEach-Object { Write-Warning "  $_" }
    exit 1
}

Write-Host "All scripts parse cleanly."
