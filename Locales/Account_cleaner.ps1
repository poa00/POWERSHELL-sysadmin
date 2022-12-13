﻿<#
Name......: Account_cleaner.ps1
Version...: 22.12.2
Author....: Dario CORRADA

This script removes account from local computer
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
$fullname -match "([a-zA-Z_\-\.\\\s0-9:]+)\\Locales\\Account_cleaner\.ps1$" > $null
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
Import-Module -Name "$workdir\Modules\Forms.psm1"

<# 
*** TODO ***
Verificare funzionamento RSAT e trovare un metodo che non richiami Active Directory (aka Get-ADUser)
#>
# import Active Directory module
$ErrorActionPreference= 'Stop'
try {
    Import-Module ActiveDirectory
} catch {
    Add-WindowsCapability -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -Online
    Import-Module ActiveDirectory
}
$ErrorActionPreference= 'Inquire'

<#
# create temporary directory
$tmppath = 'C:\TEMPSOFTWARE'
if (!(Test-Path $tmppath)) {
    New-Item -ItemType directory -Path $tmppath > $null
}
#>

# getting users list
$users = Get-CimInstance Win32_UserAccount
$whoami = @{}
$folders = Get-ChildItem C:\Users
$orphans = @()
foreach ($item in $folders) {
    Write-Host -NoNewline "Checking [$item]..."
    if ($users.Name -contains $item) {
        Write-Host -ForegroundColor Green 'OK'
        $whoami[$item] = 'local'
    } else {
        $answ = [System.Windows.MessageBox]::Show("[$item] is not a local user: search on AD?",'INFO','YesNo','Warning')
        if ($answ -eq "Yes") {
            $ErrorActionPreference= 'Stop'
            try {
                Get-ADUser -Identity $item | Out-Null
                Write-Host -ForegroundColor Green 'OK'
                $whoami[$item] = 'AD'
            } catch { 
                # AD user not found
                $orphans += $item
                Write-Host -ForegroundColor Red 'KO'
            }
            $ErrorActionPreference= 'Inquire'
        } else {
            $orphans += $item
            Write-Host -ForegroundColor Red 'KO'
        }
    }
}
$group = [ADSI] "WinNT://./Administrators,group"
$members = @($group.psbase.Invoke("Members"))
$AdminList = ($members | ForEach {$_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)})

# control panel
$hsize = 150 + (30 * $folders.Count)
$form_panel = FormBase -w 300 -h $hsize -text "USERS FOLDERS"
$label = Label -form $form_panel -x 10 -y 20 -w 200 -h 30 -text 'Select profiles to be deleted:'
$vpos = 50
$boxes = @()
foreach ($item in $folders) {
    if ($orphans -contains $item) {
        $boxes += CheckBox -form $form_panel -checked $false -x 20 -y $vpos -text $item -enabled $false
    } else {
        $boxes += CheckBox -form $form_panel -checked $false -x 20 -y $vpos -text $item
    }
    $vpos += 30
}
$vpos += 20
OKButton -form $form_panel -x 90 -y $vpos -text "Ok"
$result = $form_panel.ShowDialog()

# perform operations
foreach ($box in $boxes) {
    if ($box.Checked -eq $true) {
        $theuser = $box.Text
        Write-Host -NoNewline "Checking [$theuser]... "
        if ($whoami[$theuser] -eq 'local') {
            Write-Host -ForegroundColor Blue 'local'

            # remove local account
            Write-Host -NoNewline 'Removing account... '
            $ErrorActionPreference= 'Stop'
            Try {
                # Remove-LocalUser -Name $theuser
                Write-Host -ForegroundColor Green 'OK'                
            }
            Catch {
                Write-Host -ForegroundColor Red 'KO'
                Write-Output "`nError: $($error[0].ToString())"
                $answ = [System.Windows.MessageBox]::Show("An error occurred! Proceed?",'ERROR','YesNo','Error')
                if ($answ -eq "No") {    
                    exit
                }
            }
            $ErrorActionPreference= 'Inquire'
        } elseif ($whoami[$theuser] -eq 'AD') {
            Write-Host -ForegroundColor Cyan 'AD'

            # remove admin privileges            
            if ($AdminList -contains $theuser) {
                Write-Host -NoNewline 'Disabling admin... '
                $ErrorActionPreference= 'Stop'
                Try {
                    # Remove-LocalGroupMember -Group "Administrators" -Member $theuser
                    Write-Host -ForegroundColor Green 'OK'                
                }
                Catch {
                    Write-Host -ForegroundColor Red 'KO'
                    Write-Output "`nError: $($error[0].ToString())"
                    $answ = [System.Windows.MessageBox]::Show("An error occurred! Proceed?",'ERROR','YesNo','Error')
                    if ($answ -eq "No") {    
                        exit
                    }
                }
                $ErrorActionPreference= 'Inquire'                
            }
        }

<#
        # search and remove keys
        $record = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
            Get-ItemProperty | Where-Object {$_.ProfileimagePath -match "C:\\Users\\$theuser" } | Select-Object -Property ProfileimagePath, PSChildName
        $keypath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\" + $record.PSChildName
        Remove-Item -Path $keypath -Recurse
        
        # removing user folder
        $thepath = 'C:\Users\' + $theuser
        Move-Item -Path $thepath -Destination 'C:\TEMPSOFTWARE' -Force

#>

    }
}

<#
# removing TEMPSOFTWARE
$ErrorActionPreference = 'Stop'
Try {
    # Cambio i permessi su file e cartelle
    # $string = '/F C:\TEMPSOFTWARE /R /D Y'
    # Start-Process -Wait takeown.exe $string

    # elevate Explorer
    taskkill /F /IM explorer.exe
    Start-Sleep 3
    Start-Process C:\Windows\explorer.exe

    $path = "C:\TEMPSOFTWARE"
    $shell = new-object -comobject "Shell.Application"
    $item = $shell.Namespace(0).ParseName("$path")
    $item.InvokeVerb("delete")
    Clear-RecycleBin -Force -Confirm:$false
}
Catch {
    Write-Output "`nError: $($error[0].ToString())"
    pause
}
$ErrorActionPreference = 'Inquire'
#>