# House Planner dual-repository Docker installer, Windows PowerShell 5.1+
# Source selection is strictly limited to the two reviewed GitHub repositories.
[CmdletBinding()]
param(
    [ValidateSet('Gui','Worker','Launch')][string]$Action = 'Gui',
    [ValidateSet('Install','Repair','Uninstall')][string]$Mode = 'Install',
    [ValidateSet('Original','Fork')][string]$Source = 'Original',
    [string]$Root = '',
    [ValidateRange(1024,65535)][int]$Port = 8080,
    [switch]$UpdateLatest,
    [string]$Session = ''
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$script:Identity = 'org.houseplanner.dualsource.docker.v1'
$script:Base = Join-Path $env:LOCALAPPDATA 'HousePlannerInstaller'
$script:LogPath = ''
$script:CancelPath = ''
$script:Repos = @{Original='egmalt/house-planner'; Fork='AonzOG/house-planner-10-10-2026-Fork-egmalt'}
$script:OwnedNames = @('house-planner.compose.yml','.env','house-planner.install.json','house-planner.source-files.json','Start House Planner.bat','Manage House Planner.bat','HousePlanner-Wizard.ps1')
$null = New-Item -ItemType Directory -Force -Path $script:Base

function Write-HpLog([string]$Message) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message)
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 }
    else { Write-Host $line }
}
function Assert-Root([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Choose an installation directory.' }
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))).TrimEnd('\','/')
    $drive = [IO.Path]::GetPathRoot($full).TrimEnd('\','/')
    if ($full.Length -le 3 -or $full -ieq $drive) { throw 'A drive root is not a safe installation directory.' }
    foreach ($bad in @($env:SystemRoot,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData,$env:USERPROFILE,$env:LOCALAPPDATA,$env:TEMP)) {
        if ($bad -and $full -ieq $bad.TrimEnd('\','/')) { throw 'This folder is reserved. Choose an application-specific folder.' }
    }
    if ($full -match '(?i)^[a-z]:\\windows(\\|$)' -or $full -match '(?i)^[a-z]:\\program files( \(x86\))?(\\|$)') { throw 'Do not install inside Windows or Program Files without a managed elevated installer.' }
    if ($full -match '(?i)(^|\\)\.\.(\\|$)') { throw 'Parent traversal is not allowed.' }
    $walk = $full
    while ($walk -and $walk.Length -gt 3) {
        if (Test-Path -LiteralPath $walk) {
            if ((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Install path contains a filesystem link/junction. Choose a regular directory.' }
        }
        $walk = [IO.Path]::GetDirectoryName($walk)
    }
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Install folder must be a regular directory, not a file or junction.' }
    }
    return $full
}
function Get-Manifest([string]$Path) {
    $mf = Join-Path $Path 'house-planner.install.json'
    if (-not (Test-Path -LiteralPath $mf -PathType Leaf)) { throw "No managed House Planner installation marker at: $Path" }
    $m = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json
    if ($m.identity -cne $script:Identity -or $m.project -notmatch '^hp[a-f0-9]{12}$' -or $m.source -notin @('Original','Fork') -or
        $m.sha -notmatch '^[a-f0-9]{40}$' -or [int]$m.port -lt 1024 -or [int]$m.port -gt 65535) {
        throw 'Installation manifest has an invalid or unexpected identity.'
    }
    return $m
}
function Get-ProjectId([string]$Path) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return 'hp' + $h.Substring(0,12)
}
function Get-DockerExe {
    $cmd = Get-Command docker.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $path = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe'
    if (Test-Path -LiteralPath $path) { return $path }
    throw 'Docker Desktop/Engine is not installed. Install Docker Desktop and select Linux containers, then retry.'
}
function Quote-Arg([string]$Arg) {
    # All passed values are controlled arguments or absolute Windows paths (no double quotes allowed in Win32 paths).
    if ($Arg.Contains('"')) { throw 'Unsupported double quote in command argument.' }
    return '"' + $Arg.TrimEnd() + '"'
}
function Invoke-Program([string]$Exe,[string[]]$CommandArguments,[int]$TimeoutSeconds = 1800,[switch]$NonFatal) {
    # Do not name this parameter $Args: PowerShell reserves $args as an automatic variable.
    # A collision silently discards the command tokens, executing bare docker.exe.
    if (-not $CommandArguments -or $CommandArguments.Count -eq 0) {
        throw "Refusing to start $Exe without command arguments (installer command-assembly failure)."
    }
    $display = (($CommandArguments | ForEach-Object { Quote-Arg $_ }) -join ' ')
    Write-HpLog ("Running {0} {1}" -f ([IO.Path]::GetFileName($Exe)), $display)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $display
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    if (-not $p.Start()) { throw "Failed to start $Exe" }
    try {
        $stdoutTask = $p.StandardOutput.ReadToEndAsync()
        $stderrTask = $p.StandardError.ReadToEndAsync()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.WaitForExit(300)) {
            if ($script:CancelPath -and (Test-Path -LiteralPath $script:CancelPath)) {
                try { $p.Kill() } catch { }
                throw 'Operation cancelled. Docker may need a moment to finish its current build; use Repair if necessary.'
            }
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                try { $p.Kill() } catch { }
                throw "Command timed out after $TimeoutSeconds seconds."
            }
        }
        $out = $stdoutTask.GetAwaiter().GetResult()
        $err = $stderrTask.GetAwaiter().GetResult()
        if ($out) { Write-HpLog ($out.TrimEnd()) }
        if ($err) { Write-HpLog ($err.TrimEnd()) }
        if ($p.ExitCode -ne 0 -and -not $NonFatal) { throw "Command failed (exit $($p.ExitCode)): $Exe" }
        return @{ exitCode=$p.ExitCode; output=$out; error=$err }
    }
    finally { $p.Dispose() }
}
function Get-ComposeArguments([string]$Path,[string]$Project,[string[]]$Command) {
    # Explicit project directory and environment file avoid Docker Compose picking up a different .env from the calling directory.
    return @('compose','-p',$Project,'--project-directory',$Path,'--env-file',(Join-Path $Path '.env'),'-f',(Join-Path $Path 'house-planner.compose.yml')) + $Command
}
function Check-Docker {
    $docker = Get-DockerExe
    $null = Invoke-Program $docker @('compose','version') 30
    $info = Invoke-Program $docker @('info','--format','{{.OSType}}') 40
    if ($info.output.Trim().ToLowerInvariant() -ne 'linux') { throw 'Docker Linux engine is not ready. Start Docker Desktop and switch to Linux containers.' }
    return $docker
}
function Test-PortFree([int]$Number) {
    # Docker publishes only 127.0.0.1; probe that same IPv4 interface, never alter the owning service.
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$Number)
    try {
        $listener.Start()
        return $true
    } catch [Net.Sockets.SocketException] {
        return $false
    } finally {
        try { $listener.Stop() } catch { }
    }
}
function Find-AvailablePort([int]$Preferred) {
    # Search a bounded range beginning immediately after the requested port, wrapping at 65535.
    $rangeSize = 65535 - 1024 + 1
    for ($offset=1; $offset -le 128; $offset++) {
        $candidate = 1024 + (($Preferred - 1024 + $offset) % $rangeSize)
        if (Test-PortFree $candidate) { return [int]$candidate }
    }
    return 0
}
function Assert-PortFree([int]$Number) {
    if (-not (Test-PortFree $Number)) {
        $alternative = Find-AvailablePort $Number
        if ($alternative -gt 0) {
            throw "Port $Number is occupied on 127.0.0.1. Open the wizard again and select suggested port $alternative. The existing service will not be changed."
        }
        throw "Port $Number is occupied on 127.0.0.1 and no free port was found nearby. Choose another local port."
    }
}
function Get-SourceSha([string]$Repo) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $api = 'https://api.github.com/repos/{0}/commits/main' -f $Repo
    $info = Invoke-RestMethod -Uri $api -Headers @{'User-Agent'='HousePlanner-DualSource-Installer'} -TimeoutSec 60
    if ([string]$info.sha -notmatch '^[a-f0-9]{40}$') { throw 'GitHub did not return a valid commit SHA.' }
    return [string]$info.sha
}
function Get-SourceArchive([string]$Repo,[string]$Commit,[string]$WorkDir) {
    if ($Repo -notin @($script:Repos.Values) -or $Commit -notmatch '^[a-f0-9]{40}$') { throw 'Invalid source repository or commit.' }
    $zip = Join-Path $WorkDir 'source.zip'
    $url = 'https://codeload.github.com/{0}/zip/{1}' -f $Repo,$Commit
    Write-HpLog "Downloading selected repository commit $Commit via HTTPS: $Repo"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip -TimeoutSec 480 -Headers @{'User-Agent'='HousePlanner-DualSource-Installer'}
    Write-HpLog ('Downloaded archive SHA-256: ' + (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant())
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stage = Join-Path $WorkDir 'extracted'
    $null = New-Item -ItemType Directory -Force -Path $stage
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        if ($archive.Entries.Count -gt 6000) { throw 'Unexpectedly large number of ZIP entries.' }
        $total = [int64]0
        $prefix = $stage.TrimEnd('\') + '\'
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('/','\')
            if (-not $name -or $name.StartsWith('\') -or $name.Contains(':') -or $name.Contains('|') -or $name.Contains([char]10) -or $name.Contains([char]13) -or $name -match '(?i)^[a-z]:' -or $name -match '(^|\\)\.\.(\\|$)' -or $name -match '(^|\\)\.(\\|$)') { throw 'Unsafe path in source ZIP.' }
            $mode = (($entry.ExternalAttributes -shr 16) -band 61440)
            if ($mode -eq 40960) { throw 'Symlinks are not accepted in downloaded source archives.' }
            $total += $entry.Length
            if ($total -gt 536870912) { throw 'Source archive exceeds 512 MB extracted size limit.' }
            $target = [IO.Path]::GetFullPath((Join-Path $stage $name))
            if (-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'ZIP path attempted to escape staging directory.' }
            if ($entry.Name -eq '') { $null = New-Item -ItemType Directory -Force -Path $target; continue }
            $null = New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target))
            $dest = [IO.File]::Open($target,[IO.FileMode]::CreateNew)
            try { $stream = $entry.Open(); try { $stream.CopyTo($dest) } finally { $stream.Dispose() } }
            finally { $dest.Dispose() }
        }
    }
    finally { $archive.Dispose() }
    $folders = @(Get-ChildItem -LiteralPath $stage -Directory -Force)
    if ($folders.Count -ne 1) { throw 'Expected exactly one repository directory in GitHub ZIP.' }
    $source = $folders[0].FullName
    foreach ($required in @('Dockerfile','docker-compose.yml','package.json','package-lock.json','public\api\setup.php','docker\entrypoint.sh')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $required) -PathType Leaf)) { throw "Downloaded source is missing $required" }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $source 'package.json') -Raw | ConvertFrom-Json
    if ($manifest.name -cne 'house-planner') { throw 'Unexpected project name inside downloaded archive.' }
    return $source
}
function Create-Compose([string]$Path,[string]$Project,[int]$HostPort) {
    $template = @'
# Generated exclusively for this House Planner installation.
# Bind only to IPv4 loopback. Use an HTTPS reverse proxy for remote access.
services:
  house-planner:
    build:
      context: ./source
      dockerfile: Dockerfile
    image: "house-planner-installer-@@PROJECT@@:local"
    ports:
      - "127.0.0.1:@@PORT@@:8080"
    environment:
      HOUSE_SETUP_KEY: ${HOUSE_SETUP_KEY}
      HOUSE_PASSWORD: ""
      HOUSE_DEMO: ""
    volumes:
      - house-data:/var/lib/house-planner
    restart: unless-stopped
volumes:
  house-data:
'@
    $content = $template.Replace('@@PROJECT@@',$Project).Replace('@@PORT@@',[string]$HostPort)
    [IO.File]::WriteAllText((Join-Path $Path 'house-planner.compose.yml'),$content,(New-Object Text.UTF8Encoding($false)))
}
function Create-Env([string]$Path) {
    $envPath = Join-Path $Path '.env'
    if (Test-Path -LiteralPath $envPath) { if ((Get-Item -LiteralPath $envPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Setup-key environment file is a link; refusing to use it.' }; return }
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $key = [BitConverter]::ToString($bytes).Replace('-','').ToLowerInvariant()
    [IO.File]::WriteAllText($envPath,"HOUSE_SETUP_KEY=$key`r`n",(New-Object Text.UTF8Encoding($false)))
    # Restrict the generated one-time setup key to the installing user where possible.
    try {
        $acl = Get-Acl -LiteralPath $envPath
        $acl.SetAccessRuleProtection($true,$false)
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($user,'FullControl','Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $envPath -AclObject $acl
    } catch { Write-HpLog "Warning: could not restrict setup-key file ACL: $($_.Exception.Message)" }
}
function Save-Manifest([string]$Path,[string]$Src,[string]$Repo,[string]$Commit,[string]$Project,[int]$HostPort,[string]$State) {
    $record = [ordered]@{identity=$script:Identity; source=$Src; repository=$Repo; sha=$Commit; project=$Project; port=$HostPort; state=$State; dataVolume=($Project + '_house-data'); updatedUtc=[DateTime]::UtcNow.ToString('o')}
    $json = ConvertTo-Json $record -Depth 5
    [IO.File]::WriteAllText((Join-Path $Path 'house-planner.install.json'),$json,(New-Object Text.UTF8Encoding($false)))
}
function Save-SourceMap([string]$Path) {
    $src = Join-Path $Path 'source'
    $items = @()
    foreach ($file in (Get-ChildItem -LiteralPath $src -File -Recurse -Force)) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Installer source contains an unexpected filesystem link.' }
        $rel = $file.FullName.Substring($src.Length + 1).Replace('\','/')
        $items += @{path=$rel; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $obj = @{ identity=$script:Identity; files=$items }
    [IO.File]::WriteAllText((Join-Path $Path 'house-planner.source-files.json'),(ConvertTo-Json $obj -Depth 6),(New-Object Text.UTF8Encoding($false)))
}
function Get-SourceChanges([string]$Path) {
    $mapPath = Join-Path $Path 'house-planner.source-files.json'
    $src = Join-Path $Path 'source'
    if (-not (Test-Path -LiteralPath $mapPath) -or -not (Test-Path -LiteralPath $src)) { return $true }
    if (@(Get-ChildItem -LiteralPath $src -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) { return $true }
    $record = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json
    if ($record.identity -cne $script:Identity) { return $true }
    $expected = @{}
    foreach ($entry in $record.files) { $expected[[string]$entry.path] = [string]$entry.sha256 }
    $seen = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $src -File -Recurse -Force)) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $true }
        $rel = $file.FullName.Substring($src.Length + 1).Replace('\','/')
        if (-not $expected.ContainsKey($rel)) { return $true }
        if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected[$rel]) { return $true }
        $seen[$rel] = $true
    }
    return $seen.Count -ne $expected.Count
}
function Remove-TrackedSource([string]$Path) {
    $record = Get-Content -LiteralPath (Join-Path $Path 'house-planner.source-files.json') -Raw | ConvertFrom-Json
    if ($record.identity -cne $script:Identity) { throw 'Refusing source removal: ownership list identity mismatch.' }
    $src = Join-Path $Path 'source'
    if (-not (Test-Path -LiteralPath $src)) { return }
    if ((Get-Item -LiteralPath $src).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source folder is a junction/symlink; refusing recursive operation.' }
    if (@(Get-ChildItem -LiteralPath $src -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) { Write-HpLog 'Source contains linked files/directories. Preserving complete source folder for safety.'; return }
    foreach ($entry in $record.files) {
        $rel = [string]$entry.path
        if ($rel -match '(^|/)\.\.(/|$)' -or $rel.StartsWith('/') -or $rel.Contains('\') -or $rel.Contains(':')) { throw 'Unsafe file path in ownership record.' }
        $file = Join-Path $src ($rel.Replace('/','\'))
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Write-HpLog "Preserving linked file: $rel"; continue }
            if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ceq [string]$entry.sha256) { Remove-Item -LiteralPath $file -Force }
            else { Write-HpLog "Preserving user-modified source file: $rel" }
        }
    }
    $dirs = @(Get-ChildItem -LiteralPath $src -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending)
    foreach ($dir in $dirs) {
        if (-not ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            try { Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop } catch { }
        }
    }
    try { Remove-Item -LiteralPath $src -Force -ErrorAction Stop } catch { Write-HpLog 'Untracked or edited source files have been preserved in the source folder.' }
}
function Copy-WizardFiles([string]$Path) {
    $target = Join-Path $Path 'HousePlanner-Wizard.ps1'
    if ($PSCommandPath -ine $target) { Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force }
    $manage = @'
@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0HousePlanner-Wizard.ps1" -Action Gui -Root "%~dp0"
if errorlevel 1 pause
'@
    $launch = @'
@echo off
setlocal DisableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0HousePlanner-Wizard.ps1" -Action Launch -Root "%~dp0"
if errorlevel 1 pause
'@
    [IO.File]::WriteAllText((Join-Path $Path 'Manage House Planner.bat'),$manage.Replace("`n","`r`n"),[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $Path 'Start House Planner.bat'),$launch.Replace("`n","`r`n"),[Text.Encoding]::ASCII)
}
function Assert-InstallEmpty([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        if (Test-Path -LiteralPath (Join-Path $Path 'house-planner.install.json')) { throw 'This location already has a managed House Planner installation. Choose Repair instead.' }
        $items = @(Get-ChildItem -LiteralPath $Path -Force)
        if ($items.Count -gt 0) { throw 'Selected folder is not empty and has no installer manifest. Choose an empty folder.' }
    }
}
function Write-InitialState([string]$Path,[string]$Src,[string]$Repo,[string]$Commit,[string]$Project,[int]$HostPort) {
    Create-Compose $Path $Project $HostPort
    Create-Env $Path
    Copy-WizardFiles $Path
    Save-SourceMap $Path
    Save-Manifest $Path $Src $Repo $Commit $Project $HostPort 'pending'
}
function Invoke-HealthCheck([int]$HostPort) {
    $url = "http://127.0.0.1:$HostPort/api/setup.php"
    for ($i=0; $i -lt 25; $i++) {
        if ($script:CancelPath -and (Test-Path -LiteralPath $script:CancelPath)) { throw 'Cancelled during health check.' }
        try {
            $req = [Net.HttpWebRequest]::Create($url)
            $req.Timeout = 4000; $req.ReadWriteTimeout = 4000
            $resp = $req.GetResponse()
            try { $code = [int]$resp.StatusCode } finally { $resp.Close() }
            if ($code -eq 200) { Write-HpLog 'HTTP application setup endpoint responded successfully.'; return }
        } catch [Net.WebException] {
            $webResponse = $_.Exception.Response
            if ($webResponse -and [int]$webResponse.StatusCode -eq 403) { $webResponse.Close(); Write-HpLog 'Existing configured application responded (setup endpoint locked).'; return }
        }
        Start-Sleep -Seconds 2
    }
    throw "Container was started, but HTTP health validation did not succeed at $url. Use Repair and inspect Docker logs."
}
function Invoke-Worker {
    if (-not $Session -or -not [IO.Path]::IsPathRooted($Session)) { throw 'Worker needs an absolute session log path.' }
    $script:LogPath = $Session
    $script:CancelPath = "$Session.cancel"
    $rootPath = Assert-Root $Root
    Write-HpLog "House Planner installer 1.0.2; mode=$Mode; path=$rootPath"
    $docker = Check-Docker
    Write-HpLog 'Docker Linux engine and Compose are available.'
    if ($Mode -eq 'Uninstall') {
        $installed = Get-Manifest $rootPath
        $compose = Join-Path $rootPath 'house-planner.compose.yml'
        if (-not (Test-Path -LiteralPath $compose)) { throw 'Missing owned Compose file; refusing incomplete uninstall. Repair first.' }
        if ((Get-Item -LiteralPath $compose -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Compose configuration is a link; refusing uninstall.' }
        $null = Invoke-Program $docker (Get-ComposeArguments $rootPath ([string]$installed.project) @('down')) 180
        $null = Invoke-Program $docker @('image','rm',('house-planner-installer-{0}:local' -f $installed.project)) 60 -NonFatal
        Remove-TrackedSource $rootPath
        foreach ($name in @('house-planner.compose.yml','.env','house-planner.source-files.json')) {
            $path = Join-Path $rootPath $name
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
        }
        $mf = Join-Path $rootPath 'house-planner.install.json'
        Remove-Item -LiteralPath $mf -Force
        # Deferred cleanup avoids deleting the manager while it is executing. Never recursively delete the root.
        $marker = Join-Path $rootPath '.hp-uninstall-ready'
        [IO.File]::WriteAllText($marker,$script:Identity)
        $cleanupPath = Join-Path $script:Base ('cleanup-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $cleanupCode = @'
param([string]$Target,[string]$Identity)
Start-Sleep -Seconds 8
try {
  $marker = Join-Path $Target '.hp-uninstall-ready'
  if (-not (Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw) -cne $Identity) { exit 1 }
  foreach ($file in @('Start House Planner.bat','Manage House Planner.bat','HousePlanner-Wizard.ps1','.hp-uninstall-ready')) {
    $p = Join-Path $Target $file
    if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
  }
  try { Remove-Item -LiteralPath $Target -Force -ErrorAction Stop } catch { }
} finally { Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue }
'@
        [IO.File]::WriteAllText($cleanupPath,$cleanupCode,(New-Object Text.UTF8Encoding($false)))
        $exe = Join-Path $PSHOME 'powershell.exe'
        $argString = (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$cleanupPath,'-Target',$rootPath,'-Identity',$script:Identity) | ForEach-Object { Quote-Arg $_ }) -join ' '
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $exe; $psi.Arguments = $argString; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $cleanupProc = [Diagnostics.Process]::Start($psi)
        if ($cleanupProc) { $cleanupProc.Dispose() }
        Write-HpLog "Uninstalled application and containers. User plans remain in Docker volume $($installed.dataVolume)."
        Write-HpLog 'Any modified/untracked source files and other non-installer files were preserved.'
        return
    }
    $repo = $script:Repos[$Source]
    $existing = $null
    if ($Mode -eq 'Install') { Assert-InstallEmpty $rootPath; Assert-PortFree $Port; $project = Get-ProjectId $rootPath }
    else {
        $existing = Get-Manifest $rootPath
        $project = [string]$existing.project
        if ([int]$existing.port -ne $Port) { Assert-PortFree $Port }
    }
    $sha = if ($Mode -eq 'Repair' -and $existing -and $existing.source -eq $Source -and -not $UpdateLatest) { [string]$existing.sha } else { Get-SourceSha $repo }
    Write-HpLog "Selected source: $repo at commit $sha"
    $work = Join-Path $env:TEMP ('HousePlanner-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $work -Force
    $old = ''
    $priorCompose = ''
    $preserveBackup = $false
    $imageTag = ('house-planner-installer-{0}:local' -f $project)
    $imageBackup = ''
    try {
        $newSource = Get-SourceArchive $repo $sha $work
        if ($Mode -eq 'Install') {
            $null = New-Item -ItemType Directory -Path $rootPath -Force
            Move-Item -LiteralPath $newSource -Destination (Join-Path $rootPath 'source')
            Write-InitialState $rootPath $Source $repo $sha $project $Port
        } else {
            $preserveBackup = Get-SourceChanges $rootPath
            $old = Join-Path $rootPath ('source-previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
            $current = Join-Path $rootPath 'source'
            if (-not (Test-Path -LiteralPath $current -PathType Container)) { throw 'Current source folder is missing. Repair requires the managed source folder to exist.' }
            if ((Get-Item -LiteralPath $current).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source directory is a link; aborting repair.' }
            $composeFile = Join-Path $rootPath 'house-planner.compose.yml'
            if ((Get-Item -LiteralPath $composeFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Compose file is a link; refusing repair.' }
            $priorCompose = Get-Content -LiteralPath $composeFile -Raw
            Create-Env $rootPath
            $imageCheck = Invoke-Program $docker @('image','inspect','--format','{{.Id}}',$imageTag) 30 -NonFatal
            if ($imageCheck.exitCode -eq 0) {
                $imageBackup = ('house-planner-installer-{0}:previous-{1}' -f $project,[guid]::NewGuid().ToString('N').Substring(0,12))
                $null = Invoke-Program $docker @('tag',$imageTag,$imageBackup) 40
                Write-HpLog "Saved previous container image for rollback: $imageBackup"
            }
            Move-Item -LiteralPath $current -Destination $old
            Move-Item -LiteralPath $newSource -Destination $current
            Create-Compose $rootPath $project $Port
            Create-Env $rootPath
        }
        $compose = Join-Path $rootPath 'house-planner.compose.yml'
        $null = Invoke-Program $docker (Get-ComposeArguments $rootPath $project @('config','--quiet')) 40
        $null = Invoke-Program $docker (Get-ComposeArguments $rootPath $project @('up','-d','--build')) 1800
        Invoke-HealthCheck $Port
        Copy-WizardFiles $rootPath
        Save-SourceMap $rootPath
        Save-Manifest $rootPath $Source $repo $sha $project $Port 'installed'
        if ($old -and (Test-Path -LiteralPath $old)) {
            if ($preserveBackup) { Write-HpLog "Preserved user-modified pre-repair source files at: $old" }
            else { Remove-Item -LiteralPath $old -Recurse -Force }
        }
        if ($imageBackup) { $null = Invoke-Program $docker @('image','rm',$imageBackup) 40 -NonFatal }
        Write-HpLog "SUCCESS: http://127.0.0.1:$Port/ -- first use: /api/setup.php"
        Write-HpLog "Data volume $($project)_house-data is managed by Docker and survives Repair and Uninstall."
    } catch {
        if ($Mode -eq 'Repair' -and $old -and (Test-Path -LiteralPath $old)) {
            Write-HpLog 'Repair failed; restoring the prior source and Compose definition.'
            try {
                $badSource = Join-Path $rootPath 'source'
                if (Test-Path -LiteralPath $badSource) { Remove-Item -LiteralPath $badSource -Recurse -Force }
                Move-Item -LiteralPath $old -Destination $badSource
                [IO.File]::WriteAllText((Join-Path $rootPath 'house-planner.compose.yml'),$priorCompose,(New-Object Text.UTF8Encoding($false)))
                Write-HpLog 'Original application source restored. Existing Docker volume was not touched.'
                if ($imageBackup) {
                    # Cancellation does not block rollback; it only cancelled the requested update.
                    $priorCancelPath = $script:CancelPath
                    $script:CancelPath = ''
                    try {
                        $null = Invoke-Program $docker @('tag',$imageBackup,$imageTag) 40
                        $null = Invoke-Program $docker (Get-ComposeArguments $rootPath $project @('up','-d','--no-build')) 180 -NonFatal
                        $null = Invoke-Program $docker @('image','rm',$imageBackup) 40 -NonFatal
                        Write-HpLog 'Previous Docker image was retagged and its container restart was attempted.'
                    } finally { $script:CancelPath = $priorCancelPath }
                }
            } catch { Write-HpLog "Rollback failed: $($_.Exception.Message). Existing data volume is still retained." }
        }
        throw
    } finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
function Start-HousePlanner([string]$Path) {
    $rootPath = Assert-Root $Path
    $m = Get-Manifest $rootPath
    $script:LogPath = Join-Path $script:Base ('start-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    $docker = Check-Docker
    $compose = Join-Path $rootPath 'house-planner.compose.yml'
    if (-not (Test-Path -LiteralPath $compose)) { throw 'Missing Compose file. Run Repair.' }
    if ((Get-Item -LiteralPath $compose -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Compose file is a link. Run Repair.' }
    $null = Invoke-Program $docker (Get-ComposeArguments $rootPath ([string]$m.project) @('up','-d','--no-build')) 180
    Invoke-HealthCheck ([int]$m.port)
    $url = 'http://127.0.0.1:{0}/' -f $m.port
    Write-HpLog "Opening $url"
    Start-Process $url
}

if ($Action -eq 'Worker') {
    try { Invoke-Worker; exit 0 }
    catch { Write-HpLog ('ERROR: ' + $_.Exception.Message); Write-HpLog ($_ | Out-String); exit 1 }
}
if ($Action -eq 'Launch') {
    try { Start-HousePlanner $Root; exit 0 }
    catch { Write-Host ('House Planner failed: ' + $_.Exception.Message); Write-Host ("Logs: $script:LogPath"); exit 1 }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object Windows.Forms.Form
$form.Text = 'House Planner - Dual-Repository Installer'
$form.ClientSize = New-Object Drawing.Size(780,610)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI',10)
function Ui-Label([string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H) {
    $l = New-Object Windows.Forms.Label; $l.Text=$Text; $l.Location=New-Object Drawing.Point($X,$Y); $l.Size=New-Object Drawing.Size($W,$H); return $l
}
function Ui-Button([string]$Text,[int]$X,[int]$Y,[int]$W) {
    $b=New-Object Windows.Forms.Button; $b.Text=$Text; $b.Location=New-Object Drawing.Point($X,$Y); $b.Size=New-Object Drawing.Size($W,32); return $b
}
$header = Ui-Label 'HOUSE PLANNER  /  INSTALLER' 28 19 700 35
$header.Font = New-Object Drawing.Font('Segoe UI Semibold',16)
$form.Controls.Add($header)
$subtitle = Ui-Label 'Install, repair or uninstall the selected GitHub version on your local Docker engine.' 28 58 718 36
$form.Controls.Add($subtitle)
$panels = @()
for ($i=0;$i -lt 6;$i++) {
    $panel=New-Object Windows.Forms.Panel; $panel.Location=New-Object Drawing.Point(27,105);$panel.Size=New-Object Drawing.Size(726,410);$panel.Visible=$false
    $panels+= $panel; $form.Controls.Add($panel)
}
$modeTitle = Ui-Label 'What would you like to do?' 8 5 690 30; $modeTitle.Font = New-Object Drawing.Font('Segoe UI Semibold',13);$panels[0].Controls.Add($modeTitle)
$installRadio=New-Object Windows.Forms.RadioButton;$installRadio.Text='Install House Planner';$installRadio.Location=New-Object Drawing.Point(16,60);$installRadio.Size=New-Object Drawing.Size(600,34);$installRadio.Checked=$true;$panels[0].Controls.Add($installRadio)
$repairRadio=New-Object Windows.Forms.RadioButton;$repairRadio.Text='Repair, update or switch repository (preserves projects)';$repairRadio.Location=New-Object Drawing.Point(16,105);$repairRadio.Size=New-Object Drawing.Size(660,34);$panels[0].Controls.Add($repairRadio)
$uninstallRadio=New-Object Windows.Forms.RadioButton;$uninstallRadio.Text='Uninstall application (preserve Docker project-data volume)';$uninstallRadio.Location=New-Object Drawing.Point(16,150);$uninstallRadio.Size=New-Object Drawing.Size(690,34);$panels[0].Controls.Add($uninstallRadio)
$panels[0].Controls.Add((Ui-Label 'This installer uses the repository-supported Docker Compose production build. Docker Desktop with Linux containers must already be installed and running. No system dependencies are modified automatically.' 16 230 670 90))
$panels[1].Controls.Add((Ui-Label 'Choose the exact GitHub source to install' 8 5 690 34))
$originalRadio=New-Object Windows.Forms.RadioButton;$originalRadio.Text='Original  -  egmalt/house-planner';$originalRadio.Location=New-Object Drawing.Point(16,68);$originalRadio.Size=New-Object Drawing.Size(650,35);$originalRadio.Checked=$true;$panels[1].Controls.Add($originalRadio)
$forkRadio=New-Object Windows.Forms.RadioButton;$forkRadio.Text='Back up Fork  -  AonzOG/house-planner-10-10-2026-Fork-egmalt';$forkRadio.Location=New-Object Drawing.Point(16,118);$forkRadio.Size=New-Object Drawing.Size(700,35);$panels[1].Controls.Add($forkRadio)
$panels[1].Controls.Add((Ui-Label 'The source is downloaded from the selected repository at a resolved Git commit. The installed source and commit are recorded in the manifest. Repair normally retains the installed commit.' 16 197 675 95))
$panels[2].Controls.Add((Ui-Label 'Installation directory' 8 5 680 30))
$pathBox=New-Object Windows.Forms.TextBox;$pathBox.Location=New-Object Drawing.Point(16,47);$pathBox.Size=New-Object Drawing.Size(564,29);$pathBox.Text=if($Root){$Root}else{'C:\house-planner'};$panels[2].Controls.Add($pathBox)
$browse=Ui-Button 'Browse...' 594 45 110;$panels[2].Controls.Add($browse)
$panels[2].Controls.Add((Ui-Label 'Local web port (1024-65535)' 16 115 520 28))
$portBox=New-Object Windows.Forms.NumericUpDown;$portBox.Location=New-Object Drawing.Point(16,152);$portBox.Size=New-Object Drawing.Size(130,28);$portBox.Minimum=1024;$portBox.Maximum=65535;$portBox.Value=8080;$panels[2].Controls.Add($portBox)
$portHint=Ui-Label 'If this port is in use, the wizard offers an available port without stopping other services.' 166 145 525 54;$panels[2].Controls.Add($portHint)
$updateCheck=New-Object Windows.Forms.CheckBox;$updateCheck.Text='Repair using the latest commit instead of the installed commit';$updateCheck.Location=New-Object Drawing.Point(16,206);$updateCheck.Size=New-Object Drawing.Size(675,36);$panels[2].Controls.Add($updateCheck)
$panels[2].Controls.Add((Ui-Label 'Setup access is restricted to localhost. Your project plans, snapshots, password hash and configuration live in a named Docker volume, not inside the downloaded source folder.' 16 283 675 85))
$panels[3].Controls.Add((Ui-Label 'Docker requirements' 8 5 680 34))
$requirementsText=New-Object Windows.Forms.TextBox;$requirementsText.Multiline=$true;$requirementsText.ReadOnly=$true;$requirementsText.ScrollBars='Vertical';$requirementsText.Location=New-Object Drawing.Point(16,55);$requirementsText.Size=New-Object Drawing.Size(680,204)
$requirementsText.Text="Required: Docker Desktop/Engine running Linux containers with Docker Compose v2.`r`n`r`nThe installer builds Node.js 22 and PHP 8.3 Apache inside Docker images. Neither Node.js nor PHP is installed into Windows.`r`n`r`nFirst launch: the built-in House Planner setup page asks for the shown setup key and a password. The server listens only on 127.0.0.1.";$panels[3].Controls.Add($requirementsText)
$dockerWeb=Ui-Button 'Docker Desktop website' 16 283 210;$panels[3].Controls.Add($dockerWeb)
$panels[3].Controls.Add((Ui-Label 'The installer verifies Docker availability before modifying application files.' 16 340 685 45))
$panels[4].Controls.Add((Ui-Label 'Installing / Repairing / Uninstalling' 8 5 680 32))
$progressText=New-Object Windows.Forms.TextBox;$progressText.Multiline=$true;$progressText.ReadOnly=$true;$progressText.ScrollBars='Both';$progressText.WordWrap=$false;$progressText.Location=New-Object Drawing.Point(16,55);$progressText.Size=New-Object Drawing.Size(680,286);$progressText.Font=New-Object Drawing.Font('Consolas',9);$panels[4].Controls.Add($progressText)
$progressLabel=Ui-Label 'Preparing...' 16 350 680 45;$panels[4].Controls.Add($progressLabel)
$finishLabel=Ui-Label 'Operation finished' 8 5 680 40;$finishLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',13);$panels[5].Controls.Add($finishLabel)
$finishInfo=New-Object Windows.Forms.TextBox;$finishInfo.Multiline=$true;$finishInfo.ReadOnly=$true;$finishInfo.ScrollBars='Vertical';$finishInfo.Location=New-Object Drawing.Point(16,58);$finishInfo.Size=New-Object Drawing.Size(680,172);$panels[5].Controls.Add($finishInfo)
$setupKey=New-Object Windows.Forms.TextBox;$setupKey.Location=New-Object Drawing.Point(16,262);$setupKey.Size=New-Object Drawing.Size(510,28);$setupKey.ReadOnly=$true;$panels[5].Controls.Add($setupKey)
$copyKey=Ui-Button 'Copy setup key' 539 259 157;$panels[5].Controls.Add($copyKey)
$runButton=Ui-Button 'Open House Planner setup' 16 319 245;$panels[5].Controls.Add($runButton)
$openLog=Ui-Button 'Open diagnostic log' 279 319 210;$panels[5].Controls.Add($openLog)
$back=Ui-Button '< Back' 28 542 126;$form.Controls.Add($back)
$next=Ui-Button 'Next >' 505 542 115;$form.Controls.Add($next)
$cancel=Ui-Button 'Cancel / Close' 635 542 120;$form.Controls.Add($cancel)
$copyLog=Ui-Button 'Copy log' 165 542 115;$form.Controls.Add($copyLog)
$copyLog.Enabled=$false
$script:CurrentPage=0
$script:WorkerProc=$null
$script:SessionLog=''
$script:SelectedMode='Install'
$script:Cancelled=$false
$script:ResultSuccess=$false
$script:LastPort=8080
$script:LastRoot=''
$script:SetupAlreadyConfigured=$false
function Set-Page([int]$Index) {
    $script:CurrentPage=$Index
    for($j=0;$j -lt $panels.Count;$j++){ $panels[$j].Visible=($j -eq $Index) }
    $back.Enabled=($Index -gt 0 -and $Index -lt 4)
    $next.Enabled=($Index -lt 4)
    $next.Text=if($Index -eq 3){'Begin'}else{'Next >'}
    $cancel.Text=if($Index -eq 4){'Cancel operation'}elseif($Index -eq 5){'Close'}else{'Cancel'}
}
function Prefill-Existing {
    try {
        $at=Assert-Root $pathBox.Text
        if (Test-Path -LiteralPath (Join-Path $at 'house-planner.install.json')) {
            $old=Get-Manifest $at
            $portBox.Value=[int]$old.port
            return
        }
    } catch { }
}
function Confirm-GuiPort {
    if ($script:SelectedMode -eq 'Uninstall') { return $true }
    $requested=[int]$portBox.Value
    if ($script:SelectedMode -eq 'Repair') {
        $saved=Get-Manifest (Assert-Root $pathBox.Text)
        # This port may already be bound by House Planner itself. Never require it to be free.
        if ([int]$saved.port -eq $requested) { return $true }
    }
    if (Test-PortFree $requested) { return $true }
    $alternative=Find-AvailablePort $requested
    if ($alternative -eq 0) {
        [Windows.Forms.MessageBox]::Show("Port $requested is occupied, and no free port was found nearby. Enter a different port.",'House Planner - Port occupied','OK','Warning') | Out-Null
        return $false
    }
    $message="Port $requested is already being used on localhost by another service.`r`n`r`nUse available port $alternative instead?`r`n`r`nThe installer will not stop or modify the other service."
    $answer=[Windows.Forms.MessageBox]::Show($message,'House Planner - Port occupied','YesNo','Question')
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return $false }
    $portBox.Value=[decimal]$alternative
    $portHint.Text="Port $requested was occupied. Using port $alternative for this installation."
    return $true
}
$browse.Add_Click({
    $dlg=New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description='Choose the folder containing (or to contain) House Planner'
    if(Test-Path -LiteralPath $pathBox.Text -PathType Container){$dlg.SelectedPath=$pathBox.Text}
    if($dlg.ShowDialog() -eq 'OK'){$pathBox.Text=$dlg.SelectedPath}
})
$dockerWeb.Add_Click({ Start-Process 'https://docs.docker.com/desktop/setup/install/windows-install/' })
$copyKey.Add_Click({if($setupKey.Text){[Windows.Forms.Clipboard]::SetText($setupKey.Text)}})
$runButton.Add_Click({if($script:SetupAlreadyConfigured){Start-Process ('http://127.0.0.1:{0}/' -f $script:LastPort)}else{Start-Process ('http://127.0.0.1:{0}/api/setup.php' -f $script:LastPort)}})
$openLog.Add_Click({ if($script:SessionLog -and (Test-Path -LiteralPath $script:SessionLog)){Start-Process notepad.exe -ArgumentList ('"'+$script:SessionLog+'"')} })
$copyLog.Add_Click({if($progressText.Text){[Windows.Forms.Clipboard]::SetText($progressText.Text)}})
$back.Add_Click({
    if($script:CurrentPage -eq 2 -and $uninstallRadio.Checked){Set-Page 0}
    elseif($script:CurrentPage -eq 3){Set-Page 2}
    else{Set-Page ($script:CurrentPage-1)}
})
$cancel.Add_Click({
    if($script:WorkerProc -and -not $script:WorkerProc.HasExited){
        if(-not $script:Cancelled){[IO.File]::WriteAllText(($script:SessionLog+'.cancel'),'cancel');$script:Cancelled=$true;$progressLabel.Text='Cancellation requested; stopping after the current Docker operation...'}
    }else{$form.Close()}
})
function Start-WorkerGui {
    $script:SelectedMode=if($installRadio.Checked){'Install'}elseif($repairRadio.Checked){'Repair'}else{'Uninstall'}
    $script:LastRoot=Assert-Root $pathBox.Text
    $script:LastPort=[int]$portBox.Value
    $src=if($forkRadio.Checked){'Fork'}else{'Original'}
    $logs=Join-Path $script:Base 'logs'
    $null=New-Item -ItemType Directory -Force -Path $logs
    $script:SessionLog=Join-Path $logs (('setup-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),[guid]::NewGuid().ToString('N').Substring(0,8)))
    [IO.File]::WriteAllText($script:SessionLog,'')
    $workerArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Action','Worker','-Mode',$script:SelectedMode,'-Source',$src,'-Root',$script:LastRoot,'-Port',([string]$script:LastPort),'-Session',$script:SessionLog)
    if($updateCheck.Checked){$workerArguments+= '-UpdateLatest'}
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=(Join-Path $PSHOME 'powershell.exe')
    $psi.Arguments=(($workerArguments | ForEach-Object { Quote-Arg $_ }) -join ' ')
    $psi.CreateNoWindow=$true;$psi.UseShellExecute=$false
    $script:WorkerProc=[Diagnostics.Process]::Start($psi)
    $script:Cancelled=$false
    $progressText.Text='';$copyLog.Enabled=$true
    $progressLabel.Text=('Running {0}. Log: {1}' -f $script:SelectedMode,$script:SessionLog)
    Set-Page 4
    $timer.Start()
}
$timer=New-Object Windows.Forms.Timer
$timer.Interval=600
$timer.Add_Tick({
    if($script:SessionLog -and (Test-Path -LiteralPath $script:SessionLog)) {
        try {
            $file = New-Object IO.FileStream($script:SessionLog,([IO.FileMode]::Open),([IO.FileAccess]::Read),([IO.FileShare]::ReadWrite))
            try {$reader=New-Object IO.StreamReader($file);$s=$reader.ReadToEnd()}finally{$reader.Dispose()}
            if($s.Length -gt 60000){$s=$s.Substring($s.Length-60000)}
            if($s -cne $progressText.Text){$progressText.Text=$s;$progressText.SelectionStart=$progressText.Text.Length;$progressText.ScrollToCaret()}
        }catch{}
    }
    if($script:WorkerProc -and $script:WorkerProc.HasExited){
        $timer.Stop()
        $code=$script:WorkerProc.ExitCode
        $script:WorkerProc.Dispose();$script:WorkerProc=$null
        $script:ResultSuccess=($code -eq 0)
        $setupKey.Text=''
        $copyKey.Visible=$false
        $runButton.Visible=$false
        if($code -eq 0){
            $finishLabel.Text="$script:SelectedMode completed"
            if($script:SelectedMode -eq 'Uninstall'){
                $finishInfo.Text="Application containers and installer-owned files removed.`r`n`r`nSaved house plans, versions and snapshots were PRESERVED in Docker's named volume. They were not deleted. Untracked or user-modified local files are also preserved.`r`n`r`nSee the log for the volume name and any retained local files."
            }else{
                try{
                    $m=Get-Manifest $script:LastRoot
                    $script:LastPort=[int]$m.port
                    $script:SetupAlreadyConfigured = $progressText.Text.Contains('Existing configured application responded')
                    if($script:SetupAlreadyConfigured){
                        $finishInfo.Text="Repository: $($m.repository)`r`nCommit: $($m.sha)`r`nInstalled to: $script:LastRoot`r`nURL: http://127.0.0.1:$script:LastPort/`r`n`r`nAn existing configured Docker data volume was reused. Your old projects and password were preserved. Click Open House Planner and sign in with the previous password."
                        $runButton.Text='Open House Planner'
                    }else{
                        $finishInfo.Text="Repository: $($m.repository)`r`nCommit: $($m.sha)`r`nInstalled to: $script:LastRoot`r`nURL: http://127.0.0.1:$script:LastPort/`r`n`r`nFirst use: click Open House Planner setup. Enter the setup key and choose a password (8 or more characters)."
                        $runButton.Text='Open House Planner setup'
                    }
                    $envFile=Join-Path $script:LastRoot '.env'
                    $match=Select-String -LiteralPath $envFile -Pattern '^HOUSE_SETUP_KEY=([0-9a-f]{64})$'
                    if($match){$setupKey.Text=$match.Matches[0].Groups[1].Value}
                    $copyKey.Visible=(-not $script:SetupAlreadyConfigured);$setupKey.Visible=(-not $script:SetupAlreadyConfigured);$runButton.Visible=$true
                }catch{$finishInfo.Text="Operation succeeded. Read installer log for details: $script:SessionLog"}
            }
        }else{
            $finishLabel.Text='Operation failed or was cancelled'
            $finishInfo.Text="The operation did not complete successfully (exit code $code).`r`n`r`nSee and copy the diagnostic log:`r`n$script:SessionLog`r`n`r`nRepair keeps the Docker data volume and attempts to restore the previous source on a failed repair."
        }
        Set-Page 5
    }
})
$next.Add_Click({
    try {
        if($script:CurrentPage -eq 0){
            $script:SelectedMode=if($installRadio.Checked){'Install'}elseif($repairRadio.Checked){'Repair'}else{'Uninstall'}
            if($script:SelectedMode -eq 'Uninstall'){Set-Page 2}else{Set-Page 1}
        }elseif($script:CurrentPage -eq 1){Set-Page 2; if($script:SelectedMode -eq 'Repair'){Prefill-Existing}}
        elseif($script:CurrentPage -eq 2){
            $p=Assert-Root $pathBox.Text
            if($script:SelectedMode -eq 'Install'){Assert-InstallEmpty $p}else{$null=Get-Manifest $p}
            if($script:SelectedMode -eq 'Uninstall'){$updateCheck.Checked=$false}
            if (-not (Confirm-GuiPort)) { return }
            Set-Page 3
        }elseif($script:CurrentPage -eq 3){
            # Recheck on Begin in case another process claimed the port since the prior page.
            if (-not (Confirm-GuiPort)) { Set-Page 2; return }
            Start-WorkerGui
        }
    }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'House Planner - Check required','OK','Warning')|Out-Null}
})
if($Root){
    $pathBox.Text=$Root
    try{if(Test-Path -LiteralPath (Join-Path (Assert-Root $Root) 'house-planner.install.json')){$repairRadio.Checked=$true;Prefill-Existing;$m=Get-Manifest (Assert-Root $Root);$forkRadio.Checked=($m.source -eq 'Fork');$originalRadio.Checked=($m.source -eq 'Original')}}catch{}
}
Set-Page 0
[void]$form.ShowDialog()
