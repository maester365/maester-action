# Maester 🔥 Github Action

![Maester Action](https://img.shields.io/badge/GitHub%20Action-Maester-red?style=for-the-badge&logo=github)

Monitor your Microsoft 365 tenant's security configuration using **Maester**, the PowerShell-based test automation framework.

Check out the [Maester documentation](https://maester.dev/) for more information on how to use Maester, or the [github action documentation](https://maester.dev/docs/monitoring/github) for more details on how to use the action.

> [!NOTE]
> This github action only supports [workload identity federation](https://maester.dev/docs/monitoring/github#set-up-the-github-actions-workflow) for authentication, since that is the recommended way to authenticate to Microsoft 365 services from Github Actions.

## 🚀 Features

- Run public and private tests for Microsoft 365 security configurations.
- Supports **Exchange Online** and **Teams** tests.
- Customizable test runs with include/exclude tags.
- Detailed test results with optional email and Teams notifications.
- Uploads test results as GitHub Action artifacts.
- Supports telemetry control for privacy-conscious workflows.

## 📦 Inputs

| Name                          | Description                                                                                    | Required | Default                     |
|-------------------------------|------------------------------------------------------------------------------------------------|----------|-----------------------------|
| `tenant_id`                   | Entra ID Tenant ID.                                                                            | ✅       |                             |
| `client_id`                   | App Registration Client ID.                                                                    | ✅       |                             |
| `include_public_tests`        | Maester 2 only. Install public tests from module. Empty means `true`. No effect on Maester 3 (use `skip_builtin_tests`). | ❌       | (empty, `true`)             |
| `include_private_tests`       | Include private tests from the current repository.                                             | ❌       | `true`                      |
| `include_exchange`            | Include Exchange Online tests in the test run.                                                 | ❌       | `false`                     |
| `include_teams`               | Include Teams tests in the test run.                                                           | ❌       | `true`                      |
| `include_longrunning_tests`   | Include long running tests.                                                                    | ❌       | `false`                     |
| `include_preview_tests`       | Include preview tests.                                                                         | ❌       | `false`                     |
| `include_affected_objects`    | Collect affected objects (Affected objects page and `-affected-objects.json`).                 | ❌       | `false`                     |
| `include_tags`                | A list of tags to include in the test run (comma-separated).                                   | ❌       |                             |
| `exclude_tags`                | A list of tags to exclude from the test run (comma-separated).                                 | ❌       |                             |
| `maester_version`             | The version of Maester PowerShell to use (`latest`, `preview`, or specific version). `latest` and `preview` resolve to the newest release within `maester_major_version`. | ❌       | `latest`                    |
| `maester_major_version`       | The Maester major version to run: `2` or `3`. Set to `3` to opt in to Maester 3.0, see [Upgrading to Maester 3.0](#upgrading-to-maester-30). An exact `maester_version` must belong to this major version. | ❌       | `2`                         |
| `skip_builtin_tests`          | Maester 3 only. Run only the custom tests in the repository (`Invoke-Maester -SkipBuiltIn`).    | ❌       | `false`                     |
| `install_pester`              | Maester 3 only. Always install Pester 5.7.1 or later. By default it is installed only when the repository contains `*.Tests.ps1` files. | ❌       | `false`                     |
| `test_ids`                    | Maester 3 only. Test IDs to run, comma-separated, `*` wildcards allowed (`-TestId`).            | ❌       |                             |
| `exclude_test_ids`            | Maester 3 only. Test IDs to exclude, comma-separated, `*` wildcards allowed (`-ExcludeTestId`). | ❌       |                             |
| `config_path`                 | Maester 3 only. Path to a `maester-config.json` run configuration, relative to the repository root (`-Config`). | ❌       |                             |
| `pester_verbosity`            | Pester verbosity level (`None`, `Normal`, `Detailed`, `Diagnostic`).                           | ❌       | `None`                      |
| `step_summary`                | Level of detail in the GitHub Actions step summary: `Full` (complete report), `Summary` (counts + per-test pass/fail list), `Table` (counts only), or `false` to disable. Legacy `true` maps to `Full`. | ❌       | `Table`                      |
| `artifact_upload`             | Upload test results as GitHub Action artifacts.                                                | ❌       | `true`                      |
| `artifact_upload_html`        | Upload the self-contained HTML report as a separate artifact and add a link to it in the step summary (served with an HTML mime type so it renders in the browser). | ❌       | `false`                     |
| `disable_telemetry`           | Disable telemetry logging.                                                                     | ❌       | `false`                     |
| `mail_recipients`             | A list of email addresses to send the test results to (comma-separated).                       | ❌       |                             |
| `mail_userid`                 | The user ID of the sender of the email.                                                        | ❌       |                             |
| `mail_testresultsuri`         | URI to the detailed test results page.                                                         | ❌       | `${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}` |
| `notification_teams_webhook`  | Webhook URL for sending test results to Teams.                                                 | ❌       |                             |
| `notification_teams_channel_id` | The ID of the Teams channel to send the test results to.                                     | ❌       |                             |
| `notification_teams_team_id`  | The ID of the Teams team to send the test results to.                                          | ❌       |                             |

## 📤 Outputs

| Name             | Description                                      |
|------------------|--------------------------------------------------|
| `results_json`   | The file location of the JSON output of the test results. |
| `tests_total`    | The total number of tests                        |
| `tests_passed`   | Number of passed tests                           |
| `tests_failed`   | Number of failed tests                           |
| `tests_skipped`  | Number of skipped tests                          |
| `result`         | Result of all the tests `Failed` or `Passed`     |
| `maester_version`| The exact Maester version that was installed and run |

> [!NOTE]
> To use the outputs in your workflow, you need to set the `id` for the step that runs the action. The outputs can be accessed using `${{ steps.<step_id>.outputs.<output_name> }}`.

## 🛠️ Usage

Here’s an example of how to use the **Maester Action** in your workflow file `.github/workflows/maester.yml`:

```yaml
name: Run Maester Tests

on:
  push:
    branches:
      - main

  schedule:
    # Daily at 7:30 UTC, change accordingly
    - cron: "30 7 * * *"

  # Allows to run this workflow manually from the Actions tab
  workflow_dispatch:

permissions:
      id-token: write
      contents: read
      checks: write

jobs:
  test:
    name: Run Maester Test Job
    runs-on: ubuntu-latest

    steps:
      - name: Run Maester 🔥
        id: maester
        # Set the action version to a specific version, to keep using that exact version.
        # Or even better set it to a specific commit SHA to be sure nothing breaks unexpectedly.
        uses: maester365/maester-action@main
        with:
          tenant_id: ${{ secrets.AZURE_TENANT_ID }}
          client_id: ${{ secrets.AZURE_CLIENT_ID }}
          include_public_tests: true
          include_private_tests: false
          include_exchange: false
          include_teams: false
          # Set a specific version of the powershell module here or 'latest' or 'preview'
          # check out https://www.powershellgallery.com/packages/Maester/
          maester_version: latest
          disable_telemetry: false
          step_summary: Table  # Full, Summary, Table, or false
          artifact_upload_html: true # Upload html report as separate artifact

      - name: Write status 📃
        shell: bash
        run: |
          echo "The result of the test run is: ${{ steps.maester.outputs.result }}"
          echo "Total tests: ${{ steps.maester.outputs.tests_total }}"
          echo "Passed tests: ${{ steps.maester.outputs.tests_passed }}"
          echo "Failed tests: ${{ steps.maester.outputs.tests_failed }}"
          echo "Skipped tests: ${{ steps.maester.outputs.tests_skipped }}"
```

## Upgrading to Maester 3.0

Maester 3.0 runs the built-in tests from inside the module and no longer depends on Pester. This action keeps
running **Maester 2.x** until you opt in: `maester_version: latest` and `preview` resolve to the newest 2.x release
while `maester_major_version` is `2` (the default), even after 3.0 is published. Nothing changes until you set
`maester_major_version: "3"`.

Before:

```yaml
      - name: Run Maester 🔥
        uses: maester365/maester-action@main
        with:
          tenant_id: ${{ secrets.AZURE_TENANT_ID }}
          client_id: ${{ secrets.AZURE_CLIENT_ID }}
          include_public_tests: true
          maester_version: latest
```

After:

```yaml
      - name: Run Maester 🔥
        uses: maester365/maester-action@main
        with:
          tenant_id: ${{ secrets.AZURE_TENANT_ID }}
          client_id: ${{ secrets.AZURE_CLIENT_ID }}
          maester_major_version: "3"  # opt in to Maester 3.x
          maester_version: latest     # newest 3.x release (or 'preview', or an exact 3.x version)
```

What changes on Maester 3:

- **The built-in tests always run.** The action no longer installs the public tests (`maester365/maester-tests`)
  into the workspace, so `include_public_tests` has no effect (you get a warning if you set it). Your repository
  holds only your custom tests and `maester-config.json`. Set `skip_builtin_tests: true` to run only your custom
  tests, or use `include_tags`, `test_ids` and `exclude_test_ids` to pick tests.
- **Custom Pester tests need Pester.** Pester-format custom tests (`*.Tests.ps1`) need Pester 5.7.1 or later. The
  action installs it automatically when it finds `*.Tests.ps1` files in the repository; set `install_pester: true`
  to always install it.
- **The `All` and `Full` tags were removed.** The action stops with an error if `include_tags` or `exclude_tags`
  contain them. Use `include_preview_tests` instead of `All` and `include_longrunning_tests` instead of `Full`.
- **PowerShell 7.4 or later** is required. GitHub-hosted runners already have it; check self-hosted runners.
- **New inputs:** `skip_builtin_tests`, `install_pester`, `test_ids`, `exclude_test_ids` and `config_path`. They
  only work on Maester 3; the action fails if you set them while `maester_major_version` is `2`.
- An exact `maester_version` must match `maester_major_version`: `maester_version: 3.0.0` with
  `maester_major_version: "2"` fails with an error instead of guessing.

Read [Upgrading from Maester 2.x](https://maester.dev/docs/upgrading-from-2x) before you switch, and try the
upgrade on a branch or with `workflow_dispatch` first.

## Contributing

We welcome contributions, since this is a community project! Please check out our [contributing guidelines](https://maester.dev/docs/contributing/) for more information on how to get started.

Thanks for using Maester! If you have any questions or feedback, feel free to reach out to us on [GitHub Discussions](https://github.com/maester365/maester/discussions) or [Discord](https://discord.maester.dev/).
