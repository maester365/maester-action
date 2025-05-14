<#
.Synopsis
    Generates a markdown report using the Maester test results format.

.Description
    This markdown report can be used in GitHub actions to display the test results in a formatted way.

.Example
    $PesterResults = Invoke-Pester -PassThru
    $MaesterResults = ConvertTo-MtMaesterResult -PesterResults $PesterResults
    Get-MtMarkdownReport $MaesterResults
#>

function Get-MtMarkdownReportAction {
    [CmdletBinding()]
    param(
        # The Maester test results returned from `Invoke-Pester -PassThru | ConvertTo-MtMaesterResult`
        [Parameter(Mandatory = $true, Position = 0)]
        [PSObject] $MaesterResults,

        [Parameter(Mandatory = $false, Position = 1)]
        [string] $TemplateFile = [IO.Path]::Combine($PSScriptRoot, '..', 'assets', 'ReportTemplate.md')
    )

    $StatusIcon = @{
        Passed  = '<img src="https://maester.dev/img/test-result/pill-pass.png" height="25" alt="Passed"/>'
        Failed  = '<img src="https://maester.dev/img/test-result/pill-fail.png" height="25" alt="Failed"/>'
        NotRun  = '<img src="https://maester.dev/img/test-result/pill-notrun.png" height="25" alt="Not Run"/>'
        Skipped = '<img src="https://maester.dev/img/test-result/pill-notrun.png" height="25" alt="Not Run"/>'
    }

    $StatusIconSm = @{
        Passed  = '✅' # '<img src="https://maester.dev/img/test-result/icon-pass.png" alt="Passed icon" height="18" />'
        Failed  = '❌' # '<img src="https://maester.dev/img/test-result/icon-fail.png" alt="Failed icon" height="18" />'
        NotRun  = '❔' # '<img src="https://maester.dev/img/test-result/icon-notrun.png" alt="Not Run icon" height="18" />'
        Skipped = '🚫' # '<img src="https://maester.dev/img/test-result/icon-notrun.png" alt="Not Run icon" height="18" />'
    }

    function GetTestSummary() {
        $Summary = @'
|Test|Status|
|-|:-:|

'@
        foreach ($Test in $MaesterResults.Tests) {
            $Summary += "| $($Test.Name) | $($StatusIcon[$Test.Result]) |`n"
        }
        return $Summary
    }

    function GetTestDetails() {

        foreach ($Test in $MaesterResults.Tests) {

            $Details += "### $($StatusIconSm[$Test.Result]) $($Test.Name)`n`n"

            $Details += $StatusIcon[$Test.Result] -replace 'src', 'align="right" src'
            $Details += "`n`n"

            if (![string]::IsNullOrEmpty($Test.ResultDetail)) {
                # Test author has provided details
                $Details += "#### Overview`n`n$($Test.ResultDetail.TestDescription)`n`n"
                $Details += "#### Test Results`n`n$($Test.ResultDetail.TestResult)`n`n"
            } else {
                # Test author has not provided details, use default code in script
                # make sure we do not execute the code in the script block!
                $CleanedScriptBlock = $Test.ScriptBlock.ToString() -replace '%\w+%', '' -replace '\$_', '€_' # or show me how I can make it not execute the $_ thing
                $Details += "#### Overview`n`n``````ps1`n$CleanedScriptBlock`n```````n`n"
                if (![string]::IsNullOrEmpty($Test.ErrorRecord)) {
                    $Details += "#### Reason for failure`n`n$($Test.ErrorRecord)`n`n"
                }
            }

            if (![string]::IsNullOrEmpty($Test.HelpUrl)) { $Details += "**Learn more**: [$($Test.HelpUrl)]($($Test.HelpUrl))`n`n" }
            if (![string]::IsNullOrEmpty($Test.Tag)) {
                $Tags = '`{0}`' -f ($Test.Tag -join '` `')
                $Details += "**Tag**: $Tags`n`n"
            }

            if (![string]::IsNullOrEmpty($Test.Block)) {
                $Category = '`{0}`' -f ($Test.Block -join '` `')
                $Details += "**Category**: $Category`n`n"
            }

            if (![string]::IsNullOrEmpty($Test.ScriptBlockFile)) { $Details += "**Source**: ``$($Test.ScriptBlockFile)```n`n" }

            $Details += "---`n`n"
        }

        return $Details
    }

    #$MarkdownFilePath = Join-Path -Path $PSScriptRoot -ChildPath '../assets/ReportTemplate.md'
    $TemplateMarkdown = Get-Content -Path $TemplateFile -Raw

    $TextSummary = GetTestSummary
    $TextDetails = GetTestDetails

    $TemplateMarkdown = $TemplateMarkdown -replace '%TenantId%', $MaesterResults.TenantId
    $TemplateMarkdown = $TemplateMarkdown -replace '%TenantName%', $MaesterResults.TenantName
    $TemplateMarkdown = $TemplateMarkdown -replace '%TenantName%', $MaesterResults.TenantVersion
    $TemplateMarkdown = $TemplateMarkdown -replace '%ModuleVersion%', $MaesterResults.CurrentVersion
    $TemplateMarkdown = $TemplateMarkdown -replace '%TestDate%', $MaesterResults.ExecutedAt
    $TemplateMarkdown = $TemplateMarkdown -replace '%TotalCount%', $MaesterResults.TotalCount
    $TemplateMarkdown = $TemplateMarkdown -replace '%PassedCount%', $MaesterResults.PassedCount
    $TemplateMarkdown = $TemplateMarkdown -replace '%FailedCount%', $MaesterResults.FailedCount
    $TemplateMarkdown = $TemplateMarkdown -replace '%NotRunCount%', $MaesterResults.NotRunCount

    $TemplateMarkdown = $TemplateMarkdown -replace '%TestSummary%', $TextSummary
    $TemplateMarkdown = $TemplateMarkdown -replace '%TestDetails%', $TextDetails

    return $TemplateMarkdown
}
