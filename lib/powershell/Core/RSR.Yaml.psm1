# RSR.Yaml.psm1 - RSR YAML Parsing Module
# Provides: Native YAML parsing for package profiles
#
# Usage: Import-Module RSR (loads via manifest)

#Requires -Version 5.1

# =============================================================================
# YAML Parsing Functions (Native, no external dependencies)
# =============================================================================

function ConvertFrom-RSRYaml {
    <#
    .SYNOPSIS
        Parse simple YAML content (native implementation)
    .DESCRIPTION
        Parses basic YAML structures needed for package profiles.
        Supports: simple lists, key-value pairs, nested groups
    .PARAMETER Content
        YAML content as string
    .PARAMETER Path
        Path to YAML file
    .EXAMPLE
        $yaml = ConvertFrom-RSRYaml -Path "profile.yaml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [string]$Content,
        
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path
    )
    
    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path $Path)) {
            throw "YAML file not found: $Path"
        }
        $Content = Get-Content $Path -Raw
    }
    
    $result = @{}
    $lines = $Content -split "`n"
    $currentSection = $null
    $currentIndent = 0
    
    foreach ($line in $lines) {
        # Skip empty lines and comments
        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            continue
        }
        
        # Measure indentation
        $indent = ($line -replace '^(\s*).', '$1').Length
        
        # Remove leading/trailing whitespace
        $trimmed = $line.Trim()
        
        # Key-value pair
        if ($trimmed -match '^([a-zA-Z_][\w-]*):(.*)$') {
            $key = $matches[1]
            $value = $matches[2].Trim()
            
            # Remove quotes
            $value = $value -replace '^[''"]|[''"]$', ''
            
            if ($value) {
                $result[$key] = $value
            } else {
                $result[$key] = @{}
                $currentSection = $key
                $currentIndent = $indent
            }
        }
    }
    
    return $result
}

function Get-RSRYamlSection {
    <#
    .SYNOPSIS
        Extract a specific section from YAML file
    .PARAMETER Path
        Path to YAML file
    .PARAMETER Section
        Section name (e.g., 'packages', 'groups')
    .EXAMPLE
        $packages = Get-RSRYamlSection -Path "core.yaml" -Section "packages"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Section
    )
    
    if (-not (Test-Path $Path)) {
        throw "YAML file not found: $Path"
    }
    
    $lines = Get-Content $Path
    $inSection = $false
    $sectionIndent = 0
    $items = @()
    
    foreach ($line in $lines) {
        # Skip empty lines
        if ($line -match '^\s*$') {
            continue
        }
        
        # Measure indentation
        $indent = ($line -replace '^(\s*).', '$1').Length
        $trimmed = $line.Trim()
        
        # Check for section header
        if ($trimmed -match "^$Section\s*:") {
            $inSection = $true
            $sectionIndent = $indent
            continue
        }
        
        # Exit section when we hit a new top-level key
        if ($inSection -and $indent -le $sectionIndent -and $trimmed -match '^[a-zA-Z_][\w-]*:') {
            break
        }
        
        # Extract items from section
        if ($inSection -and $trimmed -match '^-\s+(.+)$') {
            $item = $matches[1].Trim()
            # Remove comments
            $item = $item -replace '\s*#.*$', ''
            # Remove quotes
            $item = $item -replace '^[''"]|[''"]$', ''
            if ($item) {
                $items += $item
            }
        }
    }
    
    return $items
}

