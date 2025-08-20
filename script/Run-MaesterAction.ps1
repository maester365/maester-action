param (
    [Parameter(Mandatory = $true, HelpMessage = 'The Entra Tenant Id')]
    [string]$TenantId,

    [Parameter(Mandatory = $true, HelpMessage = 'The Client Id of the Service Principal')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, HelpMessage = 'The path for the files and pester tests')]
    [string]$Path,

    [Parameter(Mandatory = $false, HelpMessage = 'If true, auto-update tests in public-tests to the version in the current module')]
    [bool]$IncludePublicTests = $true,

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

    [Parameter(Mandatory = $false, HelpMessage = 'Include Purview tests')]
    [bool]$IncludePurview = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Include Teams tests')]
    [bool]$IncludeTeams = $true,

    [Parameter(Mandatory = $false, HelpMessage = 'Maester version to install, options: latest, preview, or specific version')]
    [string]$MaesterVersion = '',

    [Parameter(Mandatory = $false, HelpMessage = 'Disable telemetry')]
    [bool]$DisableTelemetry = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Debug run')]
    [bool]$IsDebug = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Add test results to GitHub step summary')]
    [bool]$GitHubStepSummary = $false,

    [Parameter(Mandatory = $false, HelpMessage = 'Teams Webhook Uri to send test results to, see: https://maester.dev/docs/monitoring/teams')]
    [string]$TeamsWebhookUri = $null,

    [Parameter(Mandatory = $false, HelpMessage = 'Teams notification channel ID')]
    [string]$TeamsChannelId = $null,

    [Parameter(Mandatory = $false, HelpMessage = 'Teams notification teams ID')]
    [string]$TeamsTeamId = $null
)

