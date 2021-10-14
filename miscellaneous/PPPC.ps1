<#
Name......: PPPC.ps1
Version...: 21.06.1
Author....: Dario CORRADA

Pipeline per la preparazione di nuovi PC
#>

# elevated script execution with admin privileges
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$testadmin = $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if ($testadmin -eq $false) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))
    exit $LASTEXITCODE
}

# get working directory
$fullname = $MyInvocation.MyCommand.Path
$fullname -match "([a-zA-Z_\-\.\\\s0-9:]+)\\PPPC\.ps1$" > $null
$workdir = $matches[1]

# header 
$ErrorActionPreference= 'SilentlyContinue'
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force
Write-Host "ExecutionPolicy Bypass" -fore Green
$ErrorActionPreference= 'Inquire'
$WarningPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework

function DownloadFilesFromRepo {
Param(
    [string]$Owner,
    [string]$Repository,
    [string]$Path,
    [string]$DestinationPath
    )

    $baseUri = "https://api.github.com/"
    $args = "repos/$Owner/$Repository/contents/$Path"
    $wr = Invoke-WebRequest -UseBasicParsing -Uri $($baseuri+$args)
    $objects = $wr.Content | ConvertFrom-Json
    $files = $objects | where {$_.type -eq "file"} | Select -exp download_url
    $directories = $objects | where {$_.type -eq "dir"}
    
    $directories | ForEach-Object { 
        DownloadFilesFromRepo -Owner $Owner -Repository $Repository -Path $_.path -DestinationPath $($DestinationPath+$_.name)
    }
    
    if (-not (Test-Path $DestinationPath)) {
        # Destination path does not exist, let's create it
        try {
            New-Item -Path $DestinationPath -ItemType Directory -ErrorAction Stop
        } catch {
            throw "Could not create path '$DestinationPath'!"
        }
    }

    foreach ($file in $files) {
        $fileDestination = Join-Path $DestinationPath (Split-Path $file -Leaf)
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $file -OutFile $fileDestination -ErrorAction Stop | out-null
            "Fetching '$($file)'..."
        } catch {
            throw "Unable to download '$($file.path)'"
        }
    }
}

# creo una cartella temporanea e scarico gli script
$tmppath = 'C:\PPPCtemp'
New-Item -ItemType directory -Path $tmppath > $null
New-Item -ItemType directory -Path "$tmppath\Modules" > $null
New-Item -ItemType directory -Path "$tmppath\AzureAD" > $null
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'Modules' -DestinationPath "$tmppath\Modules"
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'AzureAD' -DestinationPath "$tmppath\AzureAD"
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'Init_PC.ps1' -DestinationPath $tmppath
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'JoinUser.ps1' -DestinationPath $tmppath
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'Join2Domain.ps1' -DestinationPath $tmppath
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'Powerize.ps1' -DestinationPath $tmppath
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'Update_Win10.ps1' -DestinationPath $tmppath
DownloadFilesFromRepo -Owner 'dcorrada' -Repository 'POWERSHELL' -Path 'Wazuh.ps1' -DestinationPath $tmppath

# creo i file batch per gli step da eseguire
New-Item -ItemType file -Path "$tmppath\STEP01.cmd" > $null
@"
copy "$tmppath\STEP02.cmd" "C:\Users\$env:username\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
PowerShell.exe "& "'$tmppath\Join2Domain.ps1'
del "C:\Users\$env:username\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\STEP01.cmd"
"@ | Out-File "$tmppath\STEP01.cmd" -Encoding ASCII -Append

New-Item -ItemType file -Path "$tmppath\STEP02.cmd" > $null
@"
PowerShell.exe "& "'$tmppath\Powerize.ps1'
pause
PowerShell.exe "& "'$tmppath\Wazuh.ps1'
pause
PowerShell.exe "& "'$tmppath\JoinUser.ps1'
pause
PowerShell.exe "& "'$tmppath\AzureAD\CreateMSAccount.ps1'
pause
PowerShell.exe "& "'$tmppath\Update_Win10.ps1'
pause
rd /s /q "$tmppath"
del "C:\Users\$env:username\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\STEP02.cmd"
"@ | Out-File "$tmppath\STEP02.cmd" -Encoding ASCII -Append

# copio il primo batch file per il riavvio successivo
Copy-Item -Path "$tmppath\STEP01.cmd" -Destination "C:\Users\$env:username\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"

# lancio lo STEP00
PowerShell.exe "& ""$tmppath\Init_PC.ps1"