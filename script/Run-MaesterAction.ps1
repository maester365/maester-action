param (
    [Parameter(Mandatory = $true, HelpMessage = 'The Entra Tenant Id')]
    [string]$TenantId,

    [Parameter(Mandatory = $true, HelpMessage = 'The Client Id of the Service Principal')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, HelpMessage = 'The path for the files and pester tests')]
    [string]$Path,

    [Parameter(Mandatory = $false, HelpMessage = "Maester 2 only. 'true' or empty installs the public tests into public-tests, 'false' skips them. Ignored on Maester 3, where the built-in tests ship in the module.")]
    [string]$IncludePublicTests = '',

    [Parameter(Mandatory = $false, HelpMessage = 'The Pester verbosity level')]
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$PesterVerbosity = 'None',

    [Parameter(Mandatory = $false, HelpMessage = 'The mail user id')]
    [string]$MailUser = '',

    [Parameter(Mandatory = $false, HelpMessage = 'The mail recipients separated by comma')]
    [string]$MailRecipients = '',

    [Parameter(Mandatory = $false, HelpMessage = 'The test result uri')]
    [string]$TestResultURI = '',

    [Parameter(Mandatory = $false, HelpMessage = 'The tags to include in the tests')]
    [string]$IncludeTags = '',

    [Parameter(Mandatory = $false, HelpMessage = 'The tags to exclude in the tests')]
    [string]$ExcludeTags = '',

    [Parameter(Mandatory = $false, HelpMessage = 'Include Exchange Online tests')]
    [bool]$IncludeExchange = $true,

    [Parameter(Mandatory = $false, HelpMessage = 'Include Teams tests')]
    [bool]$IncludeTeams = $true,

    [Parameter(Mandatory = $false, HelpMessage = 'Include long running tests')]
    [bool]$IncludeLongRunning = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Include preview tests')]
    [bool]$IncludePreview = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Include affected objects in the results and report')]
    [bool]$IncludeAffectedObjects = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Maester version to install, options: latest, preview, or specific version')]
    [string]$MaesterVersion = '',

    [Parameter(Mandatory = $false, HelpMessage = "The Maester major version to run: '2' (default) or '3'. latest and preview resolve within this major version.")]
    [string]$MaesterMajorVersion = '2',

    [Parameter(Mandatory = $false, HelpMessage = 'Maester 3 only. Run only the custom tests (Invoke-Maester -SkipBuiltIn).')]
    [bool]$SkipBuiltInTests = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Maester 3 only. Always install Pester 5.7.1 or later, even when no *.Tests.ps1 file is found.')]
    [bool]$InstallPester = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Maester 3 only. Test IDs to run, separated by comma (Invoke-Maester -TestId).')]
    [string]$TestIds = '',

    [Parameter(Mandatory = $false, HelpMessage = 'Maester 3 only. Test IDs to exclude, separated by comma (Invoke-Maester -ExcludeTestId).')]
    [string]$ExcludeTestIds = '',

    [Parameter(Mandatory = $false, HelpMessage = 'Maester 3 only. Path to a maester-config.json run configuration (Invoke-Maester -Config).')]
    [string]$ConfigPath = '',

    [Parameter(Mandatory = $false, HelpMessage = 'Disable telemetry')]
    [bool]$DisableTelemetry = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Debug run')]
    [bool]$IsDebug = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Add test results to GitHub step summary. Options: Full, Summary, Table, false. Legacy true is treated as Full.')]
    [string]$GitHubStepSummary = 'false',

    [Parameter(Mandatory = $false, HelpMessage = 'Teams Webhook Uri to send test results to, see: https://maester.dev/docs/monitoring/teams')]
    [string]$TeamsWebhookUri = $null,

    [Parameter(Mandatory = $false, HelpMessage = 'Teams notification channel ID')]
    [string]$TeamsChannelId = $null,

    [Parameter(Mandatory = $false, HelpMessage = 'Teams notification teams ID')]
    [string]$TeamsTeamId = $null
)

