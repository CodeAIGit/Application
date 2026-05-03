<#
.SYNOPSIS
    Active Directory GPO to Microsoft Intune Migration Tool

.DESCRIPTION
    A comprehensive PowerShell GUI application for discovering, assessing, and migrating
    Active Directory Group Policy Objects (GPOs) to Microsoft Intune configuration profiles.

    Phases:
      1. Discovery  - Connect to AD, enumerate GPOs, export XML reports
      2. Assessment - Parse GPO XML, categorize settings, score migration readiness
      3. Migration  - Create Intune Configuration Profiles via Microsoft Graph API
      4. Report     - Generate HTML/CSV summary of the full migration effort

.REQUIREMENTS
    - PowerShell 5.1+ (Windows only)
    - RSAT: Group Policy Management Tools (for GroupPolicy module)
    - Microsoft.Graph.DeviceManagement module
    - Microsoft.Graph.Authentication module
    - Domain-joined machine or network access to a domain controller
    - Intune Administrator or Global Administrator role (for migration phase)

.NOTES
    Author  : Gulab Prasad
    Website : https://gulabprasad.com
    Version : 1.0
    Created : 2025

.LICENSE
    MIT License — see LICENSE file for details.
#>

#Requires -Version 5.1

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ──────────────────────────────────────────────────────────────────────────────
# Global state
# ──────────────────────────────────────────────────────────────────────────────
$script:DiscoveredGPOs   = @()
$script:AssessedGPOs     = @()
$script:MigrationResults = @()
$script:ExportFolder     = [System.IO.Path]::Combine($env:TEMP, "GPO-IntuneMigration")
$script:GraphConnected   = $false

# ──────────────────────────────────────────────────────────────────────────────
# GPO-to-Intune mapping reference table
# Key = XML section identifier, Value = hashtable with Intune info
# ──────────────────────────────────────────────────────────────────────────────
$script:GPOMapping = @{
    "SecuritySettings"         = @{ IntuneProfile = "Endpoint Security – Security Baselines / Account Protection"; Status = "Supported";    Notes = "Maps to Intune Endpoint Security policies and Security Baselines." }
    "WindowsFirewall"          = @{ IntuneProfile = "Endpoint Security – Firewall";                                 Status = "Supported";    Notes = "Maps directly to Intune Firewall profiles under Endpoint Security." }
    "BitLocker"                = @{ IntuneProfile = "Endpoint Security – Disk Encryption (BitLocker)";              Status = "Supported";    Notes = "Maps to Intune BitLocker configuration profile." }
    "WindowsUpdateServices"    = @{ IntuneProfile = "Windows Update for Business – Update Rings";                   Status = "Supported";    Notes = "Maps to Intune Windows Update Rings and Feature Update policies." }
    "AdministrativeTemplates"  = @{ IntuneProfile = "Configuration Profiles – Settings Catalog / Admin Templates";  Status = "Partial";      Notes = "ADMX-backed policies map to Settings Catalog. Custom ADMX may need OMA-URI." }
    "InternetExplorer"         = @{ IntuneProfile = "Configuration Profiles – Microsoft Edge (Settings Catalog)";   Status = "Partial";      Notes = "IE policies superseded by Edge. Migrate to Edge Settings Catalog entries." }
    "Scripts"                  = @{ IntuneProfile = "Devices – Scripts (PowerShell)";                               Status = "Partial";      Notes = "Logon/Logoff/Startup/Shutdown scripts can run as Intune PowerShell scripts." }
    "FolderRedirection"        = @{ IntuneProfile = "Not Supported – use OneDrive Known Folder Move";               Status = "NotSupported"; Notes = "Intune does not support Folder Redirection. Use OneDrive KFM via Settings Catalog." }
    "DriveMaps"                = @{ IntuneProfile = "Not Supported – use logon script or third-party";              Status = "NotSupported"; Notes = "Drive maps via GP Preferences have no direct Intune equivalent." }
    "Printers"                 = @{ IntuneProfile = "Partial – Universal Print or Win32 app script";                Status = "Partial";      Notes = "Universal Print integration or PowerShell script deployment via Intune." }
    "SoftwareInstallation"     = @{ IntuneProfile = "Apps – Win32 App / Line-of-Business App";                      Status = "Partial";      Notes = "Use Intune app deployment (Win32, MSI, MSIX) instead of GP Software Install." }
    "AppLocker"                = @{ IntuneProfile = "Endpoint Security – App Control for Business";                  Status = "Partial";      Notes = "AppLocker policies can be migrated; WDAC/App Control is the modern equivalent." }
    "WirelessNetworks"         = @{ IntuneProfile = "Configuration Profiles – Wi-Fi";                               Status = "Supported";    Notes = "Maps to Intune Wi-Fi configuration profiles." }
    "WiredNetworks"            = @{ IntuneProfile = "Configuration Profiles – Wired Network (802.1x)";              Status = "Supported";    Notes = "Maps to Intune Wired Network configuration profiles." }
    "CertificateSettings"      = @{ IntuneProfile = "Configuration Profiles – Trusted Certificate / SCEP / PKCS";   Status = "Supported";    Notes = "Root/intermediate CAs map to Trusted Certificate profiles." }
    "PowerOptions"             = @{ IntuneProfile = "Configuration Profiles – Settings Catalog (Power)";            Status = "Supported";    Notes = "Power settings available in Settings Catalog." }
    "SystemServices"           = @{ IntuneProfile = "Not Supported – use PowerShell script";                        Status = "NotSupported"; Notes = "Service configuration has no native Intune equivalent; use remediation scripts." }
    "RegistryPreferences"      = @{ IntuneProfile = "Configuration Profiles – Custom OMA-URI";                      Status = "Partial";      Notes = "Registry preferences can be replicated via custom OMA-URI or Settings Catalog." }
    "EnvironmentVariables"     = @{ IntuneProfile = "Not Supported – use PowerShell script";                        Status = "NotSupported"; Notes = "No native Intune equivalent; deploy via PowerShell script." }
    "IniFiles"                 = @{ IntuneProfile = "Not Supported – use PowerShell script";                        Status = "NotSupported"; Notes = "No native Intune equivalent." }
    "LocalUsers"               = @{ IntuneProfile = "Endpoint Security – Account Protection (LAPS)";                Status = "Partial";      Notes = "Local admin account management via Windows LAPS in Intune." }
    "AuditPolicy"              = @{ IntuneProfile = "Endpoint Security – Security Baselines / Custom";               Status = "Supported";    Notes = "Advanced audit policies available in Endpoint Security baselines." }
    "UserRightsAssignment"     = @{ IntuneProfile = "Endpoint Security – Security Baselines";                        Status = "Supported";    Notes = "User rights assignments in Intune Security Baselines." }
    "RestrictedGroups"         = @{ IntuneProfile = "Endpoint Security – Account Protection";                        Status = "Supported";    Notes = "Local group membership managed via Account Protection policy." }
    "WindowsDefender"          = @{ IntuneProfile = "Endpoint Security – Antivirus";                                Status = "Supported";    Notes = "Defender AV settings map to Intune Antivirus profiles." }
    "AttackSurfaceReduction"   = @{ IntuneProfile = "Endpoint Security – Attack Surface Reduction";                  Status = "Supported";    Notes = "ASR rules map directly to Intune ASR profiles." }
    "ExploitGuard"             = @{ IntuneProfile = "Endpoint Security – Attack Surface Reduction";                  Status = "Supported";    Notes = "Exploit protection settings available in ASR profiles." }
}

# Status color map
$script:StatusColors = @{
    "Supported"    = [System.Drawing.Color]::FromArgb(198, 239, 206)   # light green
    "Partial"      = [System.Drawing.Color]::FromArgb(255, 235, 156)   # light amber
    "NotSupported" = [System.Drawing.Color]::FromArgb(255, 199, 206)   # light red
    "Unknown"      = [System.Drawing.Color]::FromArgb(220, 220, 220)   # light grey
}

# ──────────────────────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param([System.Windows.Forms.TextBox]$Box, [string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "[$ts][$Level] $Message"
    $Box.AppendText("$line`r`n")
    $Box.SelectionStart = $Box.Text.Length
    $Box.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Test-GroupPolicyModule {
    return (Get-Module -ListAvailable -Name GroupPolicy) -ne $null
}

function Test-GraphModules {
    $required = @("Microsoft.Graph.Authentication", "Microsoft.Graph.DeviceManagement")
    foreach ($m in $required) {
        if (-not (Get-Module -ListAvailable -Name $m)) { return $false }
    }
    return $true
}

