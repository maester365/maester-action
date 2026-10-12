BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'script', 'MaesterActionHelpers.ps1')

    $script:Gallery = @(
        '3.0.1-preview', '3.0.0', '3.0.0-preview',
        '2.2.100-preview', '2.2.99-preview', '2.2.10-preview', '2.2.0', '2.1.0', '2.0.0',
        '1.3.137-preview', '1.3.0'
    )
}

Describe 'Get-MaesterMajorVersion' {
    It 'defaults to 2 when empty' {
        Get-MaesterMajorVersion -MajorVersion '' | Should -Be 2
    }
    It 'accepts <_>' -ForEach '2', '3', ' 3 ' {
        Get-MaesterMajorVersion -MajorVersion $_ | Should -Be ([int]$_.Trim())
    }
    It 'rejects <_>' -ForEach '1', '4', 'latest', '3.0' {
        { Get-MaesterMajorVersion -MajorVersion $_ } | Should -Throw '*not supported*'
    }
}

Describe 'Resolve-MaesterVersion' {
    Context 'major version 2 (default)' {
        It 'latest resolves to the newest 2.x stable release, not 3.0' {
            (Resolve-MaesterVersion -MaesterVersion 'latest' -MajorVersion 2 -AvailableVersions $Gallery).Version | Should -Be '2.2.0'
        }
        It 'empty is treated as latest' {
            (Resolve-MaesterVersion -MaesterVersion '' -MajorVersion 2 -AvailableVersions $Gallery).Version | Should -Be '2.2.0'
        }
        It 'preview resolves to the newest 2.x prerelease, comparing versions numerically' {
            $result = Resolve-MaesterVersion -MaesterVersion 'preview' -MajorVersion 2 -AvailableVersions $Gallery
            $result.Version | Should -Be '2.2.100-preview'
            $result.IsPrerelease | Should -BeTrue
        }
        It 'an exact 2.x version wins' {
            (Resolve-MaesterVersion -MaesterVersion '2.1.0' -MajorVersion 2).Version | Should -Be '2.1.0'
        }
        It 'an exact 3.x version fails and explains how to opt in' {
            { Resolve-MaesterVersion -MaesterVersion '3.0.0' -MajorVersion 2 } | Should -Throw "*maester_major_version: '3'*"
        }
    }

    Context 'major version 3 (opt-in)' {
        It 'latest resolves to the newest 3.x stable release' {
            (Resolve-MaesterVersion -MaesterVersion 'latest' -MajorVersion 3 -AvailableVersions $Gallery).Version | Should -Be '3.0.0'
        }
        It 'preview resolves to the newest 3.x release including prereleases' {
            (Resolve-MaesterVersion -MaesterVersion 'preview' -MajorVersion 3 -AvailableVersions $Gallery).Version | Should -Be '3.0.1-preview'
        }
        It 'a stable release wins over a prerelease of the same version' {
            (Resolve-MaesterVersion -MaesterVersion 'preview' -MajorVersion 3 -AvailableVersions '3.0.0-preview', '3.0.0').Version | Should -Be '3.0.0'
        }
        It 'preview finds a 3.0 prerelease before 3.0 is released' {
            (Resolve-MaesterVersion -MaesterVersion 'preview' -MajorVersion 3 -AvailableVersions '3.0.0-preview', '2.2.0').Version | Should -Be '3.0.0-preview'
        }
        It 'latest fails when no 3.x stable release exists yet' {
            { Resolve-MaesterVersion -MaesterVersion 'latest' -MajorVersion 3 -AvailableVersions '3.0.0-preview', '2.2.0' } | Should -Throw '*No Maester 3.x stable release*'
        }
        It 'an exact 2.x version fails' {
            { Resolve-MaesterVersion -MaesterVersion '2.2.0' -MajorVersion 3 } | Should -Throw "*maester_major_version is '3'*"
        }
    }

    It 'rejects a version that is not a number' {
        { Resolve-MaesterVersion -MaesterVersion 'newest' -MajorVersion 2 } | Should -Throw '*is not valid*'
    }
}

Describe 'Get-RemovedMaesterTag' {
    It 'finds All and Full regardless of case and spaces' {
        Get-RemovedMaesterTag -Tags 'CIS, all,Full,,EIDSCA' | Should -Be @('all', 'Full')
    }
    It 'returns nothing for other tags' {
        Get-RemovedMaesterTag -Tags 'CIS,Allowed,FullAccess' | Should -BeNullOrEmpty
    }
}

Describe 'Split-MaesterInputList' {
    It 'trims and drops empty entries' {
        Split-MaesterInputList -Value ' MT.1001, MT.1024.* ,,' | Should -Be @('MT.1001', 'MT.1024.*')
    }
    It 'returns nothing for an empty value' {
        Split-MaesterInputList -Value '' | Should -BeNullOrEmpty
    }
}