BEGIN {
    Write-Host "🔥 Maester Github Action 🔥 requested module: $MaesterVersion (major version: $MaesterMajorVersion)"

    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    . (Join-Path -Path $scriptPath -ChildPath 'MaesterActionHelpers.ps1')

    function Exit-MaesterAction {
        param (
            [string]$Title,
            [string]$Message
        )
        Write-Host "❌ $Message"
        Write-Host "::error title=$Title::$Message"
        exit 1
    }

    #region Validate inputs for the Maester major version
    try {
        $majorVersion = Get-MaesterMajorVersion -MajorVersion $MaesterMajorVersion
    } catch {
        Exit-MaesterAction -Title 'Invalid maester_major_version' -Message $_.Exception.Message
    }

    if ($majorVersion -eq 2) {
        # Inputs that only exist in Maester 3. Fail rather than silently ignoring them.
        $maester3Inputs = @(
            if ($SkipBuiltInTests) { 'skip_builtin_tests' }
            if (-not [string]::IsNullOrWhiteSpace($TestIds)) { 'test_ids' }
            if (-not [string]::IsNullOrWhiteSpace($ExcludeTestIds)) { 'exclude_test_ids' }
            if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { 'config_path' }
        )
        if ($maester3Inputs.Count -gt 0) {
            Exit-MaesterAction -Title 'Maester 3 inputs used with Maester 2' -Message "The input(s) $($maester3Inputs -join ', ') need Maester 3. Set maester_major_version: '3' to opt in (see https://maester.dev/docs/upgrading-from-2x), or remove them."
        }
        if ($InstallPester) {
            Write-Host "::warning title=install_pester ignored::install_pester only applies to Maester 3. Maester 2 installs Pester as a dependency."
        }
    } else {
        if ($PSVersionTable.PSVersion -lt [version]'7.4') {
            Exit-MaesterAction -Title 'PowerShell 7.4 required' -Message "Maester $majorVersion needs PowerShell 7.4 or later. This runner has PowerShell $($PSVersionTable.PSVersion)."
        }
        if (-not [string]::IsNullOrWhiteSpace($IncludePublicTests)) {
            Write-Host "::warning title=include_public_tests ignored::include_public_tests has no effect on Maester $majorVersion. The built-in tests ship inside the module and always run; set skip_builtin_tests: true to run only your custom tests."
        }
        $removedTags = @(Get-RemovedMaesterTag -Tags "$IncludeTags,$ExcludeTags")
        if ($removedTags.Count -gt 0) {
            Exit-MaesterAction -Title 'Removed tags' -Message "The tag(s) '$($removedTags -join "', '")' were removed in Maester 3.0. Remove them from include_tags / exclude_tags and use include_preview_tests instead of 'All' and include_longrunning_tests instead of 'Full'."
        }
    }
    #endregion

    #region Resolve and install Maester
    $requestedVersion = $MaesterVersion.Trim()
    if ([string]::IsNullOrEmpty($requestedVersion)) { $requestedVersion = 'latest' }

    $availableVersions = @()
    if ($requestedVersion -in 'latest', 'preview') {
        try {
            $availableVersions = @(Find-Module -Name Maester -AllVersions -AllowPrerelease:($requestedVersion -eq 'preview') -ErrorAction Stop | ForEach-Object { [string]$_.Version })
        } catch {
            Exit-MaesterAction -Title 'Failed to find Maester' -Message "Failed to list the Maester versions in the PowerShell Gallery. $($_.Exception.Message)"
        }
    }

    try {
        $resolvedVersion = Resolve-MaesterVersion -MaesterVersion $requestedVersion -MajorVersion $majorVersion -AvailableVersions $availableVersions
    } catch {
        Exit-MaesterAction -Title 'Invalid Maester version' -Message $_.Exception.Message
    }
    Write-Host "📦 Resolved Maester version: $($resolvedVersion.Version) (maester_version: '$requestedVersion', maester_major_version: '$majorVersion')"

    try {
        Install-Module Maester -Scope CurrentUser -RequiredVersion $resolvedVersion.Version -AllowPrerelease -Force -ErrorAction Stop
    } catch {
        Write-Error "❌ Failed to install Maester version $($resolvedVersion.Version). Please check the version number."
        Write-Error $_.Exception.Message
        Write-Host "::error ::Failed to install Maester version $($resolvedVersion.Version). Please check the version number."
        exit 1
    }

    # Import the resolved version, so a different Maester version on a self-hosted runner is not picked up
    $resolvedBaseVersion = (ConvertTo-MaesterSemVer -Version $resolvedVersion.Version).Base
    Import-Module Maester -RequiredVersion $resolvedBaseVersion -Force -ErrorAction SilentlyContinue
    $installedModule = Get-Module -Name 'Maester' | Sort-Object -Property Version -Descending | Select-Object -First 1
    if ($null -eq $installedModule) {
        Exit-MaesterAction -Title 'Failed to import Maester' -Message "Maester $($resolvedVersion.Version) was installed but could not be imported."
    }
    $installedVersion = $installedModule | Select-Object -ExpandProperty Version
    Write-Host "📃 Installed Maester version: $($resolvedVersion.Version) (major version $majorVersion)"
    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "maester_version=$($resolvedVersion.Version)"
    }
    #endregion

    # Maester 2: if specified, install/update public-tests to the version in the current module.
    # Maester 3 ships the built-in tests inside the module, so there is nothing to install.
    if ($majorVersion -eq 2 -and ($IncludePublicTests -eq 'true' -or [string]::IsNullOrWhiteSpace($IncludePublicTests))) {
        $publicTestsPath = Join-Path -Path $Path -ChildPath 'public-tests'
        Install-MaesterTests -Path $publicTestsPath
    }

    # if command Get-MtAccessTokenUsingCli is not found, import the file with dot-sourcing
    if (-not (Get-Command Get-MtAccessTokenUsingCli -ErrorAction SilentlyContinue)) {
        $accessTokenScript = Join-Path -Path $scriptPath -ChildPath 'Get-MtAccessTokenUsingCli.ps1'
        if (Test-Path $accessTokenScript) {
            Write-Debug "Importing script: $accessTokenScript"
            . $accessTokenScript
        } else {
            Write-Error "❌ Access token script not found: $accessTokenScript"
            exit 1
            return
        }
    }

    # Load new MarkdownWriter
    $markdownReportScript = Join-Path -Path $scriptPath -ChildPath 'Get-MtMarkdownReportAction.ps1'
    # Normalise the step summary input once: legacy 'true' → 'Full', 'false' / empty / anything else → disabled
    $summaryMode = switch ($GitHubStepSummary.ToLower()) {
        'true'    { 'Full' }
        'full'    { 'Full' }
        'summary' { 'Summary' }
        'table'   { 'Table' }
        default   { 'Disabled' }
    }
    # Test if we even need this script since it is included in version 1.0.79 or higher
    if (($summaryMode -ne 'Disabled') -and ($installedVersion -lt [version]'1.0.79')) {
        if (Test-Path $markdownReportScript) {
            Write-Debug "Importing script: $markdownReportScript"
            . $markdownReportScript
        } else {
            Write-Host "❔ Better markdown report not loaded: $markdownReportScript"
        }
    }

    # Check if $Path is set and if it is a valid path
    # if not replace it with the current directory
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path $Path)) {
            Write-Host "The provided path does not exist: $Path. Using current directory."
            $Path = (Get-Location).Path
        } else {
            Write-Host "📃 Using provided path: $Path"
        }
    } else {
        $Path = (Get-Location).Path
        Write-Host "❔ No path provided. Using current directory $Path."
    }

    # Maester 3 does not depend on Pester. Install it only when there are Pester-format custom tests
    # (*.Tests.ps1) or when it was requested; otherwise those tests are reported as PesterNotAvailable errors.
    if ($majorVersion -ge 3) {
        $pesterTestFiles = @(Get-ChildItem -Path $Path -Filter '*.Tests.ps1' -Recurse -File -ErrorAction SilentlyContinue)
        if ($InstallPester -or $pesterTestFiles.Count -gt 0) {
            if ($pesterTestFiles.Count -gt 0) {
                Write-Host "📃 Found $($pesterTestFiles.Count) Pester-format test file(s) (*.Tests.ps1), Pester 5.7.1 or later is needed."
            }
            $pesterModule = Get-Module -Name Pester -ListAvailable | Where-Object { $_.Version -ge [version]'5.7.1' } | Sort-Object -Property Version -Descending | Select-Object -First 1
            if ($pesterModule) {
                Write-Host "📃 Using installed Pester version: $($pesterModule.Version)"
            } else {
                try {
                    Install-Module Pester -MinimumVersion 5.7.1 -Scope CurrentUser -SkipPublisherCheck -Force -ErrorAction Stop
                    $pesterModule = Get-Module -Name Pester -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
                    Write-Host "📃 Installed Pester version: $($pesterModule.Version)"
                } catch {
                    Exit-MaesterAction -Title 'Failed to install Pester' -Message "Failed to install Pester 5.7.1 or later, which the Pester-format custom tests need. $($_.Exception.Message)"
                }
            }
        } else {
            Write-Host '📃 No Pester-format custom tests (*.Tests.ps1) found, Pester is not installed.'
        }

        if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and -not (Test-Path -Path $ConfigPath -PathType Leaf)) {
            Exit-MaesterAction -Title 'Config not found' -Message "The config_path '$ConfigPath' does not exist."
        }
    }
}
PROCESS {
    $graphToken = Get-MtAccessTokenUsingCli -ResourceUrl 'https://graph.microsoft.com' -AsSecureString

    # Connect to Microsoft Graph with the token as secure string
    Connect-MgGraph -AccessToken $graphToken -NoWelcome
    Write-Host "✔️ Graph connected"

    # Check if we need to connect to Exchange Online
    if ($IncludeExchange) {
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
        Import-Module ExchangeOnlineManagement

        $outlookToken = Get-MtAccessTokenUsingCli -ResourceUrl 'https://outlook.office365.com'
        Connect-ExchangeOnline -AccessToken $outlookToken -AppId $ClientId -Organization $TenantId -ShowBanner:$false
        Write-Host "✔️ Exchange Online connected."
    } else {
        Write-Host '📃 Exchange Online tests will be skipped.'
    }

    # Check if we need to connect to Teams
    if ($IncludeTeams) {
        Install-Module MicrosoftTeams -Scope CurrentUser -Force
        Import-Module MicrosoftTeams

        $teamsToken = Get-MtAccessTokenUsingCli -ResourceUrl '48ac35b8-9aa8-4d74-927d-1f4a14a0b239'

        $regularGraphToken = ConvertFrom-SecureString -SecureString $graphToken -AsPlainText
        $tokens = @($regularGraphToken, $teamsToken)
        Connect-MicrosoftTeams -AccessTokens $tokens -Verbose
        Write-Host "✔️ Microsoft Teams connected."
    } else {
        Write-Host '📃 Teams tests will be skipped.'
    }

    $MaesterParameters = @{
        Path                 = $Path
        Verbosity            = $PesterVerbosity
        OutputFolder         = 'test-results'
        OutputFolderFileName = 'test-results'
        PassThru             = $true
        NonInteractive       = $true
    }

    if ($majorVersion -eq 2) {
        # Configure test results
        $PesterConfiguration = New-PesterConfiguration
        $PesterConfiguration.Output.Verbosity = $PesterVerbosity
        Write-Host "📃 Pester verbosity level set to: $($PesterConfiguration.Output.Verbosity.Value)"
        $MaesterParameters.Add( 'PesterConfiguration', $PesterConfiguration )
    } else {
        # Maester 3 does not need Pester: -Verbosity also applies to Pester-format custom tests.
        Write-Host "📃 Verbosity level set to: $PesterVerbosity"

        if ($SkipBuiltInTests) {
            $MaesterParameters.Add( 'SkipBuiltIn', $true )
            Write-Host '📃 Skipping the built-in tests, running custom tests only.'
        }

        $TestIdList = @(Split-MaesterInputList -Value $TestIds)
        if ($TestIdList.Count -gt 0) {
            $MaesterParameters.Add( 'TestId', $TestIdList )
            Write-Host "📃 Including tests with IDs: $TestIdList"
        }

        $ExcludeTestIdList = @(Split-MaesterInputList -Value $ExcludeTestIds)
        if ($ExcludeTestIdList.Count -gt 0) {
            $MaesterParameters.Add( 'ExcludeTestId', $ExcludeTestIdList )
            Write-Host "📃 Excluding tests with IDs: $ExcludeTestIdList"
        }

        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            $MaesterParameters.Add( 'Config', (Resolve-Path -Path $ConfigPath).Path )
            Write-Host "📃 Using run configuration: $ConfigPath"
        }
    }

    # Check if test tags are provided
    if ( [string]::IsNullOrWhiteSpace($IncludeTags) -eq $false ) {
        $TestTags = $IncludeTags -split ','
        $MaesterParameters.Add( 'Tag', $TestTags )
        Write-Host "📃 Including tests with tags: $TestTags"
    }

    # Check if exclude test tags are provided
    if ( [string]::IsNullOrWhiteSpace($ExcludeTags) -eq $false ) {
        $ExcludeTestTags = $ExcludeTags -split ','
        $MaesterParameters.Add( 'ExcludeTag', $ExcludeTestTags )
        Write-Host "📃 Excluding tests with tags: $ExcludeTestTags"
    }

    # Check if long running tests are enabled
    if ($IncludeLongRunning) {
         $MaesterParameters.Add('IncludeLongRunning', $true)
         Write-Host "📃 Including long running tests."
    }

    # Check if preview tests are enabled
    if ($IncludePreview) {
         $MaesterParameters.Add('IncludePreview', $true)
         Write-Host "📃 Including preview tests."
    }

    # Check if affected objects are enabled
    if ($IncludeAffectedObjects) {
         $MaesterParameters.Add('IncludeAffectedObjects', $true)
         Write-Host "📃 Including affected objects."
    }

    # Check if mail recipients and mail userid are provided
    if ( [string]::IsNullOrWhiteSpace($MailUser) -eq $false ) {
        if ( [string]::IsNullOrWhiteSpace( $MailRecipients ) -eq $false ) {
            # Add mail parameters
            $MaesterParameters.Add( 'MailUserId', $MailUser )
            $Recipients = $MailRecipients -split ','
            $MaesterParameters.Add( 'MailRecipient', $Recipients )
            $MaesterParameters.Add( 'MailTestResultsUri', $TestResultURI )
            Write-Host "📃 Mail notification configured"
        } else {
            Write-Warning 'Mail recipients are not provided. Skipping mail notification.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($TeamsChannelId) -eq $false -and [string]::IsNullOrWhiteSpace($TeamsTeamId) -eq $false) {
        $MaesterParameters.Add( 'TeamChannelId', $TeamsChannelId )
        $MaesterParameters.Add( 'TeamId', $TeamsTeamId )
        Write-Host "📃 Teams notifications configured on Team ID"
    }

    # Check if disable telemetry is provided
    if ($DisableTelemetry ) {
        $MaesterParameters.Add( 'DisableTelemetry', $true )
        Write-Host "📃 Telemetry disabled 🛑."
    }

    # Check if Teams Webhook Uri is provided
    if ($TeamsWebhookUri) {
        $MaesterParameters.Add( 'TeamChannelWebhookUri', $TeamsWebhookUri )
        Write-Host "::add-mask::$TeamsWebhookUri"
        Write-Host "📃 Teams Webhook Uri configured."
    }

    if ($IsDebug) {
        Write-Debug "Debug mode is enabled. Parameters: $($MaesterParameters | Out-String)"
    }


    # Check all parameters against the installed Maester version and remove the ones that are not supported
    # A warning to show which parameters are not supported seems better then not executing any tests at all
    $maesterCommand = Get-Command -Name Invoke-Maester
    $missingParameters = $MaesterParameters.Keys | Where-Object { $_ -notin  $maesterCommand.Parameters.Keys }
    foreach ($parameter in $missingParameters) {
        Write-Host "❌ Maester version: $($maesterCommand.Version) does not support parameter '-$parameter'. Please check version compatibility."
        $MaesterParameters.Remove($parameter)
    }

    try {
        # Run Maester tests
        Write-Host "🕑 Start test execution $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $results = Invoke-Maester @MaesterParameters
        Write-Host "🕑 Maester tests executed $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    } catch {
        Write-Error "Failed to run Maester tests. Please check the parameters. $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber) in $($_.InvocationInfo.ScriptName)"
        Write-Host "::error file=$($_.InvocationInfo.ScriptName),line=$($_.InvocationInfo.ScriptLineNumber),title=Maester exception::Failed to run Maester tests. Please check the parameters."
        exit $LASTEXITCODE
        return
    }

    if ($null -eq $results) {
        Write-Host "❌No test results found. Please check the parameters."
        Write-Host "::error title=No test results::No test results found. Please check the parameters."
        exit 1
    }

    # Write output variable
    $testResultsFile = "test-results/test-results.json"
    $fullTestResultsFile = Resolve-Path -Path $testResultsFile -ErrorAction SilentlyContinue
    if (Test-Path $fullTestResultsFile) {
        try {
            Write-Host "📝 Setting output variables"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "results_json=$fullTestResultsFile"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "tests_total=$($results.TotalCount)"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "tests_failed=$($results.FailedCount)"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "tests_passed=$($results.PassedCount)"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "tests_skipped=$($results.SkippedCount)"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "result=$($results.Result)"

        } catch {
            Write-Host "❌ Failed to write to output variable. $($_.Exception.Message) at $($_.InvocationInfo.Line) in $($_.InvocationInfo.ScriptName)"
            Write-Host "::error file=$($_.InvocationInfo.ScriptName),line=$($_.InvocationInfo.Line),title=Maester exception::Failed to write test result location to output variable."
        }
    }


    # Replace test results markdown file with the new one
    # Check if the 'Get-MtMarkdownReportAction' function is available, this is an improved version to fix all reports under version 1.0.79-preview
    if (Get-Command Get-MtMarkdownReportAction -ErrorAction SilentlyContinue) {
        $testResultsFile = "test-results/test-results.md"
        Move-Item -Path $testResultsFile -Destination "test-results/test-results-orig.md" -Force -ErrorAction SilentlyContinue
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
        $templateFile = Join-Path -Path $scriptPath -ChildPath 'ReportTemplate.md'
        $markdownReport = Get-MtMarkdownReportAction $results $templateFile
        $markdownReport | Out-File -FilePath $testResultsFile -Encoding UTF8 -Force
        Write-Host "🧪 Alternative markdown report generated: $testResultsFile"
    }

    # Write the markdown report to the Github step summary file
    # ($summaryMode was normalised from the step summary input earlier)
    if ($summaryMode -ne 'Disabled') {
        Write-Host "📝 Adding test results to GitHub step summary (mode: $summaryMode)"

        # Build the markdown content for the selected mode into a single string,
        # so the size check/truncation only has to run once before writing.
        $summaryContent = $null

        if ($summaryMode -eq 'Full') {
            # Full mode: use the complete markdown report file (original behaviour)
            $filePath = 'test-results/test-results.md'
            if (Test-Path $filePath) {
                $summaryContent = Get-Content $filePath -Raw
            } else {
                Write-Host "❌ Markdown report not found: $filePath"
            }
        } else {
            # Table and Summary modes: generate compact markdown directly from $results
            $summaryContent = @"
# <img src="https://maester.dev/img/logo.svg" alt="Maester logo" height="40" width="40" /> Maester Test Results

**Tenant:** $($results.TenantName)

**Date:** $($results.ExecutedAt)

| 🔥 <br/> Total Tests | ✅ <br/> Passed | ❌ <br/> Failed | ❔ <br/> Not Run |
|:-:|:-:|:-:|:-:|
| **$($results.TotalCount)** | **$($results.PassedCount)** | **$($results.FailedCount)** | **$($results.NotRunCount)** |
"@

            if ($summaryMode -eq 'Summary') {
                # Summary mode: also append the per-test pass/fail table
                $StatusIcon = @{
                    Passed  = '✅'
                    Failed  = '❌'
                    NotRun  = '❔'
                    Skipped = '🚫'
                }
                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.Append("`n## Test Summary`n`n| Test | Status |`n|-|:-:|`n")
                foreach ($test in $results.Tests) {
                    $icon = if ($StatusIcon.ContainsKey($test.Result)) { $StatusIcon[$test.Result] } else { '❔' }
                    [void]$sb.Append("| $($test.Name) | $icon |`n")
                }
                $summaryContent += $sb.ToString()
            }
        }

        # Single size check for all modes: GitHub's step summary limit is 1024 KB.
        if (-not [string]::IsNullOrEmpty($summaryContent)) {
            $maxSize = 1000KB # GitHub's limit is 1024 KB, but we leave some room for the truncation message and encoding overhead
            $truncationMsg = "`n`n**⚠ TRUNCATED: Output exceeded GitHub's 1024 KB limit.**"

            $summaryBytes = [System.Text.Encoding]::UTF8.GetBytes($summaryContent)
            if ($summaryBytes.Length -gt $maxSize) {
                Write-Host "❌ Truncating output to prevent failure."
                $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($truncationMsg)
                $maxContentBytes = $maxSize - $msgBytes.Length - 4KB
                if ($maxContentBytes -lt 0) { $maxContentBytes = 0 }
                $summaryContent = ([System.Text.Encoding]::UTF8.GetString($summaryBytes, 0, [int]$maxContentBytes)) + $truncationMsg
            }

            Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summaryContent
        }
    }

}
END {
    Write-Host '🏁 Maester tests completed!'
    exit 0
    return
}
