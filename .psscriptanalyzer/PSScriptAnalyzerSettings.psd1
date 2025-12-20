@{
    # PSScriptAnalyzer Settings
    # =============================================================================
    # Configuration for PowerShell code quality analysis
    # Matches the strictness level used for shell scripts (ShellCheck --severity=warning)

    # Include all default rules
    IncludeDefaultRules = $true

    # Severity levels to check (Error, Warning, Information)
    Severity = @('Error', 'Warning', 'Information')

    # Exclude specific rules if needed
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'  # We use Write-Host for colored console output in interactive tools
    )

    # Custom rule configurations
    Rules = @{
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $false
        }

        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator = $true
            CheckParameter = $false
        }

        PSAlignAssignmentStatement = @{
            Enable = $true
            CheckHashtable = $true
        }

        PSUseCorrectCasing = @{
            Enable = $true
        }

        PSAvoidUsingCmdletAliases = @{
            Enable = $true
            # Allow common aliases that improve readability
            Allowlist = @()
        }

        PSProvideCommentHelp = @{
            Enable = $true
            ExportedOnly = $false
            BlockComment = $true
            VSCodeSnippetCorrection = $true
            Placement = 'begin'
        }
    }
}