BEGIN {
    Write-Host "🔥 Maester Github Action 🔥 requested module: $MaesterVersion"

    # Install Maester
    if ($MaesterVersion -eq "latest" -or $MaesterVersion -eq "") {
        Install-Module Maester -Force
    } elseif ($MaesterVersion -eq "preview") {
        Install-Module Maester -AllowPrerelease -Force
    } else { # it is not empty and not latest or preview
        try {
            Install-Module Maester -RequiredVersion $MaesterVersion -AllowPrerelease -Force
        } catch {
            Write-Error "❌ Failed to install Maester version $MaesterVersion. Please check the version number."
            Write-Error $_.Exception.Message
            Write-Host "::error ::Failed to install Maester version $MaesterVersion. Please check the version number."
            exit 1
        }
    }

    # Get installed version of Maester
    Import-Module Maester -Force -ErrorAction SilentlyContinue
    $installedModule = Get-Module Maester -ListAvailable | Where-Object { $_.Name -eq 'Maester' } | Select-Object -First 1
    $installedVersion = $installedModule | Select-Object -ExpandProperty Version
    Write-Host "📃 Installed Maester version: $installedVersion"

    # If specified, install/update public-tests to the version in the current module
    if ($IncludePublicTests -eq $true) {
        $publicTestsPath = Join-Path -Path $Path -ChildPath 'public-tests'
        Install-MaesterTests -Path $publicTestsPath
    }

    # if command Get-MtAccessTokenUsingCli is not found, import the file with dot-sourcing
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
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
    # Test if we even need this script since it is included in version 1.0.79 or higher
    if (($GitHubStepSummary -eq $true) -and ($installedVersion -lt [version]'1.0.79')) {
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
            $Path = Get-Location
        } else {
            Write-Host "📃 Using provided path: $Path"
        }
    } else {
        $Path = Get-Location
        Write-Host "❔ No path provided. Using current directory $Path."
    }
}
PROCESS {
    $graphToken = Get-MtAccessTokenUsingCli -ResourceUrl 'https://graph.microsoft.com' -AsSecureString

    # Connect to Microsoft Graph with the token as secure string
    Connect-MgGraph -AccessToken $graphToken -NoWelcome
    Write-Host "✔️ Graph connected"

    # Check if we need to connect to Exchange Online or Purview
    if ($IncludeExchange -or $IncludePurview) {
        Install-Module ExchangeOnlineManagement -Force
        Import-Module ExchangeOnlineManagement

        $outlookToken = Get-MtAccessTokenUsingCli -ResourceUrl 'https://outlook.office365.com'

        # Check if we need to connect to Exchange Online
        if ($IncludeExchange) {
            Connect-ExchangeOnline -AccessToken $outlookToken -AppId $ClientId -Organization $TenantId -ShowBanner:$false
            Write-Host "✔️ Exchange Online connected."
        } else {
            Write-Host '📃 Exchange Online tests will be skipped.'
        }

        # Check if we need to connect to Purview
        if ($IncludePurview) {
            $domains = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/domains?`$select=id,isDefault"
            $primaryDomain = $domains.value | Where-Object { $_.isDefault -eq $true } | Select-Object -ExpandProperty id

            Connect-IPPSSession -AccessToken $outlookToken -Organization $primaryDomain -ShowBanner:$false
            Write-Host "✔️ Purview connected."
        } else {
            Write-Host '📃 Purview tests will be skipped.'
        }
    }

    # Check if we need to connect to Teams
    if ($IncludeTeams) {
        Install-Module MicrosoftTeams -Force
        Import-Module MicrosoftTeams

        $teamsToken = Get-MtAccessTokenUsingCli -ResourceUrl '48ac35b8-9aa8-4d74-927d-1f4a14a0b239'

        $regularGraphToken = ConvertFrom-SecureString -SecureString $graphToken -AsPlainText
        $tokens = @($regularGraphToken, $teamsToken)
        Connect-MicrosoftTeams -AccessTokens $tokens
        Write-Host "✔️ Microsoft Teams connected."
    } else {
        Write-Host '📃 Teams tests will be skipped.'
    }

    # Configure test results
    $PesterConfiguration = New-PesterConfiguration
    $PesterConfiguration.Output.Verbosity = $PesterVerbosity
    Write-Host "📃 Pester verbosity level set to: $($PesterConfiguration.Output.Verbosity.Value)"

    $MaesterParameters = @{
        Path                 = $Path
        PesterConfiguration  = $PesterConfiguration
        OutputFolder         = 'test-results'
        OutputFolderFileName = 'test-results'
        PassThru             = $true
        NonInteractive       = $true
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
    if ($missingParameters) {
        Write-Host "❌ Maester version: $($maesterCommand.Version) does not support $missingParameters parameters. Please check version compatibility."
        $MaesterParameters.Remove($missingParameters)
    }

    try {
        # Run Maester tests
        Write-Host "🕑 Start test execution $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $results = Invoke-Maester @MaesterParameters
        Write-Host "🕑 Maester tests executed $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    } catch {
        Write-Error "Failed to run Maester tests. Please check the parameters. $($_.Exception.Message) at $($_.InvocationInfo.Line) in $($_.InvocationInfo.ScriptName)"
        Write-Host "::error file=$($_.InvocationInfo.ScriptName),line=$($_.InvocationInfo.Line),title=Maester exception::Failed to run Maester tests. Please check the parameters."
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
    if ($GitHubStepSummary) {
        Write-Host "📝 Adding test results to GitHub step summary"
        # Add step summary
        $filePath = "test-results/test-results.md"
        if (Test-Path $filePath) {
            $maxSize = 1024KB
            $truncationMsg = "`n`n**⚠ TRUNCATED: Output exceeded GitHub's 1024 KB limit.**"

            # Check file size
            $fileSize = (Get-Item $filePath).Length
            if ($fileSize -gt $maxSize) {
                Write-Host "❌ Truncating output file to prevent failure."

                # Read the file content
                $content = Get-Content $filePath -Raw

                # Calculate the maximum content size to fit within the limit
                $maxContentSize = $maxSize - ($truncationMsg.Length * [System.Text.Encoding]::UTF8.GetByteCount("a")) - 4KB

                # Truncate the content
                $truncatedContent = $content.Substring(0, $maxContentSize / [System.Text.Encoding]::UTF8.GetByteCount("a"))

                # Write the truncated content and truncation message to the new file
                $truncatedContent | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Append
                Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $truncationMsg

            } else {
                Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $(Get-Content $filePath)
            }
        } else {
            Write-Host "❌ Markdown report not found: $filePath"
        }
    }

}
END {
    Write-Host '🏁 Maester tests completed!'
    exit 0
    return
}
