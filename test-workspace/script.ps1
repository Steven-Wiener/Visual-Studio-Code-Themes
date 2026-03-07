#Requires -Version 7.2
<#
.SYNOPSIS
    theme_preview.ps1 — PowerShell syntax showcase
.DESCRIPTION
    Covers: classes, enums, advanced functions, pipeline, regex,
            error handling, jobs, format operators, here-strings
.PARAMETER Mode
    Generation mode: custom | random | personalized
.PARAMETER Palette
    Array of hex colour strings
.EXAMPLE
    .\theme_preview.ps1 -Mode random
    .\theme_preview.ps1 -Palette '#070425','#9900FF','#09FBD3'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('custom', 'random', 'personalized')]
    [string] $Mode    = 'custom',

    [ValidatePattern('^#[0-9A-Fa-f]{6}$')]
    [string[]] $Palette = @('#070425','#9900FF','#09FBD3','#5CB800'),

    [string] $OutputDir = '.\out',
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Enum ───────────────────────────────────────────────────────────────────────
enum ThemeStatus { Draft; Published; Archived }

# ── Classes ───────────────────────────────────────────────────────────────────
class HexColor {
    [string] hidden $_hex

    HexColor([string] $hex) {
        if ($hex -notmatch '^#[0-9A-Fa-f]{6}$') {
            throw [ArgumentException]::new("Invalid hex colour: '$hex'")
        }
        $this._hex = $hex.ToUpper()
    }

    [int] R() { return [Convert]::ToInt32($this._hex.Substring(1,2), 16) }
    [int] G() { return [Convert]::ToInt32($this._hex.Substring(3,2), 16) }
    [int] B() { return [Convert]::ToInt32($this._hex.Substring(5,2), 16) }

    [double] Luminance() {
        $linearise = { param($c) $v = $c / 255.0; if ($v -le 0.04045) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) } }
        return 0.2126 * (& $linearise $this.R()) +
               0.7152 * (& $linearise $this.G()) +
               0.0722 * (& $linearise $this.B())
    }

    [string] WithAlpha([byte] $alpha) {
        return '{0}{1:X2}' -f $this._hex, $alpha
    }

    [string] ToString() { return $this._hex }
}

class Theme {
    [string]      $Id
    [string]      $Name
    [HexColor[]]  $Palette
    [hashtable]   $Colors     = @{}
    [ThemeStatus] $Status     = [ThemeStatus]::Draft
    [int]         $InstallCount = 0
    [datetime]    $CreatedAt  = [datetime]::UtcNow

    Theme([string] $id, [string] $name) {
        $this.Id   = $id
        $this.Name = $name
    }

    [bool] IsDark() {
        return $this.Palette.Count -gt 0 -and $this.Palette[0].Luminance() -lt 0.5
    }

    [string] Slug() {
        return $this.Name.ToLower() -replace '[^a-z0-9]+', '-' -replace '^-|-$', ''
    }
}

# ── Advanced functions ─────────────────────────────────────────────────────────
function ConvertTo-Slug {
    [OutputType([string])]
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [string] $InputString)
    process {
        $InputString.ToLower() -replace '[^a-z0-9]+', '-' -replace '^-|-$', ''
    }
}

function Get-HexLightness {
    [OutputType([double])]
    param([Parameter(Mandatory)] [string] $Hex)
    ([HexColor]::new($Hex)).Luminance()
}

function Group-PaletteByLightness {
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [string[]] $Colors)
    $Colors | Group-Object -Property { Get-HexLightness $_ } -Descending
}

function New-ThemePackage {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]   $Name,
        [Parameter(Mandatory)] [string[]] $Palette,
        [string] $Description = ''
    )

    $sorted = Sort-PaletteByLightness -Colors $Palette
    $bg     = $sorted[0]
    $slug   = $Name | ConvertTo-Slug

    $package = [ordered] @{
        name        = $slug
        displayName = $Name
        description = $Description
        version     = '0.0.1'
        publisher   = 'Steven-Wiener'
        engines     = @{ vscode = '^1.91.1' }
        categories  = @('Themes')
        galleryBanner = @{ color = $bg; theme = 'dark' }
        contributes = @{
            themes = @(@{
                label   = $Name
                uiTheme = 'vs-dark'
                path    = "./themes/$slug-color-theme.json"
            })
        }
        keywords    = @('color-theme', 'dark-theme', 'vscode')
        license     = 'MIT'
        repository  = @{ type = 'git'; url = 'https://github.com/Steven-Wiener/Visual-Studio-Code-Themes' }
        sponsor     = @{ url = 'https://account.venmo.com/u/Steven-Wiener-1' }
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Generate package.json')) {
        return $package
    }
}

