# RSR.SSH.psm1 - RSR SSH PowerShell Module
#Requires -Version 5.1

function Get-RSRPlatformInternal {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($IsWindows) { return 'Windows' }
        if ($IsLinux) { return 'Linux' }
        if ($IsMacOS) { return 'macOS' }
    }
    return 'Windows'
}

function Test-RSRSSHServerInstalled {
    [CmdletBinding()]
    param()
    switch (Get-RSRPlatformInternal) {
        'Windows' {
            $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue
            $null -ne $cap -and $cap.State -eq 'Installed'
        }
        default { $null -ne (Get-Command 'sshd' -ErrorAction SilentlyContinue) }
    }
}

function Test-RSRSSHServerRunning {
    [CmdletBinding()]
    param()
    switch (Get-RSRPlatformInternal) {
        'Windows' {
            $svc = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
            $null -ne $svc -and $svc.Status -eq 'Running'
        }
        default { $false }
    }
}

function Test-RSRSSHServerEnabled {
    [CmdletBinding()]
    param()
    switch (Get-RSRPlatformInternal) {
        'Windows' {
            $svc = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
            $null -ne $svc -and $svc.StartType -eq 'Automatic'
        }
        default { $false }
    }
}

function Get-RSRSSHServerStatus {
    [CmdletBinding()]
    param()
    [PSCustomObject]@{
        Installed = Test-RSRSSHServerInstalled
        Running = Test-RSRSSHServerRunning
        Enabled = Test-RSRSSHServerEnabled
        Platform = Get-RSRPlatformInternal
    }
}

function Start-RSRSSHServer {
    [CmdletBinding()]
    param()
    if (Get-RSRPlatformInternal -eq 'Windows') { Start-Service sshd }
}

function Stop-RSRSSHServer {
    [CmdletBinding()]
    param()
    if (Get-RSRPlatformInternal -eq 'Windows') { Stop-Service sshd }
}

function Restart-RSRSSHServer {
    [CmdletBinding()]
    param()
    if (Get-RSRPlatformInternal -eq 'Windows') { Restart-Service sshd }
}

function Enable-RSRSSHServer {
    [CmdletBinding()]
    param()
    if (Get-RSRPlatformInternal -eq 'Windows') { Set-Service -Name sshd -StartupType Automatic }
}

function Disable-RSRSSHServer {
    [CmdletBinding()]
    param()
    if (Get-RSRPlatformInternal -eq 'Windows') { Set-Service -Name sshd -StartupType Manual }
}

function New-RSRSSHKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Email,
        [string]$Path = "$env:USERPROFILE\.ssh\id_ed25519",
        [ValidateSet('ed25519','rsa')][string]$Type = 'ed25519',
        [string]$Passphrase = ''
    )
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ssh-keygen -t $Type -C $Email -f $Path -N $Passphrase
}

function Get-RSRSSHPublicKey {
    [CmdletBinding()]
    param([string]$Path)
    $paths = @($Path, "$env:USERPROFILE\.ssh\id_ed25519.pub", "$env:USERPROFILE\.ssh\id_rsa.pub") | Where-Object { $_ }
    foreach ($p in $paths) { if (Test-Path $p) { return Get-Content $p -Raw } }
    throw "No SSH public key found"
}

function Add-RSRSSHAuthorizedKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PublicKey, [string]$User = $env:USERNAME)
    $dir = if ($User -eq $env:USERNAME) { "$env:USERPROFILE\.ssh" } else { "C:\Users\$User\.ssh" }
    $auth = Join-Path $dir 'authorized_keys'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ((Test-Path $auth) -and (Get-Content $auth -Raw).Contains($PublicKey.Trim())) {
        Write-Warning "Key exists"; return
    }
    Add-Content -Path $auth -Value $PublicKey.Trim()
}

function Remove-RSRSSHAuthorizedKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Pattern, [string]$User = $env:USERNAME)
    $dir = if ($User -eq $env:USERNAME) { "$env:USERPROFILE\.ssh" } else { "C:\Users\$User\.ssh" }
    $auth = Join-Path $dir 'authorized_keys'
    if (-not (Test-Path $auth)) { return }
    Copy-Item $auth "${auth}.bak"
    Get-Content $auth | Where-Object { $_ -notmatch $Pattern } | Set-Content $auth
}

function Get-RSRSSHAuthorizedKeys {
    [CmdletBinding()]
    param([string]$User = $env:USERNAME)
    $dir = if ($User -eq $env:USERNAME) { "$env:USERPROFILE\.ssh" } else { "C:\Users\$User\.ssh" }
    $auth = Join-Path $dir 'authorized_keys'
    if (-not (Test-Path $auth)) { return @() }
    Get-Content $auth | Where-Object { $_.Trim() } | ForEach-Object {
        $p = $_ -split '\s+'
        [PSCustomObject]@{ Type=$p[0]; Key=if($p[1].Length -gt 50){"$($p[1].Substring(0,50))..."}else{$p[1]}; Comment=if($p.Count -gt 2){$p[2..($p.Count-1)] -join ' '}else{''} }
    }
}

Export-ModuleMember -Function @(
    'Test-RSRSSHServerInstalled', 'Test-RSRSSHServerRunning', 'Test-RSRSSHServerEnabled', 'Get-RSRSSHServerStatus',
    'Start-RSRSSHServer', 'Stop-RSRSSHServer', 'Restart-RSRSSHServer', 'Enable-RSRSSHServer', 'Disable-RSRSSHServer',
    'New-RSRSSHKey', 'Get-RSRSSHPublicKey', 'Add-RSRSSHAuthorizedKey', 'Remove-RSRSSHAuthorizedKey', 'Get-RSRSSHAuthorizedKeys'
)
