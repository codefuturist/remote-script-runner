# RSR.Docker.psm1 - RSR Docker PowerShell Module
#Requires -Version 5.1

function Test-RSRDockerInstalled {
    [CmdletBinding()]
    param()
    $null -ne (Get-Command 'docker' -ErrorAction SilentlyContinue)
}

function Test-RSRDockerRunning {
    [CmdletBinding()]
    param()
    if (-not (Test-RSRDockerInstalled)) { return $false }
    try { $null = docker info 2>&1; $LASTEXITCODE -eq 0 } catch { $false }
}

function Assert-RSRDocker {
    [CmdletBinding()]
    param()
    if (-not (Test-RSRDockerInstalled)) { throw "Docker is not installed" }
    if (-not (Test-RSRDockerRunning)) { throw "Docker is not running" }
}

function Get-RSRDockerVersion {
    [CmdletBinding()]
    param()
    if (-not (Test-RSRDockerInstalled)) { return 'not_installed' }
    (docker --version) -replace 'Docker version ([^,]+).*', '$1'
}

function Get-RSRDockerContainers {
    [CmdletBinding()]
    param([switch]$All)
    Assert-RSRDocker
    $args = @('ps', '--format', '{{json .}}')
    if ($All) { $args += '-a' }
    docker @args | ForEach-Object { $_ | ConvertFrom-Json }
}

function Test-RSRDockerContainerExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Assert-RSRDocker
    $Name -in (docker ps -a --format '{{.Names}}')
}

function Test-RSRDockerContainerRunning {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Assert-RSRDocker
    $Name -in (docker ps --format '{{.Names}}')
}

function Start-RSRDockerContainer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Assert-RSRDocker
    docker start $Name
}

function Stop-RSRDockerContainer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [int]$Timeout = 10)
    Assert-RSRDocker
    docker stop -t $Timeout $Name
}

function Restart-RSRDockerContainer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Assert-RSRDocker
    docker restart $Name
}

function Remove-RSRDockerContainer {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name, [switch]$Force)
    Assert-RSRDocker
    if ($PSCmdlet.ShouldProcess($Name, 'Remove')) {
        $a = @('rm'); if ($Force) { $a += '-f' }; $a += $Name
        docker @a
    }
}

function Get-RSRDockerContainerLogs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [int]$Tail, [switch]$Follow)
    Assert-RSRDocker
    $a = @('logs'); if ($Tail) { $a += '--tail'; $a += $Tail }; if ($Follow) { $a += '-f' }; $a += $Name
    docker @a
}

function Invoke-RSRDockerExec {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Command, [switch]$Interactive)
    Assert-RSRDocker
    $a = @('exec'); if ($Interactive) { $a += '-it' }; $a += $Name; $a += $Command.Split(' ')
    docker @a
}

function Get-RSRDockerImages {
    [CmdletBinding()]
    param()
    Assert-RSRDocker
    docker images --format '{{json .}}' | ForEach-Object { $_ | ConvertFrom-Json }
}

function Get-RSRDockerImage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Image)
    Assert-RSRDocker
    docker pull $Image
}

function Remove-RSRDockerImage {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Image, [switch]$Force)
    Assert-RSRDocker
    if ($PSCmdlet.ShouldProcess($Image, 'Remove')) {
        $a = @('rmi'); if ($Force) { $a += '-f' }; $a += $Image
        docker @a
    }
}

function Get-RSRDockerVolumes {
    [CmdletBinding()]
    param()
    Assert-RSRDocker
    docker volume ls --format '{{json .}}' | ForEach-Object { $_ | ConvertFrom-Json }
}

function New-RSRDockerVolume {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Assert-RSRDocker
    docker volume create $Name
}

function Remove-RSRDockerVolume {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name, [switch]$Force)
    Assert-RSRDocker
    if ($PSCmdlet.ShouldProcess($Name, 'Remove')) {
        $a = @('volume', 'rm'); if ($Force) { $a += '-f' }; $a += $Name
        docker @a
    }
}

function Get-RSRDockerNetworks {
    [CmdletBinding()]
    param()
    Assert-RSRDocker
    docker network ls --format '{{json .}}' | ForEach-Object { $_ | ConvertFrom-Json }
}

function New-RSRDockerNetwork {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [string]$Driver = 'bridge')
    Assert-RSRDocker
    docker network create -d $Driver $Name
}

function Remove-RSRDockerNetwork {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Name)
    Assert-RSRDocker
    if ($PSCmdlet.ShouldProcess($Name, 'Remove')) { docker network rm $Name }
}

function Invoke-RSRDockerSystemPrune {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$All, [switch]$Volumes)
    Assert-RSRDocker
    if ($PSCmdlet.ShouldProcess('Docker', 'Prune')) {
        $a = @('system', 'prune', '-f'); if ($All) { $a += '-a' }; if ($Volumes) { $a += '--volumes' }
        docker @a
    }
}

Export-ModuleMember -Function @(
    'Test-RSRDockerInstalled', 'Test-RSRDockerRunning', 'Assert-RSRDocker', 'Get-RSRDockerVersion',
    'Get-RSRDockerContainers', 'Test-RSRDockerContainerExists', 'Test-RSRDockerContainerRunning',
    'Start-RSRDockerContainer', 'Stop-RSRDockerContainer', 'Restart-RSRDockerContainer',
    'Remove-RSRDockerContainer', 'Get-RSRDockerContainerLogs', 'Invoke-RSRDockerExec',
    'Get-RSRDockerImages', 'Get-RSRDockerImage', 'Remove-RSRDockerImage',
    'Get-RSRDockerVolumes', 'New-RSRDockerVolume', 'Remove-RSRDockerVolume',
    'Get-RSRDockerNetworks', 'New-RSRDockerNetwork', 'Remove-RSRDockerNetwork',
    'Invoke-RSRDockerSystemPrune'
)