function Get-GPOSettingSections {
    param([xml]$GPOXml)
    $sections = @()

    # Computer Configuration
    $computer = $GPOXml.GPO.Computer
    if ($computer) {
        # Administrative Templates
        if ($computer.ExtensionData | Where-Object { $_.Name -like "*Administrative*" -or $_.Name -like "*Registry*" }) {
            $sections += "AdministrativeTemplates"
        }
        # Security Settings
        if ($computer.ExtensionData | Where-Object { $_.Name -like "*Security*" }) {
            $secExt = $computer.ExtensionData | Where-Object { $_.Name -like "*Security*" }
            $secXml = [xml]($secExt.Extension.OuterXml)
            # Detect sub-sections
            if ($secXml -and $secXml.InnerXml -match "AuditSetting")      { $sections += "AuditPolicy" }
            if ($secXml -and $secXml.InnerXml -match "UserRight")          { $sections += "UserRightsAssignment" }
            if ($secXml -and $secXml.InnerXml -match "RestrictedGroup")    { $sections += "RestrictedGroups" }
            if ($secXml -and $secXml.InnerXml -match "LocalAccount")       { $sections += "LocalUsers" }
            if ($secXml -and $secXml.InnerXml -match "SecurityOptions")    { $sections += "SecuritySettings" }
            if ($sections -notcontains "SecuritySettings")                  { $sections += "SecuritySettings" }
        }
        # Windows Firewall
        if ($computer.ExtensionData | Where-Object { $_.Name -like "*Firewall*" -or $_.Name -like "*Windows Firewall*" }) {
            $sections += "WindowsFirewall"
        }
        # Windows Update
        if ($computer.ExtensionData | Where-Object { $_.Name -like "*WindowsUpdate*" -or $_.Name -like "*Windows Update*" }) {
            $sections += "WindowsUpdateServices"
        }
        # Scripts
        if ($computer.ExtensionData | Where-Object { $_.Name -like "*Scripts*" }) {
            $sections += "Scripts"
        }
        # Software Installation
        if ($computer.ExtensionData | Where-Object { $_.Name -like "*Software*" }) {
            $sections += "SoftwareInstallation"
        }
        # Folder Redirection
        if ($computer.ExtensionData | Where-Object { $_.Name -like "*Folder*" }) {
            $sections += "FolderRedirection"
        }
    }

    # User Configuration
    $user = $GPOXml.GPO.User
    if ($user) {
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Administrative*" }) {
            if ($sections -notcontains "AdministrativeTemplates") { $sections += "AdministrativeTemplates" }
        }
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Scripts*" }) {
            if ($sections -notcontains "Scripts") { $sections += "Scripts" }
        }
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Folder Redirection*" }) {
            if ($sections -notcontains "FolderRedirection") { $sections += "FolderRedirection" }
        }
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Drive*" }) {
            $sections += "DriveMaps"
        }
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Printer*" }) {
            $sections += "Printers"
        }
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Internet Explorer*" -or $_.Name -like "*InternetExplorer*" }) {
            $sections += "InternetExplorer"
        }
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Registry*" }) {
            $sections += "RegistryPreferences"
        }
        if ($user.ExtensionData | Where-Object { $_.Name -like "*Environment*" }) {
            $sections += "EnvironmentVariables"
        }
    }

    # Fallback — if XML parsed but no extension data found, try raw content scan
    if ($sections.Count -eq 0) {
        $raw = $GPOXml.InnerXml
        if ($raw -match "SecuritySettings|AuditSetting|UserRight")  { $sections += "SecuritySettings" }
        if ($raw -match "WindowsFirewall|FirewallRules")             { $sections += "WindowsFirewall" }
        if ($raw -match "BitLocker|FVDE")                           { $sections += "BitLocker" }
        if ($raw -match "WindowsUpdate|WUServer|NoAutoUpdate")       { $sections += "WindowsUpdateServices" }
        if ($raw -match "Defender|MpEngine|SpyNet")                  { $sections += "WindowsDefender" }
        if ($raw -match "AppLocker")                                 { $sections += "AppLocker" }
        if ($raw -match "AttackSurface|ASR")                         { $sections += "AttackSurfaceReduction" }
        if ($raw -match "FolderRedirection")                         { $sections += "FolderRedirection" }
        if ($raw -match "DriveMap|MapDrive")                         { $sections += "DriveMaps" }
        if ($raw -match "Script|Logon|Logoff|Startup|Shutdown")      { $sections += "Scripts" }
        if ($raw -match "Software.*Installation|SoftwareInstallation") { $sections += "SoftwareInstallation" }
        if ($raw -match "Printer")                                   { $sections += "Printers" }
        if ($raw -match "WiFi|Wireless|SSID")                        { $sections += "WirelessNetworks" }
        if ($raw -match "Certificate|CertificateSettings")           { $sections += "CertificateSettings" }
        if ($raw -match "InternetExplorer|Internet Explorer")        { $sections += "InternetExplorer" }
        if ($raw -match "RegistryPref|Registry")                     { $sections += "RegistryPreferences" }
        if ($raw -match "PowerPlan|PowerOptions|SleepSetting")       { $sections += "PowerOptions" }
        if ($raw -match "ServiceGeneral|NtService|SystemServices")   { $sections += "SystemServices" }
        if ($raw -match "LocalUser|LocalAccount")                    { $sections += "LocalUsers" }
        if ($raw -match "AuditPolicy|AuditSetting")                  { $sections += "AuditPolicy" }
        if ($raw -match "UserRight")                                 { $sections += "UserRightsAssignment" }
        if ($raw -match "RestrictedGroup")                           { $sections += "RestrictedGroups" }
        if ($raw -match "ExploitGuard|ExploitProtection")            { $sections += "ExploitGuard" }
        if ($sections.Count -eq 0)                                   { $sections += "AdministrativeTemplates" }
    }

    return ($sections | Select-Object -Unique)
}

function Get-MigrationScore {
    param([string[]]$Sections)
    if ($Sections.Count -eq 0) { return 0 }
    $supported    = ($Sections | Where-Object { $script:GPOMapping[$_].Status -eq "Supported" }).Count
    $partial      = ($Sections | Where-Object { $script:GPOMapping[$_].Status -eq "Partial" }).Count
    $notSupported = ($Sections | Where-Object { $script:GPOMapping[$_].Status -eq "NotSupported" }).Count
    $unknown      = $Sections.Count - $supported - $partial - $notSupported

    $score = [math]::Round((($supported * 100) + ($partial * 50) + ($unknown * 25)) / ($Sections.Count * 100) * 100)
    return [math]::Max(0, [math]::Min(100, $score))
}

function New-IntuneConfigurationProfile {
    param(
        [string]$DisplayName,
        [string]$Description,
        [string]$Platform = "windows10AndLater",
        [string]$TemplateId = ""
    )
    try {
        Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop

        if ($TemplateId -ne "") {
            $body = @{
                displayName = $DisplayName
                description = $Description
                templateId  = $TemplateId
            }
            $profile = New-MgDeviceManagementConfigurationPolicy -BodyParameter $body
        } else {
            $body = @{
                "@odata.type"  = "#microsoft.graph.windows10CustomConfiguration"
                displayName    = $DisplayName
                description    = $Description
                omaSettings    = @()
            }
            $profile = New-MgDeviceManagementDeviceConfiguration -BodyParameter $body
        }
        return $profile
    } catch {
        throw "Failed to create Intune profile '$DisplayName': $($_.Exception.Message)"
    }
}

