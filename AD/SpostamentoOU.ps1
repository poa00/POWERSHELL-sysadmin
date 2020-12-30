﻿<#
Name......: SpostamentoOU.ps1
Version...: 19.04.1
Author....: Dario CORRADA

Questo script accede ad Active Directory e sposta una lista di computer da una OU specificata ad un'altra
#>


# header 
$ErrorActionPreference= 'SilentlyContinue'
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force
Write-Host "ExecutionPolicy Bypass" -fore Green
$ErrorActionPreference= 'Inquire'
$WarningPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework
$workdir = Get-Location
Import-Module -Name "$workdir\Moduli_PowerShell\Forms.psm1"

# Controllo accesso
$AD_login = LoginWindow

# Importo il modulo di Active Directory
if (! (get-Module ActiveDirectory)) { Import-Module ActiveDirectory } 

# recupero la lista dei PC
[System.Reflection.Assembly]::LoadWithPartialName('System.windows.forms')
$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$OpenFileDialog.initialDirectory = "C:\Users\$env:USERNAME\Desktop"
$OpenFileDialog.filter = 'Text file (*.txt)| *.txt'
$OpenFileDialog.ShowDialog() | Out-Null
$file_path = $OpenFileDialog.filename
$computer_list = Get-Content $file_path

# Recupero la lista delle OU disponibili
$ou_available = Get-ADOrganizationalUnit -Filter *
$ou_list = @()
foreach ($item in $ou_available) {
    $ou_list += $item.DistinguishedName
}

$source_dest = @()
foreach ($item in ('OU SORGENTE', 'OU DESTINAZIONE')) {
    $formlist = FormBase -w 400 -h 200 -text $item
    $DropDown = new-object System.Windows.Forms.ComboBox
    $DropDown.Location = new-object System.Drawing.Size(10,60)
    $DropDown.Size = new-object System.Drawing.Size(350,30)
    foreach ($elem in ($ou_list | sort)) {
        $DropDown.Items.Add($elem)  > $null
    }
    $formlist.Controls.Add($DropDown)
    $DropDownLabel = new-object System.Windows.Forms.Label
    $DropDownLabel.Location = new-object System.Drawing.Size(10,20) 
    $DropDownLabel.size = new-object System.Drawing.Size(500,30) 
    $DropDownLabel.Text = "Scegliere OU"
    $formlist.Controls.Add($DropDownLabel)
    OKButton -form $formlist -x 100 -y 100 -text "Ok"
    $formlist.Add_Shown({$DropDown.Select()})
    $result = $formlist.ShowDialog()
    $source_dest += $DropDown.Text
}

foreach ($computer_name in $computer_list) {
    Write-Host -Nonewline $computer_name
    $computer_ADobj = Get-ADComputer $computer_name -Credential $AD_login
    # Write-Host $computer_ADobj.DistinguishedName
    if ($computer_ADobj.DistinguishedName -match $source_dest[1]) {
        Write-Host -ForegroundColor Cyan " skipped"
    } elseif ($computer_ADobj.DistinguishedName -match $source_dest[0]) {
        $target_path = "OU=" + $dest_ou + $suffix
        $computer_ADobj | Move-ADObject -Credential $AD_login -TargetPath $source_dest[1]
        Write-Host -ForegroundColor Green " remapped"
    } else {
        Write-Host -ForegroundColor Cyan " skipped"
    }
}
pause