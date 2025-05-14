# Contributing to Maester action

This document describes how to contribute to the Maester action. It is intended for developers who want to add new features, fix bugs, or improve the action in any way.

## Important notice

This action is mostly used by IT professionals that want to run Maester in GitHub Actions, do not bother them with complex warnings or errors. Instead, use simple and clear **actionable** messages. For example, if the user provided a wrong combination of inputs, log an error message and exit with a non-zero code. Do not use `Write-Host` to log errors or warnings, use `Write-Error` instead. Or use the [workflow commands](https://svrooij.io/2025/05/14/github-workflow-commands-powershell/) to log errors or warnings.

## Backward compatibility

When making changes to the action, please make sure to maintain backward compatibility with previous versions. This means that any changes you make should not break existing workflows that use the action. If you need to make breaking changes, please consider creating a new version of the action and updating the documentation accordingly.

Changing inputs or outputs of the action is considered a breaking action, if you were to remove them or add required inputs without a default value. To ensure smooth upgrades between versions, make sure that you provided default values for required inputs, not everybody is using a pinned version of the action. If you are not sure about the impact of your changes, please discuss first in the [issue tracker](https://github.com/maester365/maester-action/issues).

## Prerequisites

Before contributing to this action, make sure you familiarize yourself with the [Maester documentation](https://maester.dev/docs/) and the [codebase](https://github.com/maester365/maester).

### Action structure

This action is a composite action that runs Maester, it executes all the steps needed to authenticate, get the custom tests, and then call the `script/Run-MaesterAction.ps1` PowerShell script, with all the needed inputs from the workflow.

1. Log error is the wrong combination of inputs is provided.
1. Checkout the custom tests from the repository.
1. Call `azure/login@v2` to authenticate with Azure using Azure CLI.
1. Run the `script/Run-MaesterAction.ps1` PowerShell script with all the inputs provided in the workflow.
1. Artifact upload the results if the `artifact-upload` input is set to true.

## Making changes

1. Fork the repository and clone it to your local machine.
1. Create a new branch for your changes.
1. Make your changes to the codebase.
1. Push the changes to your forked repository.
1. Change your maester action to test your new action.
1. Create a pull request to the main repository with a description of your changes and why they are needed.
1. Wait for the pull request to be reviewed and merged.

> [!NOTE]
> If you are not sure about the impact of your changes, please discuss first in the [issue tracker](https://github.com/maester365/maester-action/issues). We are happy to help you with your changes.

## Pull requests

When creating a pull request, please make sure to follow these guidelines:

- Provide a clear and concise description of the changes you made.
- Include any relevant issue numbers in the pull request description.
- Enable the checkbox to [allow maintainer edits](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/allowing-changes-to-a-pull-request-branch-created-from-a-fork) so the branch can be updated for a merge.
- Make sure you use enough emojis in the `Write-Host` cmdlets, we love emojis! 😍 Also provide them in your commit messages.

## Merging pull requests

For those with write access to the repository, please follow these guidelines when merging pull requests:

- Review the pull request thoroughly and test the changes if possible.
- Make sure the pull request follows the guidelines mentioned above.
- **DO** use ["Squash and Merge"](https://github.com/blog/2141-squash-your-commits) by default for individual contributions unless requested by the PR author. Do so, even if the PR contains only one commit. It creates a simpler history than "Create a Merge Commit".