# ── Pipeline & filtering ───────────────────────────────────────────────────────
function Get-CommunityThemes {
    [OutputType([pscustomobject[]])]
    param()

    $themes = @(
        [pscustomobject]@{ Name = 'Dracula';         Bg = '#282a36'; Keywords = '#ff79c6'; Functions = '#50fa7b' }
        [pscustomobject]@{ Name = 'One Dark Pro';    Bg = '#282c34'; Keywords = '#c678dd'; Functions = '#61afef' }
        [pscustomobject]@{ Name = 'Monokai Pro';     Bg = '#272822'; Keywords = '#f92672'; Functions = '#a6e22e' }
        [pscustomobject]@{ Name = 'Tokyo Night';     Bg = '#1a1b26'; Keywords = '#9d7cd8'; Functions = '#7aa2f7' }
        [pscustomobject]@{ Name = 'Catppuccin Mocha';Bg = '#1e1e2e'; Keywords = '#cba6f7'; Functions = '#89b4fa' }
        [pscustomobject]@{ Name = 'Nord';            Bg = '#2e3440'; Keywords = '#81a1c1'; Functions = '#88c0d0' }
        [pscustomobject]@{ Name = 'SynthWave 84';   Bg = '#262335'; Keywords = '#fede5d'; Functions = '#72f1b8' }
        [pscustomobject]@{ Name = 'GitHub Dark';     Bg = '#0d1117'; Keywords = '#ff7b72'; Functions = '#d2a8ff' }
    )

    $themes | Add-Member -PassThru -NotePropertyName Luminance -NotePropertyValue {
        Get-HexLightness $this.Bg
    }.GetNewClosure() | ForEach-Object { $_ }
}

# ── Here-string ───────────────────────────────────────────────────────────────
function Get-License {
    param([string] $Author = 'Steven Wiener')
    $year = (Get-Date).Year
    @"
MIT License

Copyright (c) $year $Author

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
"@
}

# ── Error handling ────────────────────────────────────────────────────────────
function Invoke-WithRetry {
    param(
        [scriptblock] $ScriptBlock,
        [int]         $MaxAttempts = 3,
        [int]         $DelayMs     = 500
    )
    $attempt = 0
    do {
        $attempt++
        try   { return & $ScriptBlock }
        catch {
            if ($attempt -ge $MaxAttempts) { throw }
            Write-Warning "Attempt $attempt/$MaxAttempts failed: $_. Retrying in ${DelayMs}ms..."
            Start-Sleep -Milliseconds $DelayMs
            $DelayMs *= 2
        }
    } while ($attempt -lt $MaxAttempts)
}

# ── Main ───────────────────────────────────────────────────────────────────────
function Main {
    Write-Host "`n⚡ ThemePreview PowerShell — Mode: $Mode`n" -ForegroundColor Cyan

    # Display community themes
    $communityThemes = Get-CommunityThemes
    $communityThemes |
        Sort-Object Name |
        Format-Table Name,
            @{L='Background';  E={$_.Bg}; Width=10},
            @{L='Keywords';    E={$_.Keywords}; Width=10},
            @{L='Functions';   E={$_.Functions}; Width=10} `
        -AutoSize

    # Generate a package
    $pkg = New-ThemePackage -Name 'Neon Vomit Night' -Palette $Palette -Description 'Cyberpunk neon dark theme'

    if ($pkg) {
        $json = $pkg | ConvertTo-Json -Depth 10
        Write-Host "Generated package.json:`n" -ForegroundColor Green
        Write-Host $json
    }

    # HexColor class demo
    $colours = $Palette | ForEach-Object { [HexColor]::new($_) }
    $colours | ForEach-Object {
        Write-Host ("{0}  R={1,3} G={2,3} B={3,3}  Lum={4:F4}  Dark={5}" -f `
            $_, $_.R(), $_.G(), $_.B(), $_.Luminance(), ($_.Luminance() -lt 0.5))
    }

    # Parallel jobs
    $jobs = 1..4 | ForEach-Object {
        $n = $_
        Start-ThreadJob -ScriptBlock {
            param($num)
            Start-Sleep -Milliseconds (100 * $num)
            "Job $num complete"
        } -ArgumentList $n
    }

    $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job

    # License
    Write-Host "`n--- License ---`n" -ForegroundColor Yellow
    Get-License | Write-Host
}

Main