function Get-RSRYamlGroups {
    <#
    .SYNOPSIS
        List all groups in a YAML profile
    .PARAMETER Path
        Path to YAML file
    .PARAMETER ParentGroup
        Optional parent group path (e.g., 'languages')
    .EXAMPLE
        $groups = Get-RSRYamlGroups -Path "development.yaml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string]$ParentGroup
    )
    
    if (-not (Test-Path $Path)) {
        throw "YAML file not found: $Path"
    }
    
    $lines = Get-Content $Path
    $inGroups = $false
    $groupsIndent = 0
    $groups = @()
    
    foreach ($line in $lines) {
        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            continue
        }
        
        $indent = ($line -replace '^(\s*).', '$1').Length
        $trimmed = $line.Trim()
        
        # Find groups section
        if ($trimmed -match '^groups\s*:') {
            $inGroups = $true
            $groupsIndent = $indent
            continue
        }
        
        # Exit groups section
        if ($inGroups -and $indent -le $groupsIndent -and $trimmed -match '^[a-zA-Z_][\w-]*:') {
            break
        }
        
        # Extract group names (2-space indentation after 'groups:')
        if ($inGroups -and $indent -eq ($groupsIndent + 2) -and $trimmed -match '^([a-zA-Z_][\w-]*):') {
            $groupName = $matches[1]
            
            # Get description if available
            $description = $null
            $nextLineIdx = $lines.IndexOf($line) + 1
            if ($nextLineIdx -lt $lines.Count) {
                $nextLine = $lines[$nextLineIdx].Trim()
                if ($nextLine -match '^description:\s*(.+)$') {
                    $description = $matches[1] -replace '^[''"]|[''"]$', ''
                }
            }
            
            $groups += [PSCustomObject]@{
                Name = $groupName
                Description = $description
            }
        }
    }
    
    return $groups
}

function Get-RSRYamlGroupPackages {
    <#
    .SYNOPSIS
        Get packages from a specific group in YAML profile
    .PARAMETER Path
        Path to YAML file
    .PARAMETER GroupPath
        Group path with dot notation (e.g., 'languages.python')
    .EXAMPLE
        $packages = Get-RSRYamlGroupPackages -Path "development.yaml" -GroupPath "languages.python"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$GroupPath
    )
    
    if (-not (Test-Path $Path)) {
        throw "YAML file not found: $Path"
    }
    
    # Split group path
    $pathParts = $GroupPath -split '\.'
    $lines = Get-Content $Path
    
    # Navigate to the group
    $currentIndent = 0
    $targetIndent = 2  # Start after 'groups:'
    $foundGroups = $false
    $foundTarget = $false
    $inPackages = $false
    $packages = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            continue
        }
        
        $indent = ($line -replace '^(\s*).', '$1').Length
        $trimmed = $line.Trim()
        
        # Find groups section
        if (-not $foundGroups -and $trimmed -match '^groups\s*:') {
            $foundGroups = $true
            continue
        }
        
        if (-not $foundGroups) {
            continue
        }
        
        # Navigate through path parts
        if (-not $foundTarget) {
            foreach ($part in $pathParts) {
                if ($trimmed -match "^$part\s*:" -and $indent -eq $targetIndent) {
                    $targetIndent += 2
                    $foundTarget = ($pathParts[-1] -eq $part)
                    break
                }
            }
            continue
        }
        
        # Look for packages section in target group
        if ($foundTarget -and -not $inPackages) {
            if ($trimmed -match '^packages\s*:') {
                $inPackages = $true
                continue
            }
        }
        
        # Extract packages
        if ($inPackages) {
            # Exit if we hit a new key at same or lower indent
            if ($indent -le $targetIndent -and $trimmed -match '^[a-zA-Z_][\w-]*:') {
                break
            }
            
            # Extract package (simple format)
            if ($trimmed -match '^-\s+([a-zA-Z0-9_-]+)\s*$') {
                $packages += $matches[1]
            }
            # Extended format with name:
            elseif ($trimmed -match '^-\s+name:\s*(.+)$') {
                $packages += $matches[1] -replace '^[''"]|[''"]$', ''
            }
        }
    }
    
    return $packages
}

# Export functions
Export-ModuleMember -Function @(
    'ConvertFrom-RSRYaml',
    'Get-RSRYamlSection',
    'Get-RSRYamlGroups',
    'Get-RSRYamlGroupPackages'
)
