<#
.SYNOPSIS
    Helper functions for Run-MaesterAction.ps1.

.DESCRIPTION
    These functions contain no side effects (no module installs, no network calls) so they can be unit tested.
    They decide which Maester version to install for the 'maester_version' and 'maester_major_version' inputs,
    and validate inputs that changed in Maester 3.0.
#>

# The Maester major versions this action knows how to run.
$script:SupportedMaesterMajorVersions = @(2, 3)

function ConvertTo-MaesterSemVer {
    <#
    .SYNOPSIS
        Parses a PowerShell Gallery version string such as '2.2.0' or '2.2.100-preview'.
        Returns $null when the string is not a valid version.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Version
    )

    $text = $Version.Trim()
    $basePart, $prerelease = $text -split '-', 2
    $base = $null
    if (-not [version]::TryParse($basePart, [ref]$base)) {
        return $null
    }

    [pscustomobject]@{
        Text       = $text
        Major      = $base.Major
        Base       = $base
        Prerelease = if ($prerelease) { $prerelease } else { '' }
    }
}

function Get-MaesterMajorVersion {
    <#
    .SYNOPSIS
        Validates the 'maester_major_version' input and returns it as an integer.
        Throws a message suitable for the workflow log when the value is not supported.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$MajorVersion
    )

    $value = $MajorVersion.Trim()
    if ([string]::IsNullOrEmpty($value)) {
        $value = '2'
    }

    $major = 0
    if (-not [int]::TryParse($value, [ref]$major) -or $major -notin $script:SupportedMaesterMajorVersions) {
        throw "maester_major_version '$MajorVersion' is not supported. Use one of: $($script:SupportedMaesterMajorVersions -join ', ')."
    }
    return $major
}

function Select-MaesterVersion {
    <#
    .SYNOPSIS
        Picks the newest version within a major version from a list of available version strings.
    .PARAMETER AllowPrerelease
        Include prerelease (preview) versions. A stable release wins over a prerelease of the same version,
        which matches how Install-Module -AllowPrerelease picks the newest version.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$AvailableVersions,

        [Parameter(Mandatory = $true)]
        [int]$MajorVersion,

        [switch]$AllowPrerelease
    )

    $candidates = foreach ($version in $AvailableVersions) {
        $parsed = ConvertTo-MaesterSemVer -Version $version
        if ($null -eq $parsed -or $parsed.Major -ne $MajorVersion) { continue }
        if (-not $AllowPrerelease -and $parsed.Prerelease) { continue }
        $parsed
    }

    $newest = $candidates | Sort-Object -Property `
        @{ Expression = { $_.Base }; Descending = $true }, `
        @{ Expression = { [string]::IsNullOrEmpty($_.Prerelease) }; Descending = $true }, `
        @{ Expression = { $_.Prerelease }; Descending = $true } |
        Select-Object -First 1

    if ($null -eq $newest) {
        return $null
    }
    return $newest.Text
}

function Resolve-MaesterVersion {
    <#
    .SYNOPSIS
        Works out which Maester version to install from the 'maester_version' and 'maester_major_version' inputs.

    .DESCRIPTION
        - 'latest' (or empty): the newest stable release within the major version.
        - 'preview': the newest release within the major version, including prereleases.
        - an exact version: that version, which must belong to the major version.

        Returns an object with Version (the exact version string to install), Major and IsPrerelease.

    .PARAMETER AvailableVersions
        The versions published to the gallery. Only needed for 'latest' and 'preview'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$MaesterVersion,

        [Parameter(Mandatory = $true)]
        [int]$MajorVersion,

        [AllowEmptyCollection()]
        [string[]]$AvailableVersions = @()
    )

    $requested = $MaesterVersion.Trim()
    if ([string]::IsNullOrEmpty($requested)) {
        $requested = 'latest'
    }

    if ($requested -in 'latest', 'preview') {
        $allowPrerelease = $requested -eq 'preview'
        $selected = Select-MaesterVersion -AvailableVersions $AvailableVersions -MajorVersion $MajorVersion -AllowPrerelease:$allowPrerelease
        if (-not $selected) {
            $kind = if ($allowPrerelease) { 'release or preview' } else { 'stable release' }
            throw "No Maester $MajorVersion.x $kind was found in the PowerShell Gallery for maester_version '$requested' and maester_major_version '$MajorVersion'."
        }
        $parsed = ConvertTo-MaesterSemVer -Version $selected
    } else {
        $parsed = ConvertTo-MaesterSemVer -Version $requested
        if ($null -eq $parsed) {
            throw "maester_version '$MaesterVersion' is not valid. Use 'latest', 'preview' or an exact version number such as '$MajorVersion.0.0'."
        }
        if ($parsed.Major -ne $MajorVersion) {
            if ($parsed.Major -ge 3 -and $MajorVersion -lt 3) {
                throw "maester_version '$requested' is a Maester $($parsed.Major) release, but maester_major_version is '$MajorVersion'. To opt in to Maester $($parsed.Major), also set maester_major_version: '$($parsed.Major)'. See https://maester.dev/docs/upgrading-from-2x before you upgrade."
            }
            throw "maester_version '$requested' is a Maester $($parsed.Major) release, but maester_major_version is '$MajorVersion'. Set maester_major_version: '$($parsed.Major)' or pick a $MajorVersion.x version."
        }
    }

    [pscustomobject]@{
        Version      = $parsed.Text
        Major        = $parsed.Major
        IsPrerelease = -not [string]::IsNullOrEmpty($parsed.Prerelease)
    }
}

function Get-RemovedMaesterTag {
    <#
    .SYNOPSIS
        Returns the tags that were removed in Maester 3.0 ('All' and 'Full') found in a comma separated tag list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Tags
    )

    $Tags -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -in 'All', 'Full' } | Select-Object -Unique
}

function Split-MaesterInputList {
    <#
    .SYNOPSIS
        Splits a comma separated action input into a trimmed list without empty entries.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