function Export-HTMLReport {
    param([string]$OutputPath)

    $supported    = ($script:AssessedGPOs | Where-Object { $_.OverallStatus -eq "Supported" }).Count
    $partial      = ($script:AssessedGPOs | Where-Object { $_.OverallStatus -eq "Partial" }).Count
    $notSupported = ($script:AssessedGPOs | Where-Object { $_.OverallStatus -eq "NotSupported" }).Count
    $total        = $script:AssessedGPOs.Count
    $avgScore     = if ($total -gt 0) { [math]::Round(($script:AssessedGPOs | Measure-Object -Property Score -Average).Average) } else { 0 }

    $rowsHtml = ""
    foreach ($gpo in $script:AssessedGPOs) {
        $statusColor = switch ($gpo.OverallStatus) {
            "Supported"    { "#C6EFCE" }
            "Partial"      { "#FFEB9C" }
            "NotSupported" { "#FFC7CE" }
            default        { "#DCDCDC" }
        }
        $sectionsHtml = ($gpo.Sections | ForEach-Object {
            $s = $_
            $m = $script:GPOMapping[$s]
            if ($m) {
                $sc = switch ($m.Status) {
                    "Supported"    { "#C6EFCE" }
                    "Partial"      { "#FFEB9C" }
                    "NotSupported" { "#FFC7CE" }
                    default        { "#DCDCDC" }
                }
                "<tr><td style='padding:4px 8px;background:$sc'>$s</td><td style='padding:4px 8px'>$($m.IntuneProfile)</td><td style='padding:4px 8px'>$($m.Notes)</td></tr>"
            }
        }) -join ""

        $migStatus = if ($script:MigrationResults | Where-Object { $_.GPOName -eq $gpo.Name }) {
            ($script:MigrationResults | Where-Object { $_.GPOName -eq $gpo.Name }).Status
        } else { "Not Migrated" }

        $rowsHtml += @"
<tr>
  <td style='padding:6px 10px;font-weight:bold'>$($gpo.Name)</td>
  <td style='padding:6px 10px'>$($gpo.Domain)</td>
  <td style='padding:6px 10px'>$($gpo.LinkedOUs -join "<br>")</td>
  <td style='padding:6px 10px;background:$statusColor;text-align:center'>$($gpo.OverallStatus)</td>
  <td style='padding:6px 10px;text-align:center'>$($gpo.Score)%</td>
  <td style='padding:6px 10px;text-align:center'>$migStatus</td>
</tr>
<tr>
  <td colspan='6' style='padding:0 10px 10px 30px;background:#f9f9f9'>
    <table style='width:100%;border-collapse:collapse;font-size:12px'>
      <tr style='background:#e0e0e0'><th style='padding:4px 8px;text-align:left'>Setting Section</th><th style='padding:4px 8px;text-align:left'>Intune Profile</th><th style='padding:4px 8px;text-align:left'>Notes</th></tr>
      $sectionsHtml
    </table>
  </td>
</tr>
"@
    }

    $migratedRows = ""
    foreach ($mr in $script:MigrationResults) {
        $sc = if ($mr.Status -eq "Success") { "#C6EFCE" } else { "#FFC7CE" }
        $migratedRows += "<tr><td style='padding:6px 10px'>$($mr.GPOName)</td><td style='padding:6px 10px'>$($mr.IntuneProfileName)</td><td style='padding:6px 10px;background:$sc'>$($mr.Status)</td><td style='padding:6px 10px'>$($mr.Message)</td></tr>"
    }

    $migrationSection = if ($script:MigrationResults.Count -gt 0) { @"
<h2 style='color:#1F3864;margin-top:40px'>Migration Results</h2>
<table style='width:100%;border-collapse:collapse;font-size:13px'>
  <tr style='background:#1F3864;color:white'>
    <th style='padding:8px 10px;text-align:left'>GPO Name</th>
    <th style='padding:8px 10px;text-align:left'>Intune Profile Created</th>
    <th style='padding:8px 10px;text-align:left'>Status</th>
    <th style='padding:8px 10px;text-align:left'>Message</th>
  </tr>
  $migratedRows
</table>
"@ } else { "" }

    $html = @"
<!DOCTYPE html>
<html>
<head>
  <meta charset='UTF-8'>
  <title>GPO to Intune Migration Report</title>
  <style>
    body { font-family: 'Segoe UI', Arial, sans-serif; margin: 30px; color: #222; background: #f5f5f5; }
    h1   { color: #1F3864; border-bottom: 3px solid #2E75B6; padding-bottom: 10px; }
    h2   { color: #2E75B6; }
    .summary { display:flex; gap:20px; margin:20px 0; }
    .card { background:white; border-radius:8px; padding:20px; min-width:140px; text-align:center; box-shadow:0 2px 6px rgba(0,0,0,.1); }
    .card .num { font-size:36px; font-weight:bold; }
    .card .lbl { font-size:13px; color:#666; margin-top:4px; }
    .green { color:#375623; }
    .amber { color:#7D6608; }
    .red   { color:#9C0006; }
    .blue  { color:#1F3864; }
    table { width:100%; border-collapse:collapse; background:white; box-shadow:0 2px 6px rgba(0,0,0,.08); border-radius:6px; overflow:hidden; margin-top:20px; }
    th    { background:#2E75B6; color:white; text-align:left; padding:10px 12px; }
    tr:hover td { background:#EBF3FB; }
    td    { border-bottom:1px solid #ddd; vertical-align:top; }
    .footer { margin-top:40px; font-size:12px; color:#999; text-align:center; }
  </style>
</head>
<body>
  <h1>GPO to Microsoft Intune Migration Report</h1>
  <p style='color:#666'>Generated: $(Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss') &nbsp;|&nbsp; Author: Gulab Prasad &nbsp;|&nbsp; <a href='https://gulabprasad.com'>gulabprasad.com</a></p>

  <div class='summary'>
    <div class='card'><div class='num blue'>$total</div><div class='lbl'>Total GPOs</div></div>
    <div class='card'><div class='num green'>$supported</div><div class='lbl'>Fully Supported</div></div>
    <div class='card'><div class='num amber'>$partial</div><div class='lbl'>Partial Support</div></div>
    <div class='card'><div class='num red'>$notSupported</div><div class='lbl'>Not Supported</div></div>
    <div class='card'><div class='num blue'>$avgScore%</div><div class='lbl'>Avg. Readiness</div></div>
  </div>

  <h2>GPO Assessment Details</h2>
  <table>
    <tr style='background:#1F3864;color:white'>
      <th>GPO Name</th>
      <th>Domain</th>
      <th>Linked OUs</th>
      <th>Status</th>
      <th>Score</th>
      <th>Migration</th>
    </tr>
    $rowsHtml
  </table>

  $migrationSection

  <div class='footer'>
    GPO to Intune Migration Tool v1.0 &nbsp;|&nbsp; <a href='https://gulabprasad.com'>gulabprasad.com</a><br>
    This report is generated automatically. Always review Intune profiles before assigning to production devices.
  </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
}

# ──────────────────────────────────────────────────────────────────────────────
# Main Form
# ──────────────────────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = "GPO to Microsoft Intune Migration Tool"
$form.Size            = New-Object System.Drawing.Size(1100, 780)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = [System.Drawing.Color]::White
$form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)
$form.MinimumSize     = New-Object System.Drawing.Size(900, 650)

# ── Header panel ──────────────────────────────────────────────────────────────
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock      = "Top"
$headerPanel.Height    = 65
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(31, 56, 100)
$form.Controls.Add($headerPanel)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text      = "  GPO to Microsoft Intune Migration Tool"
$titleLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::White
$titleLabel.Location  = New-Object System.Drawing.Point(10, 10)
$titleLabel.Size      = New-Object System.Drawing.Size(700, 28)
$headerPanel.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text      = "  Discover · Assess · Migrate · Report"
$subtitleLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(180, 210, 255)
$subtitleLabel.Location  = New-Object System.Drawing.Point(10, 38)
$subtitleLabel.Size      = New-Object System.Drawing.Size(500, 20)
$headerPanel.Controls.Add($subtitleLabel)

$websiteLink = New-Object System.Windows.Forms.LinkLabel
$websiteLink.Text           = "gulabprasad.com"
$websiteLink.Font           = New-Object System.Drawing.Font("Segoe UI", 9)
$websiteLink.ForeColor      = [System.Drawing.Color]::FromArgb(180, 210, 255)
$websiteLink.LinkColor      = [System.Drawing.Color]::FromArgb(180, 210, 255)
$websiteLink.ActiveLinkColor = [System.Drawing.Color]::White
$websiteLink.Location       = New-Object System.Drawing.Point(900, 25)
$websiteLink.Size           = New-Object System.Drawing.Size(160, 20)
$websiteLink.Add_LinkClicked({ Start-Process "https://gulabprasad.com" })
$headerPanel.Controls.Add($websiteLink)

# ── TabControl ────────────────────────────────────────────────────────────────
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock       = "Fill"
$tabs.Font       = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$tabs.ItemSize   = New-Object System.Drawing.Size(200, 32)
$tabs.SizeMode   = "Fixed"
$form.Controls.Add($tabs)

# ══════════════════════════════════════════════════════════════════════════════
# TAB 1 — DISCOVERY
# ══════════════════════════════════════════════════════════════════════════════
$tabDiscover = New-Object System.Windows.Forms.TabPage
$tabDiscover.Text    = "  1. Discovery  "
$tabDiscover.Padding = New-Object System.Windows.Forms.Padding(10)
$tabs.TabPages.Add($tabDiscover)

# Domain input row
$discPanel = New-Object System.Windows.Forms.Panel
$discPanel.Dock   = "Top"
$discPanel.Height = 100
$tabDiscover.Controls.Add($discPanel)

$lblDomain = New-Object System.Windows.Forms.Label
$lblDomain.Text     = "Domain / DC:"
$lblDomain.Location = New-Object System.Drawing.Point(10, 15)
$lblDomain.Size     = New-Object System.Drawing.Size(110, 22)
$lblDomain.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$discPanel.Controls.Add($lblDomain)

$txtDomain = New-Object System.Windows.Forms.TextBox
$txtDomain.Location = New-Object System.Drawing.Point(125, 12)
$txtDomain.Size     = New-Object System.Drawing.Size(320, 22)
$txtDomain.Text     = $env:USERDNSDOMAIN
$discPanel.Controls.Add($txtDomain)

$lblOU = New-Object System.Windows.Forms.Label
$lblOU.Text     = "Scope (OU DN, blank=all):"
$lblOU.Location = New-Object System.Drawing.Point(460, 15)
$lblOU.Size     = New-Object System.Drawing.Size(180, 22)
$lblOU.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$discPanel.Controls.Add($lblOU)

$txtOU = New-Object System.Windows.Forms.TextBox
$txtOU.Location    = New-Object System.Drawing.Point(645, 12)
$txtOU.Size        = New-Object System.Drawing.Size(310, 22)
$txtOU.PlaceholderText = "e.g. OU=Computers,DC=corp,DC=local"
$discPanel.Controls.Add($txtOU)

$btnDiscover = New-Object System.Windows.Forms.Button
$btnDiscover.Text      = "Discover GPOs"
$btnDiscover.Location  = New-Object System.Drawing.Point(10, 48)
$btnDiscover.Size      = New-Object System.Drawing.Size(140, 35)
$btnDiscover.BackColor = [System.Drawing.Color]::FromArgb(46, 117, 182)
$btnDiscover.ForeColor = [System.Drawing.Color]::White
$btnDiscover.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnDiscover.FlatStyle = "Flat"
$discPanel.Controls.Add($btnDiscover)

$btnImportXML = New-Object System.Windows.Forms.Button
$btnImportXML.Text      = "Import GPO XML"
$btnImportXML.Location  = New-Object System.Drawing.Point(165, 48)
$btnImportXML.Size      = New-Object System.Drawing.Size(140, 35)
$btnImportXML.BackColor = [System.Drawing.Color]::FromArgb(68, 114, 196)
$btnImportXML.ForeColor = [System.Drawing.Color]::White
$btnImportXML.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnImportXML.FlatStyle = "Flat"
$discPanel.Controls.Add($btnImportXML)

$btnExportXMLs = New-Object System.Windows.Forms.Button
$btnExportXMLs.Text      = "Export Selected XMLs"
$btnExportXMLs.Location  = New-Object System.Drawing.Point(320, 48)
$btnExportXMLs.Size      = New-Object System.Drawing.Size(155, 35)
$btnExportXMLs.BackColor = [System.Drawing.Color]::FromArgb(84, 130, 53)
$btnExportXMLs.ForeColor = [System.Drawing.Color]::White
$btnExportXMLs.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnExportXMLs.FlatStyle = "Flat"
$btnExportXMLs.Enabled   = $false
$discPanel.Controls.Add($btnExportXMLs)

$lblDiscStatus = New-Object System.Windows.Forms.Label
$lblDiscStatus.Text      = "Ready — click Discover GPOs to connect to Active Directory."
$lblDiscStatus.Location  = New-Object System.Drawing.Point(490, 58)
$lblDiscStatus.Size      = New-Object System.Drawing.Size(560, 20)
$lblDiscStatus.ForeColor = [System.Drawing.Color]::DimGray
$discPanel.Controls.Add($lblDiscStatus)

# GPO ListView
$gpoListView = New-Object System.Windows.Forms.ListView
$gpoListView.View          = "Details"
$gpoListView.FullRowSelect = $true
$gpoListView.CheckBoxes    = $true
$gpoListView.GridLines     = $true
$gpoListView.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
$gpoListView.Dock          = "Fill"
$tabDiscover.Controls.Add($gpoListView)

foreach ($col in @(
    @{ N = "GPO Name";          W = 280 },
    @{ N = "Domain";            W = 160 },
    @{ N = "Linked OUs";        W = 280 },
    @{ N = "Computer Settings"; W = 120 },
    @{ N = "User Settings";     W = 120 },
    @{ N = "Last Modified";     W = 140 }
)) {
    $c = New-Object System.Windows.Forms.ColumnHeader
    $c.Text  = $col.N
    $c.Width = $col.W
    $gpoListView.Columns.Add($c) | Out-Null
}

# Discovery log
$discLogBox = New-Object System.Windows.Forms.TextBox
$discLogBox.Multiline   = $true
$discLogBox.ScrollBars  = "Vertical"
$discLogBox.ReadOnly    = $true
$discLogBox.BackColor   = [System.Drawing.Color]::FromArgb(15, 15, 30)
$discLogBox.ForeColor   = [System.Drawing.Color]::FromArgb(180, 255, 180)
$discLogBox.Font        = New-Object System.Drawing.Font("Consolas", 8)
$discLogBox.Dock        = "Bottom"
$discLogBox.Height      = 120
$tabDiscover.Controls.Add($discLogBox)

# ══════════════════════════════════════════════════════════════════════════════
# TAB 2 — ASSESSMENT
# ══════════════════════════════════════════════════════════════════════════════
$tabAssess = New-Object System.Windows.Forms.TabPage
$tabAssess.Text    = "  2. Assessment  "
$tabAssess.Padding = New-Object System.Windows.Forms.Padding(10)
$tabs.TabPages.Add($tabAssess)

$assessCtrlPanel = New-Object System.Windows.Forms.Panel
$assessCtrlPanel.Dock   = "Top"
$assessCtrlPanel.Height = 60
$tabAssess.Controls.Add($assessCtrlPanel)

$btnAssess = New-Object System.Windows.Forms.Button
$btnAssess.Text      = "Assess Selected GPOs"
$btnAssess.Location  = New-Object System.Drawing.Point(10, 12)
$btnAssess.Size      = New-Object System.Drawing.Size(180, 35)
$btnAssess.BackColor = [System.Drawing.Color]::FromArgb(46, 117, 182)
$btnAssess.ForeColor = [System.Drawing.Color]::White
$btnAssess.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnAssess.FlatStyle = "Flat"
$assessCtrlPanel.Controls.Add($btnAssess)

$btnAssessAll = New-Object System.Windows.Forms.Button
$btnAssessAll.Text      = "Assess All Discovered"
$btnAssessAll.Location  = New-Object System.Drawing.Point(205, 12)
$btnAssessAll.Size      = New-Object System.Drawing.Size(170, 35)
$btnAssessAll.BackColor = [System.Drawing.Color]::FromArgb(68, 114, 196)
$btnAssessAll.ForeColor = [System.Drawing.Color]::White
$btnAssessAll.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnAssessAll.FlatStyle = "Flat"
$assessCtrlPanel.Controls.Add($btnAssessAll)

$lblAssessStatus = New-Object System.Windows.Forms.Label
$lblAssessStatus.Text      = "Run Discovery first, then assess GPO migration readiness."
$lblAssessStatus.Location  = New-Object System.Drawing.Point(395, 20)
$lblAssessStatus.Size      = New-Object System.Drawing.Size(600, 22)
$lblAssessStatus.ForeColor = [System.Drawing.Color]::DimGray
$assessCtrlPanel.Controls.Add($lblAssessStatus)

# Assessment results DataGridView
$assessGrid = New-Object System.Windows.Forms.DataGridView
$assessGrid.Dock                    = "Fill"
$assessGrid.ReadOnly                = $true
$assessGrid.AllowUserToAddRows      = $false
$assessGrid.AllowUserToDeleteRows   = $false
$assessGrid.RowHeadersVisible       = $false
$assessGrid.SelectionMode           = "FullRowSelect"
$assessGrid.AutoSizeColumnsMode     = "Fill"
$assessGrid.GridColor               = [System.Drawing.Color]::LightGray
$assessGrid.Font                    = New-Object System.Drawing.Font("Segoe UI", 9)
$assessGrid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$assessGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(31, 56, 100)
$assessGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$assessGrid.EnableHeadersVisualStyles = $false
$tabAssess.Controls.Add($assessGrid)

foreach ($col in @(
    @{ N = "GPO Name";         P = "Name";          W = 30 },
    @{ N = "Domain";           P = "Domain";         W = 15 },
    @{ N = "Setting Sections"; P = "SectionsSummary";W = 25 },
    @{ N = "Overall Status";   P = "OverallStatus";  W = 12 },
    @{ N = "Score";            P = "Score";          W = 8  },
    @{ N = "Recommendation";   P = "Recommendation"; W = 20 }
)) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.HeaderText     = $col.N
    $c.DataPropertyName = $col.P
    $c.FillWeight     = $col.W
    $assessGrid.Columns.Add($c) | Out-Null
}

# Detail panel at bottom
$assessDetailBox = New-Object System.Windows.Forms.RichTextBox
$assessDetailBox.ReadOnly   = $true
$assessDetailBox.BackColor  = [System.Drawing.Color]::FromArgb(250, 250, 255)
$assessDetailBox.Font       = New-Object System.Drawing.Font("Segoe UI", 9)
$assessDetailBox.Dock       = "Bottom"
$assessDetailBox.Height     = 160
$assessDetailBox.ScrollBars = "Vertical"
$tabAssess.Controls.Add($assessDetailBox)

$assessGrid.Add_SelectionChanged({
    $assessDetailBox.Clear()
    if ($assessGrid.SelectedRows.Count -gt 0) {
        $idx = $assessGrid.SelectedRows[0].Index
        if ($idx -ge 0 -and $idx -lt $script:AssessedGPOs.Count) {
            $gpo = $script:AssessedGPOs[$idx]
            $assessDetailBox.SelectionFont  = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
            $assessDetailBox.AppendText("$($gpo.Name)`n")
            $assessDetailBox.SelectionFont  = New-Object System.Drawing.Font("Segoe UI", 9)
            $assessDetailBox.AppendText("Domain: $($gpo.Domain)   |   Linked OUs: $($gpo.LinkedOUs -join ', ')`n`n")
            foreach ($section in $gpo.Sections) {
                $m = $script:GPOMapping[$section]
                if ($m) {
                    $statusStr = $m.Status.PadRight(14)
                    $assessDetailBox.SelectionFont  = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
                    $assessDetailBox.AppendText("[$statusStr] $section`n")
                    $assessDetailBox.SelectionFont  = New-Object System.Drawing.Font("Segoe UI", 9)
                    $assessDetailBox.AppendText("  Intune: $($m.IntuneProfile)`n")
                    $assessDetailBox.AppendText("  Note:   $($m.Notes)`n`n")
                }
            }
        }
    }
})

# ══════════════════════════════════════════════════════════════════════════════
# TAB 3 — MIGRATION
# ══════════════════════════════════════════════════════════════════════════════
$tabMigrate = New-Object System.Windows.Forms.TabPage
$tabMigrate.Text    = "  3. Migration  "
$tabMigrate.Padding = New-Object System.Windows.Forms.Padding(10)
$tabs.TabPages.Add($tabMigrate)

$migCtrlPanel = New-Object System.Windows.Forms.Panel
$migCtrlPanel.Dock   = "Top"
$migCtrlPanel.Height = 110
$tabMigrate.Controls.Add($migCtrlPanel)

# Graph connection group
$grpConnect = New-Object System.Windows.Forms.GroupBox
$grpConnect.Text     = "Microsoft Graph / Intune Connection"
$grpConnect.Location = New-Object System.Drawing.Point(5, 5)
$grpConnect.Size     = New-Object System.Drawing.Size(490, 95)
$grpConnect.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$migCtrlPanel.Controls.Add($grpConnect)

$lblTenantId = New-Object System.Windows.Forms.Label
$lblTenantId.Text     = "Tenant ID:"
$lblTenantId.Location = New-Object System.Drawing.Point(10, 25)
$lblTenantId.Size     = New-Object System.Drawing.Size(75, 22)
$grpConnect.Controls.Add($lblTenantId)

$txtTenantId = New-Object System.Windows.Forms.TextBox
$txtTenantId.Location    = New-Object System.Drawing.Point(90, 22)
$txtTenantId.Size        = New-Object System.Drawing.Size(280, 22)
$txtTenantId.PlaceholderText = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$grpConnect.Controls.Add($txtTenantId)

$btnConnect = New-Object System.Windows.Forms.Button
$btnConnect.Text      = "Connect"
$btnConnect.Location  = New-Object System.Drawing.Point(380, 20)
$btnConnect.Size      = New-Object System.Drawing.Size(90, 28)
$btnConnect.BackColor = [System.Drawing.Color]::FromArgb(46, 117, 182)
$btnConnect.ForeColor = [System.Drawing.Color]::White
$btnConnect.FlatStyle = "Flat"
$grpConnect.Controls.Add($btnConnect)

$lblConnStatus = New-Object System.Windows.Forms.Label
$lblConnStatus.Text      = "Not connected"
$lblConnStatus.Location  = New-Object System.Drawing.Point(10, 58)
$lblConnStatus.Size      = New-Object System.Drawing.Size(460, 22)
$lblConnStatus.ForeColor = [System.Drawing.Color]::DarkRed
$grpConnect.Controls.Add($lblConnStatus)

# Migration action group
$grpMigAction = New-Object System.Windows.Forms.GroupBox
$grpMigAction.Text     = "Migration Options"
$grpMigAction.Location = New-Object System.Drawing.Point(510, 5)
$grpMigAction.Size     = New-Object System.Drawing.Size(540, 95)
$grpMigAction.Font     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$migCtrlPanel.Controls.Add($grpMigAction)

$chkSupportedOnly = New-Object System.Windows.Forms.CheckBox
$chkSupportedOnly.Text     = "Migrate Supported GPOs only"
$chkSupportedOnly.Location = New-Object System.Drawing.Point(10, 22)
$chkSupportedOnly.Size     = New-Object System.Drawing.Size(220, 22)
$chkSupportedOnly.Checked  = $true
$grpMigAction.Controls.Add($chkSupportedOnly)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text     = "Dry-run (assess only, no changes)"
$chkDryRun.Location = New-Object System.Drawing.Point(240, 22)
$chkDryRun.Size     = New-Object System.Drawing.Size(240, 22)
$chkDryRun.Checked  = $true
$grpMigAction.Controls.Add($chkDryRun)

$btnMigrate = New-Object System.Windows.Forms.Button
$btnMigrate.Text      = "Start Migration"
$btnMigrate.Location  = New-Object System.Drawing.Point(10, 55)
$btnMigrate.Size      = New-Object System.Drawing.Size(150, 32)
$btnMigrate.BackColor = [System.Drawing.Color]::FromArgb(84, 130, 53)
$btnMigrate.ForeColor = [System.Drawing.Color]::White
$btnMigrate.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnMigrate.FlatStyle = "Flat"
$btnMigrate.Enabled   = $false
$grpMigAction.Controls.Add($btnMigrate)

$lblMigStatus = New-Object System.Windows.Forms.Label
$lblMigStatus.Text      = "Connect to Graph first, then run Assessment."
$lblMigStatus.Location  = New-Object System.Drawing.Point(175, 63)
$lblMigStatus.Size      = New-Object System.Drawing.Size(350, 22)
$lblMigStatus.ForeColor = [System.Drawing.Color]::DimGray
$grpMigAction.Controls.Add($lblMigStatus)

# Migration results list
$migListView = New-Object System.Windows.Forms.ListView
$migListView.View          = "Details"
$migListView.FullRowSelect = $true
$migListView.GridLines     = $true
$migListView.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
$migListView.Dock          = "Fill"
$tabMigrate.Controls.Add($migListView)

foreach ($col in @(
    @{ N = "GPO Name";             W = 280 },
    @{ N = "Sections";             W = 200 },
    @{ N = "Intune Profile Name";  W = 280 },
    @{ N = "Status";               W = 100 },
    @{ N = "Message";              W = 240 }
)) {
    $c = New-Object System.Windows.Forms.ColumnHeader
    $c.Text  = $col.N
    $c.Width = $col.W
    $migListView.Columns.Add($c) | Out-Null
}

$migLogBox = New-Object System.Windows.Forms.TextBox
$migLogBox.Multiline  = $true
$migLogBox.ScrollBars = "Vertical"
$migLogBox.ReadOnly   = $true
$migLogBox.BackColor  = [System.Drawing.Color]::FromArgb(15, 15, 30)
$migLogBox.ForeColor  = [System.Drawing.Color]::FromArgb(180, 255, 180)
$migLogBox.Font       = New-Object System.Drawing.Font("Consolas", 8)
$migLogBox.Dock       = "Bottom"
$migLogBox.Height     = 130
$tabMigrate.Controls.Add($migLogBox)

# ══════════════════════════════════════════════════════════════════════════════
# TAB 4 — REPORT
# ══════════════════════════════════════════════════════════════════════════════
$tabReport = New-Object System.Windows.Forms.TabPage
$tabReport.Text    = "  4. Report  "
$tabReport.Padding = New-Object System.Windows.Forms.Padding(10)
$tabs.TabPages.Add($tabReport)

$rptCtrlPanel = New-Object System.Windows.Forms.Panel
$rptCtrlPanel.Dock   = "Top"
$rptCtrlPanel.Height = 55
$tabReport.Controls.Add($rptCtrlPanel)

$btnExportHTML = New-Object System.Windows.Forms.Button
$btnExportHTML.Text      = "Export HTML Report"
$btnExportHTML.Location  = New-Object System.Drawing.Point(10, 10)
$btnExportHTML.Size      = New-Object System.Drawing.Size(165, 35)
$btnExportHTML.BackColor = [System.Drawing.Color]::FromArgb(46, 117, 182)
$btnExportHTML.ForeColor = [System.Drawing.Color]::White
$btnExportHTML.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnExportHTML.FlatStyle = "Flat"
$rptCtrlPanel.Controls.Add($btnExportHTML)

$btnExportCSV = New-Object System.Windows.Forms.Button
$btnExportCSV.Text      = "Export CSV Report"
$btnExportCSV.Location  = New-Object System.Drawing.Point(190, 10)
$btnExportCSV.Size      = New-Object System.Drawing.Size(155, 35)
$btnExportCSV.BackColor = [System.Drawing.Color]::FromArgb(68, 114, 196)
$btnExportCSV.ForeColor = [System.Drawing.Color]::White
$btnExportCSV.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnExportCSV.FlatStyle = "Flat"
$rptCtrlPanel.Controls.Add($btnExportCSV)

$btnOpenReport = New-Object System.Windows.Forms.Button
$btnOpenReport.Text      = "Open Last Report"
$btnOpenReport.Location  = New-Object System.Drawing.Point(360, 10)
$btnOpenReport.Size      = New-Object System.Drawing.Size(145, 35)
$btnOpenReport.BackColor = [System.Drawing.Color]::FromArgb(84, 130, 53)
$btnOpenReport.ForeColor = [System.Drawing.Color]::White
$btnOpenReport.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnOpenReport.FlatStyle = "Flat"
$rptCtrlPanel.Controls.Add($btnOpenReport)

$lblRptStatus = New-Object System.Windows.Forms.Label
$lblRptStatus.Text      = "Complete Discovery and Assessment first to generate a report."
$lblRptStatus.Location  = New-Object System.Drawing.Point(520, 20)
$lblRptStatus.Size      = New-Object System.Drawing.Size(540, 22)
$lblRptStatus.ForeColor = [System.Drawing.Color]::DimGray
$rptCtrlPanel.Controls.Add($lblRptStatus)

# Summary stats panel
$summaryPanel = New-Object System.Windows.Forms.Panel
$summaryPanel.Dock      = "Top"
$summaryPanel.Height    = 100
$summaryPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 244, 252)
$tabReport.Controls.Add($summaryPanel)

function New-StatCard {
    param([string]$Label, [string]$Value, [System.Drawing.Color]$Color, [int]$X)
    $card = New-Object System.Windows.Forms.Panel
    $card.Location  = New-Object System.Drawing.Point($X, 10)
    $card.Size      = New-Object System.Drawing.Size(150, 78)
    $card.BackColor = [System.Drawing.Color]::White
    $card.BorderStyle = "FixedSingle"

    $valLbl = New-Object System.Windows.Forms.Label
    $valLbl.Text      = $Value
    $valLbl.Name      = "val"
    $valLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
    $valLbl.ForeColor = $Color
    $valLbl.TextAlign = "MiddleCenter"
    $valLbl.Dock      = "Top"
    $valLbl.Height    = 50

    $lblLbl = New-Object System.Windows.Forms.Label
    $lblLbl.Text      = $Label
    $lblLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblLbl.ForeColor = [System.Drawing.Color]::DimGray
    $lblLbl.TextAlign = "MiddleCenter"
    $lblLbl.Dock      = "Fill"

    $card.Controls.Add($lblLbl)
    $card.Controls.Add($valLbl)
    return $card
}

$cardTotal    = New-StatCard -Label "Total GPOs"      -Value "0" -Color ([System.Drawing.Color]::FromArgb(31,56,100))  -X 10
$cardSupported= New-StatCard -Label "Fully Supported" -Value "0" -Color ([System.Drawing.Color]::FromArgb(55,86,35))   -X 170
$cardPartial  = New-StatCard -Label "Partial Support" -Value "0" -Color ([System.Drawing.Color]::FromArgb(125,106,8))  -X 330
$cardNot      = New-StatCard -Label "Not Supported"   -Value "0" -Color ([System.Drawing.Color]::FromArgb(156,0,6))    -X 490
$cardScore    = New-StatCard -Label "Avg. Readiness"  -Value "0%" -Color ([System.Drawing.Color]::FromArgb(31,56,100)) -X 650
$cardMigrated = New-StatCard -Label "Migrated"        -Value "0" -Color ([System.Drawing.Color]::FromArgb(55,86,35))   -X 810
$summaryPanel.Controls.AddRange(@($cardTotal, $cardSupported, $cardPartial, $cardNot, $cardScore, $cardMigrated))

function Update-ReportSummary {
    $total     = $script:AssessedGPOs.Count
    $supported = ($script:AssessedGPOs | Where-Object { $_.OverallStatus -eq "Supported" }).Count
    $partial   = ($script:AssessedGPOs | Where-Object { $_.OverallStatus -eq "Partial" }).Count
    $notSup    = ($script:AssessedGPOs | Where-Object { $_.OverallStatus -eq "NotSupported" }).Count
    $avgScore  = if ($total -gt 0) { [math]::Round(($script:AssessedGPOs | Measure-Object -Property Score -Average).Average) } else { 0 }
    $migrated  = $script:MigrationResults.Count

    ($cardTotal.Controls    | Where-Object { $_.Name -eq "val" }).Text = "$total"
    ($cardSupported.Controls| Where-Object { $_.Name -eq "val" }).Text = "$supported"
    ($cardPartial.Controls  | Where-Object { $_.Name -eq "val" }).Text = "$partial"
    ($cardNot.Controls      | Where-Object { $_.Name -eq "val" }).Text = "$notSup"
    ($cardScore.Controls    | Where-Object { $_.Name -eq "val" }).Text = "$avgScore%"
    ($cardMigrated.Controls | Where-Object { $_.Name -eq "val" }).Text = "$migrated"
}

# Report detail grid
$rptGrid = New-Object System.Windows.Forms.DataGridView
$rptGrid.Dock                    = "Fill"
$rptGrid.ReadOnly                = $true
$rptGrid.AllowUserToAddRows      = $false
$rptGrid.AllowUserToDeleteRows   = $false
$rptGrid.RowHeadersVisible       = $false
$rptGrid.SelectionMode           = "FullRowSelect"
$rptGrid.AutoSizeColumnsMode     = "Fill"
$rptGrid.Font                    = New-Object System.Drawing.Font("Segoe UI", 9)
$rptGrid.ColumnHeadersDefaultCellStyle.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$rptGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(31, 56, 100)
$rptGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$rptGrid.EnableHeadersVisualStyles = $false
$tabReport.Controls.Add($rptGrid)

foreach ($col in @(
    @{ N = "GPO Name";        P = "Name";            W = 25 },
    @{ N = "Domain";          P = "Domain";           W = 12 },
    @{ N = "Overall Status";  P = "OverallStatus";    W = 12 },
    @{ N = "Score";           P = "Score";            W = 8  },
    @{ N = "Sections";        P = "SectionsSummary";  W = 30 },
    @{ N = "Recommendation";  P = "Recommendation";   W = 23 }
)) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.HeaderText       = $col.N
    $c.DataPropertyName = $col.P
    $c.FillWeight       = $col.W
    $rptGrid.Columns.Add($c) | Out-Null
}

# ──────────────────────────────────────────────────────────────────────────────
# Event handlers
# ──────────────────────────────────────────────────────────────────────────────

# DISCOVERY ───────────────────────────────────────────────────────────────────
$btnDiscover.Add_Click({
    if (-not (Test-GroupPolicyModule)) {
        [System.Windows.Forms.MessageBox]::Show(
            "The GroupPolicy PowerShell module was not found.`n`nPlease install RSAT: Group Policy Management Tools.`n`n  Windows 10/11: Settings → Apps → Optional Features → RSAT`n  Server: Add-WindowsFeature GPMC",
            "Missing Module", "OK", "Warning")
        return
    }

    $domain = $txtDomain.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($domain)) { $domain = $env:USERDNSDOMAIN }

    $btnDiscover.Enabled   = $false
    $btnExportXMLs.Enabled = $false
    $gpoListView.Items.Clear()
    $script:DiscoveredGPOs = @()
    $discLogBox.Clear()
    $lblDiscStatus.Text = "Discovering GPOs in $domain ..."

    Write-Log $discLogBox "Starting GPO discovery in domain: $domain"

    try {
        Import-Module GroupPolicy -ErrorAction Stop
        Write-Log $discLogBox "GroupPolicy module loaded."

        $params = @{ Domain = $domain; ErrorAction = "Stop" }
        if (-not [string]::IsNullOrWhiteSpace($txtOU.Text)) {
            $params.SearchBase = $txtOU.Text.Trim()
        }

        $allGPOs = Get-GPO -All @params
        Write-Log $discLogBox "Found $($allGPOs.Count) GPO(s). Retrieving details..."

        $gpoProgressBar = New-Object System.Windows.Forms.ProgressBar
        $gpoProgressBar.Dock  = "Bottom"
        $gpoProgressBar.Style = "Continuous"
        $tabDiscover.Controls.Add($gpoProgressBar)

        $idx = 0
        foreach ($gpo in $allGPOs) {
            $idx++
            $gpoProgressBar.Value = [math]::Round(($idx / $allGPOs.Count) * 100)
            Write-Log $discLogBox "  Processing: $($gpo.DisplayName)"

            # Get linked OUs
            $linkedOUs = @()
            try {
                $report    = Get-GPOReport -Guid $gpo.Id -ReportType Xml -Domain $domain
                $reportXml = [xml]$report
                $links     = $reportXml.GPO.LinksTo
                if ($links) {
                    $linkedOUs = @($links | ForEach-Object { $_.SOMPath })
                }
            } catch {
                $linkedOUs = @("(unable to retrieve)")
            }

            $obj = [PSCustomObject]@{
                Name              = $gpo.DisplayName
                Guid              = $gpo.Id.ToString()
                Domain            = $domain
                LinkedOUs         = $linkedOUs
                ComputerEnabled   = $gpo.GpoStatus -ne "UserSettingsDisabled" -and $gpo.GpoStatus -ne "AllSettingsDisabled"
                UserEnabled       = $gpo.GpoStatus -ne "ComputerSettingsDisabled" -and $gpo.GpoStatus -ne "AllSettingsDisabled"
                LastModified      = $gpo.ModificationTime
                XmlReport         = $report
                XmlPath           = ""
            }
            $script:DiscoveredGPOs += $obj

            $lvi = New-Object System.Windows.Forms.ListViewItem($gpo.DisplayName)
            $lvi.SubItems.Add($domain) | Out-Null
            $lvi.SubItems.Add(($linkedOUs -join " | ")) | Out-Null
            $lvi.SubItems.Add($(if ($obj.ComputerEnabled) { "Enabled" } else { "Disabled" })) | Out-Null
            $lvi.SubItems.Add($(if ($obj.UserEnabled) { "Enabled" } else { "Disabled" })) | Out-Null
            $lvi.SubItems.Add($gpo.ModificationTime.ToString("yyyy-MM-dd HH:mm")) | Out-Null
            $lvi.Checked = $true
            $gpoListView.Items.Add($lvi) | Out-Null
            [System.Windows.Forms.Application]::DoEvents()
        }

        $tabDiscover.Controls.Remove($gpoProgressBar)
        Write-Log $discLogBox "Discovery complete. $($script:DiscoveredGPOs.Count) GPO(s) found."
        $lblDiscStatus.Text    = "Discovered $($script:DiscoveredGPOs.Count) GPOs. Check items to select, then go to Assessment tab."
        $btnExportXMLs.Enabled = $true

    } catch {
        Write-Log $discLogBox "ERROR: $($_.Exception.Message)" "ERROR"
        $lblDiscStatus.Text = "Error during discovery. See log below."
        [System.Windows.Forms.MessageBox]::Show("Discovery failed:`n$($_.Exception.Message)", "Error", "OK", "Error")
    } finally {
        $btnDiscover.Enabled = $true
    }
})

# Import GPO XML (manual)
$btnImportXML.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title       = "Select GPO XML Report(s)"
    $ofd.Filter      = "XML Files (*.xml)|*.xml|All Files (*.*)|*.*"
    $ofd.Multiselect = $true
    if ($ofd.ShowDialog() -ne "OK") { return }

    $discLogBox.Clear()
    $gpoListView.Items.Clear()
    $script:DiscoveredGPOs = @()

    foreach ($file in $ofd.FileNames) {
        try {
            $rawXml   = Get-Content $file -Raw
            $xmlDoc   = [xml]$rawXml
            $gpoName  = $xmlDoc.GPO.Name
            if ([string]::IsNullOrWhiteSpace($gpoName)) { $gpoName = [System.IO.Path]::GetFileNameWithoutExtension($file) }
            $domain   = if ($xmlDoc.GPO.Identifier.Domain) { $xmlDoc.GPO.Identifier.Domain."#text" } else { "Imported" }
            $links    = @($xmlDoc.GPO.LinksTo | ForEach-Object { $_.SOMPath })

            $obj = [PSCustomObject]@{
                Name            = $gpoName
                Guid            = $xmlDoc.GPO.Identifier.Identifier."#text"
                Domain          = $domain
                LinkedOUs       = $links
                ComputerEnabled = $true
                UserEnabled     = $true
                LastModified    = (Get-Item $file).LastWriteTime
                XmlReport       = $rawXml
                XmlPath         = $file
            }
            $script:DiscoveredGPOs += $obj

            $lvi = New-Object System.Windows.Forms.ListViewItem($gpoName)
            $lvi.SubItems.Add($domain) | Out-Null
            $lvi.SubItems.Add(($links -join " | ")) | Out-Null
            $lvi.SubItems.Add("Imported") | Out-Null
            $lvi.SubItems.Add("Imported") | Out-Null
            $lvi.SubItems.Add((Get-Item $file).LastWriteTime.ToString("yyyy-MM-dd HH:mm")) | Out-Null
            $lvi.Checked = $true
            $gpoListView.Items.Add($lvi) | Out-Null
            Write-Log $discLogBox "Imported: $gpoName ($file)"
        } catch {
            Write-Log $discLogBox "ERROR importing $file`: $($_.Exception.Message)" "ERROR"
        }
    }

    $btnExportXMLs.Enabled = ($script:DiscoveredGPOs.Count -gt 0)
    $lblDiscStatus.Text = "Imported $($script:DiscoveredGPOs.Count) GPO XML file(s). Proceed to Assessment."
})

# Export selected XMLs
$btnExportXMLs.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select folder to save GPO XML reports"
    if ($fbd.ShowDialog() -ne "OK") { return }

    $outDir = $fbd.SelectedPath
    $saved  = 0

    for ($i = 0; $i -lt $gpoListView.Items.Count; $i++) {
        if ($gpoListView.Items[$i].Checked -and $i -lt $script:DiscoveredGPOs.Count) {
            $gpo  = $script:DiscoveredGPOs[$i]
            $safe = $gpo.Name -replace '[\\/:*?"<>|]', '_'
            $path = [System.IO.Path]::Combine($outDir, "$safe.xml")
            $gpo.XmlReport | Out-File -FilePath $path -Encoding UTF8
            $gpo.XmlPath = $path
            $saved++
            Write-Log $discLogBox "Saved: $path"
        }
    }

    Write-Log $discLogBox "$saved XML file(s) exported to $outDir"
    [System.Windows.Forms.MessageBox]::Show("$saved GPO XML file(s) saved to:`n$outDir", "Export Complete", "OK", "Information")
})

# ASSESSMENT ──────────────────────────────────────────────────────────────────
function Invoke-Assessment {
    param([System.Collections.Generic.List[PSCustomObject]]$GPOs)

    $script:AssessedGPOs = @()
    $assessGrid.DataSource = $null
    $dt = New-Object System.Data.DataTable

    foreach ($col in @("Name","Domain","SectionsSummary","OverallStatus","Score","Recommendation")) {
        $dt.Columns.Add($col) | Out-Null
    }

    $lblAssessStatus.Text = "Assessing $($GPOs.Count) GPO(s)..."

    foreach ($gpo in $GPOs) {
        try {
            $xmlDoc   = [xml]$gpo.XmlReport
            $sections = Get-GPOSettingSections -GPOXml $xmlDoc

            $statusCounts = @{ Supported = 0; Partial = 0; NotSupported = 0; Unknown = 0 }
            foreach ($s in $sections) {
                $m = $script:GPOMapping[$s]
                if ($m) { $statusCounts[$m.Status]++ } else { $statusCounts["Unknown"]++ }
            }

            $overallStatus = if ($statusCounts.NotSupported -gt 0 -and $statusCounts.Supported -eq 0 -and $statusCounts.Partial -eq 0) {
                "NotSupported"
            } elseif ($statusCounts.NotSupported -gt 0 -or $statusCounts.Partial -gt 0) {
                "Partial"
            } elseif ($statusCounts.Supported -gt 0) {
                "Supported"
            } else { "Unknown" }

            $score = Get-MigrationScore -Sections $sections

            $recommendation = switch ($overallStatus) {
                "Supported"    { "Ready for direct Intune migration via Settings Catalog / Endpoint Security." }
                "Partial"      { "Partially migratable. Review unsupported sections; consider scripts for gaps." }
                "NotSupported" { "Cannot be directly migrated. Evaluate alternative controls (OneDrive KFM, scripts, etc.)." }
                default        { "Manual review required." }
            }

            $assessed = [PSCustomObject]@{
                Name            = $gpo.Name
                Domain          = $gpo.Domain
                LinkedOUs       = $gpo.LinkedOUs
                Sections        = $sections
                SectionsSummary = $sections -join ", "
                OverallStatus   = $overallStatus
                Score           = $score
                Recommendation  = $recommendation
                Guid            = $gpo.Guid
            }
            $script:AssessedGPOs += $assessed

            $row = $dt.NewRow()
            $row["Name"]            = $gpo.Name
            $row["Domain"]          = $gpo.Domain
            $row["SectionsSummary"] = $sections -join ", "
            $row["OverallStatus"]   = $overallStatus
            $row["Score"]           = $score
            $row["Recommendation"]  = $recommendation
            $dt.Rows.Add($row) | Out-Null

        } catch {
            Write-Log $discLogBox "ERROR assessing $($gpo.Name): $($_.Exception.Message)" "ERROR"
        }
    }

    $assessGrid.DataSource = $dt

    # Color rows by status
    $assessGrid.Add_CellFormatting({
        param($sender, $e)
        if ($e.RowIndex -ge 0 -and $e.RowIndex -lt $script:AssessedGPOs.Count) {
            $status = $script:AssessedGPOs[$e.RowIndex].OverallStatus
            $color  = $script:StatusColors[$status]
            if ($color -and $assessGrid.Columns[$e.ColumnIndex].DataPropertyName -eq "OverallStatus") {
                $e.CellStyle.BackColor = $color
                $e.CellStyle.ForeColor = [System.Drawing.Color]::Black
            }
        }
    })

    $lblAssessStatus.Text = "Assessment complete: $($script:AssessedGPOs.Count) GPO(s) assessed. See Migration tab to proceed."
    Update-ReportSummary

    # Populate report grid
    $rptGrid.DataSource = $dt.Copy()
    $rptGrid.Add_CellFormatting({
        param($sender, $e)
        if ($e.RowIndex -ge 0 -and $e.RowIndex -lt $script:AssessedGPOs.Count) {
            $status = $script:AssessedGPOs[$e.RowIndex].OverallStatus
            $color  = $script:StatusColors[$status]
            if ($color -and $rptGrid.Columns[$e.ColumnIndex].DataPropertyName -eq "OverallStatus") {
                $e.CellStyle.BackColor = $color
                $e.CellStyle.ForeColor = [System.Drawing.Color]::Black
            }
        }
    })
}

$btnAssess.Add_Click({
    $selected = [System.Collections.Generic.List[PSCustomObject]]::new()
    for ($i = 0; $i -lt $gpoListView.Items.Count; $i++) {
        if ($gpoListView.Items[$i].Checked -and $i -lt $script:DiscoveredGPOs.Count) {
            $selected.Add($script:DiscoveredGPOs[$i])
        }
    }
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No GPOs are checked in the Discovery tab.", "Nothing Selected", "OK", "Warning")
        return
    }
    Invoke-Assessment -GPOs $selected
})

$btnAssessAll.Add_Click({
    if ($script:DiscoveredGPOs.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Run Discovery first.", "No GPOs", "OK", "Warning")
        return
    }
    $all = [System.Collections.Generic.List[PSCustomObject]]::new()
    $script:DiscoveredGPOs | ForEach-Object { $all.Add($_) }
    Invoke-Assessment -GPOs $all
})

# MIGRATION ───────────────────────────────────────────────────────────────────
$btnConnect.Add_Click({
    if (-not (Test-GraphModules)) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Required Graph modules are not installed:`n  Microsoft.Graph.Authentication`n  Microsoft.Graph.DeviceManagement`n`nInstall them now?",
            "Missing Modules", "YesNo", "Question")
        if ($result -eq "Yes") {
            Write-Log $migLogBox "Installing Microsoft.Graph modules..."
            try {
                Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -ErrorAction Stop
                Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser -Force -ErrorAction Stop
                Write-Log $migLogBox "Modules installed. Please retry connection."
            } catch {
                Write-Log $migLogBox "Install failed: $($_.Exception.Message)" "ERROR"
            }
        }
        return
    }

    $tenantId = $txtTenantId.Text.Trim()
    Write-Log $migLogBox "Connecting to Microsoft Graph (Intune)..."
    $lblConnStatus.Text = "Connecting..."

    try {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        $connectParams = @{
            Scopes = @(
                "DeviceManagementConfiguration.ReadWrite.All",
                "DeviceManagementManagedDevices.ReadWrite.All",
                "DeviceManagementApps.ReadWrite.All"
            )
        }
        if (-not [string]::IsNullOrWhiteSpace($tenantId)) {
            $connectParams.TenantId = $tenantId
        }
        Connect-MgGraph @connectParams -ErrorAction Stop

        $ctx = Get-MgContext
        $script:GraphConnected = $true
        $lblConnStatus.Text      = "Connected as: $($ctx.Account) | Tenant: $($ctx.TenantId)"
        $lblConnStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $btnMigrate.Enabled      = $true
        $lblMigStatus.Text       = "Ready. Review options and click Start Migration."
        Write-Log $migLogBox "Connected to Microsoft Graph as $($ctx.Account)"
    } catch {
        $lblConnStatus.Text      = "Connection failed: $($_.Exception.Message)"
        $lblConnStatus.ForeColor = [System.Drawing.Color]::DarkRed
        Write-Log $migLogBox "Connection failed: $($_.Exception.Message)" "ERROR"
    }
})

$btnMigrate.Add_Click({
    if ($script:AssessedGPOs.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Run Assessment first.", "No Assessment Data", "OK", "Warning")
        return
    }

    $isDryRun      = $chkDryRun.Checked
    $supportedOnly = $chkSupportedOnly.Checked

    $toMigrate = $script:AssessedGPOs | Where-Object {
        if ($supportedOnly) { $_.OverallStatus -eq "Supported" }
        else                { $_.OverallStatus -ne "NotSupported" }
    }

    if ($toMigrate.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No eligible GPOs to migrate with current filter settings.", "Nothing to Migrate", "OK", "Information")
        return
    }

    $modeLabel = if ($isDryRun) { "[DRY-RUN] " } else { "" }
    Write-Log $migLogBox "${modeLabel}Starting migration of $($toMigrate.Count) GPO(s)..."
    $btnMigrate.Enabled  = $false
    $script:MigrationResults = @()
    $migListView.Items.Clear()

    foreach ($gpo in $toMigrate) {
        $profileName  = "GPO-Migrated - $($gpo.Name)"
        $description  = "Migrated from GPO: $($gpo.Name) | Domain: $($gpo.Domain) | Score: $($gpo.Score)%"
        $status       = "Success"
        $message      = ""

        try {
            if ($isDryRun) {
                $message = "Dry-run: Would create profile '$profileName' (sections: $($gpo.SectionsSummary))"
                Write-Log $migLogBox "[DRY-RUN] $($gpo.Name) → $profileName"
            } else {
                if (-not $script:GraphConnected) { throw "Not connected to Microsoft Graph." }
                $profile = New-IntuneConfigurationProfile -DisplayName $profileName -Description $description
                $message = "Profile created: ID=$($profile.Id)"
                Write-Log $migLogBox "MIGRATED: $($gpo.Name) → $profileName (ID: $($profile.Id))"
            }
        } catch {
            $status  = "Failed"
            $message = $_.Exception.Message
            Write-Log $migLogBox "FAILED: $($gpo.Name) — $message" "ERROR"
        }

        $result = [PSCustomObject]@{
            GPOName          = $gpo.Name
            IntuneProfileName = $profileName
            Status           = $status
            Message          = $message
        }
        $script:MigrationResults += $result

        $lvi = New-Object System.Windows.Forms.ListViewItem($gpo.Name)
        $lvi.SubItems.Add($gpo.SectionsSummary) | Out-Null
        $lvi.SubItems.Add($profileName) | Out-Null
        $lvi.SubItems.Add($status) | Out-Null
        $lvi.SubItems.Add($message) | Out-Null
        if ($status -eq "Success") {
            $lvi.BackColor = [System.Drawing.Color]::FromArgb(198, 239, 206)
        } else {
            $lvi.BackColor = [System.Drawing.Color]::FromArgb(255, 199, 206)
        }
        $migListView.Items.Add($lvi) | Out-Null
        [System.Windows.Forms.Application]::DoEvents()
    }

    Update-ReportSummary
    $btnMigrate.Enabled = $true
    $succeeded = ($script:MigrationResults | Where-Object { $_.Status -eq "Success" }).Count
    $failed    = ($script:MigrationResults | Where-Object { $_.Status -eq "Failed" }).Count
    $modeNote  = if ($isDryRun) { " (dry-run — no actual changes made)" } else { "" }
    Write-Log $migLogBox "Migration complete$modeNote. Succeeded: $succeeded | Failed: $failed"
    $lblMigStatus.Text = "Complete$modeNote. Succeeded: $succeeded | Failed: $failed. See Report tab."
})

# REPORT ──────────────────────────────────────────────────────────────────────
$script:LastReportPath = ""

$btnExportHTML.Add_Click({
    if ($script:AssessedGPOs.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No assessment data. Run Discovery and Assessment first.", "No Data", "OK", "Warning")
        return
    }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title      = "Save HTML Report"
    $sfd.Filter     = "HTML Files (*.html)|*.html"
    $sfd.FileName   = "GPO-IntuneMigration-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    if ($sfd.ShowDialog() -ne "OK") { return }

    try {
        Export-HTMLReport -OutputPath $sfd.FileName
        $script:LastReportPath = $sfd.FileName
        $lblRptStatus.Text = "HTML report saved: $($sfd.FileName)"
        [System.Windows.Forms.MessageBox]::Show("Report saved to:`n$($sfd.FileName)`n`nOpen it in your browser to view.", "Report Saved", "OK", "Information")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to save report:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
})

$btnExportCSV.Add_Click({
    if ($script:AssessedGPOs.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No assessment data. Run Discovery and Assessment first.", "No Data", "OK", "Warning")
        return
    }

    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title    = "Save CSV Report"
    $sfd.Filter   = "CSV Files (*.csv)|*.csv"
    $sfd.FileName = "GPO-IntuneMigration-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    if ($sfd.ShowDialog() -ne "OK") { return }

    try {
        $script:AssessedGPOs | Select-Object Name, Domain,
            @{N="LinkedOUs"; E={ $_.LinkedOUs -join " | " }},
            OverallStatus, Score, SectionsSummary, Recommendation |
            Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
        $lblRptStatus.Text = "CSV report saved: $($sfd.FileName)"
        [System.Windows.Forms.MessageBox]::Show("CSV saved to:`n$($sfd.FileName)", "Report Saved", "OK", "Information")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to save CSV:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
})

$btnOpenReport.Add_Click({
    if ([string]::IsNullOrWhiteSpace($script:LastReportPath) -or -not (Test-Path $script:LastReportPath)) {
        [System.Windows.Forms.MessageBox]::Show("No HTML report has been exported yet.", "No Report", "OK", "Information")
        return
    }
    Start-Process $script:LastReportPath
})

# ──────────────────────────────────────────────────────────────────────────────
# Startup
# ──────────────────────────────────────────────────────────────────────────────
Write-Log $discLogBox "GPO to Intune Migration Tool loaded."
Write-Log $discLogBox "Step 1: Enter your domain and click 'Discover GPOs'."
Write-Log $discLogBox "Step 2: Go to Assessment tab and assess migration readiness."
Write-Log $discLogBox "Step 3: Connect to Microsoft Graph and migrate supported GPOs."
Write-Log $discLogBox "Step 4: Export an HTML or CSV report of the full migration."

Write-Host "`n=== GPO TO MICROSOFT INTUNE MIGRATION TOOL ===" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "GUI loaded. Follow the four tabs: Discovery → Assessment → Migration → Report." -ForegroundColor Cyan

$form.ShowDialog() | Out-Null
