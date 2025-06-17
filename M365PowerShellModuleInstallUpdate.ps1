<#
.SYNOPSIS
    Microsoft 365 PowerShell Module Install/Update GUI

.DESCRIPTION
    A comprehensive PowerShell GUI application for managing and updating Microsoft 365 PowerShell modules.
    This tool provides an intuitive interface to check for updates, install modules, and view current versions
    of essential Microsoft cloud administration modules including Exchange Online, SharePoint Online, Teams,
    Microsoft Graph, Azure PowerShell, Entra ID, Power Platform, and more.

.FEATURES
    - Check for module updates with version comparison
    - Install or update selected modules with configurable options
    - View currently installed module versions and publication dates
    - Support for both CurrentUser and AllUsers installation scopes
    - Force reinstall and prerelease options
    - Real-time progress tracking with GUI and console output
    - Color-coded console output for easy status identification
    - Comprehensive error handling and logging

.SUPPORTED MODULES
    - Exchange Online Management (EXO)
    - SharePoint Online (SPO)
    - Microsoft Teams
    - Microsoft Graph (Complete SDK)
    - Microsoft Entra ID Directory Management
    - Azure PowerShell (Az modules)
    - Power Platform Administration
    - PnP PowerShell
    - Legacy Azure AD modules (MSOnline, AzureAD)
    - Secret Management modules
    - And more...

.REQUIREMENTS
    - PowerShell 5.1 or later
    - Internet connection for module downloads
    - Administrator privileges (for AllUsers scope installation)
    - PowerShellGet module (pre-installed with PowerShell 5.1+)

.USAGE
    1. Run the script: .\M365ModuleUpdater.ps1
    2. Select desired modules from the checklist
    3. Configure installation options as needed
    4. Use buttons to check updates, install modules, or view current versions
    5. Monitor progress in both GUI and PowerShell console

.NOTES
    File Name      : M365ModuleUpdater.ps1
    Author         : Gulab Prasad
    Website        : https://gulabprasad.com
    Created        : 2025
    Version        : 1.0
    
.COPYRIGHT
    Copyright (c) 2025 Gulab Prasad. All Rights Reserved.
    
    This script is provided "AS IS" without warranty of any kind, either express or implied,
    including but not limited to the implied warranties of merchantability and/or fitness
    for a particular purpose.
    
    The author shall not be liable for any damages whatsoever (including, without limitation,
    damages for loss of business profits, business interruption, loss of business information,
    or other pecuniary loss) arising out of the use of or inability to use this script.
    
    For more information and updates, visit: https://gulabprasad.com

.LICENSE
    MIT License
    
    Copyright (c) 2025 Gulab Prasad
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

.DISCLAIMER
    This tool is designed for system administrators and IT professionals. Users are responsible
    for testing in non-production environments before deploying to production systems.
    Always ensure you have proper backups and change management procedures in place.

#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Microsoft 365 PowerShell Module Install/Update"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Title label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Microsoft 365 PowerShell Module Install/Update"
$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
$titleLabel.Size = New-Object System.Drawing.Size(550, 30)
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::DarkBlue
$form.Controls.Add($titleLabel)

# Website link
$websiteLabel = New-Object System.Windows.Forms.LinkLabel
$websiteLabel.Text = "https://gulabprasad.com"
$websiteLabel.Location = New-Object System.Drawing.Point(580, 25)
$websiteLabel.Size = New-Object System.Drawing.Size(200, 20)
$websiteLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$websiteLabel.LinkColor = [System.Drawing.Color]::Blue
$websiteLabel.VisitedLinkColor = [System.Drawing.Color]::Purple
$websiteLabel.ActiveLinkColor = [System.Drawing.Color]::Red
$websiteLabel.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
$websiteLabel.Add_LinkClicked({
    try {
        Start-Process "https://gulabprasad.com"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Unable to open web browser. Please manually visit: https://gulabprasad.com", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$form.Controls.Add($websiteLabel)

# Author label
$authorLabel = New-Object System.Windows.Forms.Label
$authorLabel.Text = "Created by Gulab Prasad"
$authorLabel.Location = New-Object System.Drawing.Point(580, 45)
$authorLabel.Size = New-Object System.Drawing.Size(200, 15)
$authorLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$authorLabel.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($authorLabel)

# Module list (CheckedListBox)
$moduleLabel = New-Object System.Windows.Forms.Label
$moduleLabel.Text = "Select modules to update:"
$moduleLabel.Location = New-Object System.Drawing.Point(20, 60)
$moduleLabel.Size = New-Object System.Drawing.Size(200, 20)
$moduleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($moduleLabel)

$moduleList = New-Object System.Windows.Forms.CheckedListBox
$moduleList.Location = New-Object System.Drawing.Point(20, 85)
$moduleList.Size = New-Object System.Drawing.Size(350, 200)
$moduleList.CheckOnClick = $true
$moduleList.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Define modules with their proper names
$modules = @{
    "ExchangeOnlineManagement" = "Exchange Online (EXO)"
    "Microsoft.Online.SharePoint.PowerShell" = "SharePoint Online (SPO)"
    "MicrosoftTeams" = "Microsoft Teams"
    "Microsoft.Graph" = "Microsoft Graph (Complete SDK)"
    "Microsoft.Graph.Identity.DirectoryManagement" = "Entra ID Directory Management"
    "Az" = "Azure PowerShell (Complete Az Module)"
    "Az.Accounts" = "Azure Accounts (Core)"
    "Az.Resources" = "Azure Resources"
    "Az.KeyVault" = "Azure Key Vault"
    "Az.Storage" = "Azure Storage"
    "Az.Security" = "Azure Security Center"
    "MSOnline" = "Azure AD (MSOnline) - Legacy"
    "AzureAD" = "Azure AD (AzureAD) - Legacy"
    "Microsoft.Graph.Security" = "Microsoft Graph Security"
    "Microsoft.Graph.DeviceManagement" = "Intune Device Management"
    "MSAL.PS" = "Microsoft Authentication Library"
    "Microsoft.PowerApps.Administration.PowerShell" = "Power Platform Admin"
    "Microsoft.PowerApps.PowerShell" = "Power Platform"
    "Microsoft.Xrm.Data.PowerShell" = "Dynamics 365"
    "PnP.PowerShell" = "PnP PowerShell (SharePoint/M365)"
    "Microsoft.PowerShell.SecretManagement" = "Secret Management"
    "Microsoft.PowerShell.SecretStore" = "Secret Store"
}

foreach ($module in $modules.GetEnumerator()) {
    $moduleList.Items.Add("$($module.Value) ($($module.Key))")
}

$form.Controls.Add($moduleList)

# Buttons frame
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(20, 300)
$buttonPanel.Size = New-Object System.Drawing.Size(410, 80)
$form.Controls.Add($buttonPanel)

# Select All button
$selectAllBtn = New-Object System.Windows.Forms.Button
$selectAllBtn.Text = "Select All"
$selectAllBtn.Location = New-Object System.Drawing.Point(0, 0)
$selectAllBtn.Size = New-Object System.Drawing.Size(80, 30)
$selectAllBtn.BackColor = [System.Drawing.Color]::LightBlue
$buttonPanel.Controls.Add($selectAllBtn)

# Clear All button
$clearAllBtn = New-Object System.Windows.Forms.Button
$clearAllBtn.Text = "Clear All"
$clearAllBtn.Location = New-Object System.Drawing.Point(90, 0)
$clearAllBtn.Size = New-Object System.Drawing.Size(80, 30)
$clearAllBtn.BackColor = [System.Drawing.Color]::LightCoral
$buttonPanel.Controls.Add($clearAllBtn)

# Check Updates button
$checkBtn = New-Object System.Windows.Forms.Button
$checkBtn.Text = "Check for Updates"
$checkBtn.Location = New-Object System.Drawing.Point(0, 40)
$checkBtn.Size = New-Object System.Drawing.Size(120, 35)
$checkBtn.BackColor = [System.Drawing.Color]::LightGreen
$checkBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$buttonPanel.Controls.Add($checkBtn)

# Install Updates button
$installBtn = New-Object System.Windows.Forms.Button
$installBtn.Text = "Install/Update Modules"
$installBtn.Location = New-Object System.Drawing.Point(130, 40)
$installBtn.Size = New-Object System.Drawing.Size(120, 35)
$installBtn.BackColor = [System.Drawing.Color]::Orange
$installBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$installBtn.Enabled = $false
$installBtn.Add_MouseHover({
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($installBtn, "Installs new modules and updates existing ones")
})
$buttonPanel.Controls.Add($installBtn)

# Check Current Versions button
$currentVersionBtn = New-Object System.Windows.Forms.Button
$currentVersionBtn.Text = "Check Current Versions"
$currentVersionBtn.Location = New-Object System.Drawing.Point(260, 40)
$currentVersionBtn.Size = New-Object System.Drawing.Size(140, 35)
$currentVersionBtn.BackColor = [System.Drawing.Color]::LightSteelBlue
$currentVersionBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$buttonPanel.Controls.Add($currentVersionBtn)

# Options GroupBox
$optionsGroup = New-Object System.Windows.Forms.GroupBox
$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Text = "If you see 'currently in use' warnings, restart PowerShell after installation to complete updates."
$infoLabel.Location = New-Object System.Drawing.Point(400, 250)
$infoLabel.Size = New-Object System.Drawing.Size(350, 40)
$infoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$infoLabel.ForeColor = [System.Drawing.Color]::DarkOrange
$infoLabel.BackColor = [System.Drawing.Color]::LightYellow
$infoLabel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($infoLabel)
$optionsGroup.Text = "Options"
$optionsGroup.Location = New-Object System.Drawing.Point(400, 85)
$optionsGroup.Size = New-Object System.Drawing.Size(350, 150)
$optionsGroup.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($optionsGroup)

# Force update checkbox
$forceCheckbox = New-Object System.Windows.Forms.CheckBox
$forceCheckbox.Text = "Force reinstall (even if up to date)"
$forceCheckbox.Location = New-Object System.Drawing.Point(15, 25)
$forceCheckbox.Size = New-Object System.Drawing.Size(300, 20)
$forceCheckbox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$optionsGroup.Controls.Add($forceCheckbox)

# Allow prerelease checkbox
$prereleaseCheckbox = New-Object System.Windows.Forms.CheckBox
$prereleaseCheckbox.Text = "Include prerelease versions"
$prereleaseCheckbox.Location = New-Object System.Drawing.Point(15, 50)
$prereleaseCheckbox.Size = New-Object System.Drawing.Size(300, 20)
$prereleaseCheckbox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$optionsGroup.Controls.Add($prereleaseCheckbox)

# Skip publisher check
$skipPublisherCheckbox = New-Object System.Windows.Forms.CheckBox
$skipPublisherCheckbox.Text = "Skip publisher check (trust all publishers)"
$skipPublisherCheckbox.Location = New-Object System.Drawing.Point(15, 75)
$skipPublisherCheckbox.Size = New-Object System.Drawing.Size(300, 20)
$skipPublisherCheckbox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$optionsGroup.Controls.Add($skipPublisherCheckbox)

# Scope selection
$scopeLabel = New-Object System.Windows.Forms.Label
$scopeLabel.Text = "Installation Scope:"
$scopeLabel.Location = New-Object System.Drawing.Point(15, 100)
$scopeLabel.Size = New-Object System.Drawing.Size(120, 20)
$scopeLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$optionsGroup.Controls.Add($scopeLabel)

$scopeCombo = New-Object System.Windows.Forms.ComboBox
$scopeCombo.Location = New-Object System.Drawing.Point(140, 98)
$scopeCombo.Size = New-Object System.Drawing.Size(100, 20)
$scopeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$scopeCombo.Items.AddRange(@("CurrentUser", "AllUsers"))
$scopeCombo.SelectedIndex = 0
$optionsGroup.Controls.Add($scopeCombo)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 390)
$progressBar.Size = New-Object System.Drawing.Size(730, 20)
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$form.Controls.Add($progressBar)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready"
$statusLabel.Location = New-Object System.Drawing.Point(20, 420)
$statusLabel.Size = New-Object System.Drawing.Size(730, 20)
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($statusLabel)

# Output text box
$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Output:"
$outputLabel.Location = New-Object System.Drawing.Point(20, 450)
$outputLabel.Size = New-Object System.Drawing.Size(100, 20)
$outputLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($outputLabel)

$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point(20, 475)
$outputBox.Size = New-Object System.Drawing.Size(730, 80)
$outputBox.Multiline = $true
$outputBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$outputBox.ReadOnly = $true
$outputBox.BackColor = [System.Drawing.Color]::Black
$outputBox.ForeColor = [System.Drawing.Color]::White
$outputBox.Font = New-Object System.Drawing.Font("Consolas", 8)
$form.Controls.Add($outputBox)

# Function to update output
function Update-Output {
    param([string]$message)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $formattedMessage = "[$timestamp] $message"
    
    # Output to GUI
    $outputBox.AppendText("$formattedMessage`r`n")
    $outputBox.SelectionStart = $outputBox.Text.Length
    $outputBox.ScrollToCaret()
    
    # Output to PowerShell console
    Write-Host $formattedMessage -ForegroundColor Green
}

# Function to get selected modules
function Get-SelectedModules {
    $selected = @()
    for ($i = 0; $i -lt $moduleList.Items.Count; $i++) {
        if ($moduleList.GetItemChecked($i)) {
            $itemText = $moduleList.Items[$i].ToString()
            $moduleName = ($itemText -split '\(')[-1].TrimEnd(')')
            $selected += $moduleName
        }
    }
    return $selected
}

# Event handlers
$selectAllBtn.Add_Click({
    for ($i = 0; $i -lt $moduleList.Items.Count; $i++) {
        $moduleList.SetItemChecked($i, $true)
    }
})

$clearAllBtn.Add_Click({
    for ($i = 0; $i -lt $moduleList.Items.Count; $i++) {
        $moduleList.SetItemChecked($i, $false)
    }
})

$checkBtn.Add_Click({
    $selectedModules = Get-SelectedModules
    if ($selectedModules.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one module.", "No Modules Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $checkBtn.Enabled = $false
    $installBtn.Enabled = $false
    $statusLabel.Text = "Checking for updates..."
    $progressBar.Value = 0
    $outputBox.Clear()
    
    Update-Output "Starting update check for selected modules..."
    
    try {
        $totalModules = $selectedModules.Count
        $currentModule = 0
        
        foreach ($module in $selectedModules) {
            $currentModule++
            $progressBar.Value = [math]::Round(($currentModule / $totalModules) * 100)
            $statusLabel.Text = "Checking $module..."
            
            Update-Output "Checking module: $module"
            
            try {
                $installed = Get-InstalledModule -Name $module -ErrorAction SilentlyContinue
                $available = Find-Module -Name $module -ErrorAction SilentlyContinue
                
                if ($installed -and $available) {
                    if ($installed.Version -lt $available.Version) {
                        $updateMsg = "  UPDATE AVAILABLE: $module (Installed: $($installed.Version), Available: $($available.Version))"
                        Update-Output $updateMsg
                        Write-Host $updateMsg -ForegroundColor Yellow
                    } else {
                        $upToDateMsg = "  UP TO DATE: $module (Version: $($installed.Version))"
                        Update-Output $upToDateMsg
                        Write-Host $upToDateMsg -ForegroundColor Green
                    }
                } elseif ($available) {
                    $notInstalledMsg = "  NOT INSTALLED: $module (Available: $($available.Version))"
                    Update-Output $notInstalledMsg
                    Write-Host $notInstalledMsg -ForegroundColor Cyan
                } else {
                    $notFoundMsg = "  NOT FOUND: $module"
                    Update-Output $notFoundMsg
                    Write-Host $notFoundMsg -ForegroundColor Red
                }
            } catch {
                $errorMsg = "  ERROR checking $module`: $($_.Exception.Message)"
                Update-Output $errorMsg
                Write-Host $errorMsg -ForegroundColor Red
            }
            
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        $progressBar.Value = 100
        $statusLabel.Text = "Update check completed"
        $completedMsg = "Update check completed!"
        Update-Output $completedMsg
        Write-Host "`n=== UPDATE CHECK COMPLETED ===" -ForegroundColor Green -BackgroundColor Black
        $installBtn.Enabled = $true
        
    } catch {
        $mainErrorMsg = "ERROR: $($_.Exception.Message)"
        Update-Output $mainErrorMsg
        Write-Host $mainErrorMsg -ForegroundColor Red -BackgroundColor Black
        $statusLabel.Text = "Error occurred during check"
    } finally {
        $checkBtn.Enabled = $true
        $currentVersionBtn.Enabled = $true
    }
})

$installBtn.Add_Click({
    $selectedModules = Get-SelectedModules
    if ($selectedModules.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one module.", "No Modules Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $result = [System.Windows.Forms.MessageBox]::Show("This will install new modules and update existing ones for the selected items. Continue?", "Confirm Installation/Update", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $checkBtn.Enabled = $false
    $installBtn.Enabled = $false
    $currentVersionBtn.Enabled = $false
    $statusLabel.Text = "Installing updates..."
    $progressBar.Value = 0
    
    Update-Output "Starting module installation and updates..."
    
    try {
        $totalModules = $selectedModules.Count
        $currentModule = 0
        
        foreach ($module in $selectedModules) {
            $currentModule++
            $progressBar.Value = [math]::Round(($currentModule / $totalModules) * 100)
            $statusLabel.Text = "Installing $module..."
            
            Update-Output "Installing/Updating module: $module"
            
            try {
                $installParams = @{
                    Name = $module
                    Scope = $scopeCombo.SelectedItem
                    Force = $forceCheckbox.Checked
                    AllowClobber = $true
                    WarningAction = 'SilentlyContinue'
                }
                
                if ($prereleaseCheckbox.Checked) {
                    $installParams.AllowPrerelease = $true
                }
                
                if ($skipPublisherCheckbox.Checked) {
                    $installParams.SkipPublisherCheck = $true
                }
                
                # Try installation with warning capture
                $warningMessages = @()
                $installResult = Install-Module @installParams -ErrorAction Stop -WarningVariable warningMessages
                
                if ($warningMessages -and $warningMessages.Count -gt 0) {
                    $warningMsg = "  WARNING: $module installed but with warnings:"
                    Update-Output $warningMsg
                    Write-Host $warningMsg -ForegroundColor Yellow
                    foreach ($warning in $warningMessages) {
                        if ($warning -like "*currently in use*") {
                            $specificWarning = "    Module may require PowerShell restart to fully update"
                            Update-Output $specificWarning
                            Write-Host $specificWarning -ForegroundColor Yellow
                        } else {
                            Update-Output "    $warning"
                            Write-Host "    $warning" -ForegroundColor Yellow
                        }
                    }
                }
                
                $successMsg = "  SUCCESS: $module installed/updated"
                Update-Output $successMsg
                Write-Host $successMsg -ForegroundColor Green
                
            } catch {
                $installErrorMsg = "  ERROR installing $module`: $($_.Exception.Message)"
                Update-Output $installErrorMsg
                Write-Host $installErrorMsg -ForegroundColor Red
                
                # Check for specific common errors
                if ($_.Exception.Message -like "*currently in use*") {
                    $restartMsg = "    SOLUTION: Close all PowerShell windows and restart to complete update"
                    Update-Output $restartMsg
                    Write-Host $restartMsg -ForegroundColor Cyan
                }
            }
            
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        $progressBar.Value = 100
        $statusLabel.Text = "Installation completed"
        $installCompletedMsg = "All selected modules processed!"
        Update-Output $installCompletedMsg
        Write-Host "`n=== INSTALLATION COMPLETED ===" -ForegroundColor Green -BackgroundColor Black
        
        # Check if any warnings were shown and provide restart guidance
        $restartGuidance = "NOTE: If you saw warnings about modules 'currently in use', restart PowerShell to complete updates."
        Update-Output $restartGuidance
        Write-Host $restartGuidance -ForegroundColor Yellow
        
    } catch {
        $installMainErrorMsg = "ERROR: $($_.Exception.Message)"
        Update-Output $installMainErrorMsg
        Write-Host $installMainErrorMsg -ForegroundColor Red -BackgroundColor Black
        $statusLabel.Text = "Error occurred during installation"
    } finally {
        $checkBtn.Enabled = $true
        $installBtn.Enabled = $true
        $currentVersionBtn.Enabled = $true
    }
})

$currentVersionBtn.Add_Click({
    $selectedModules = Get-SelectedModules
    if ($selectedModules.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one module.", "No Modules Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $checkBtn.Enabled = $false
    $installBtn.Enabled = $false
    $currentVersionBtn.Enabled = $false
    $statusLabel.Text = "Checking current versions..."
    $progressBar.Value = 0
    $outputBox.Clear()
    
    Update-Output "Checking currently installed module versions..."
    
    try {
        $totalModules = $selectedModules.Count
        $currentModule = 0
        
        foreach ($module in $selectedModules) {
            $currentModule++
            $progressBar.Value = [math]::Round(($currentModule / $totalModules) * 100)
            $statusLabel.Text = "Checking $module..."
            
            Update-Output "Checking installed version: $module"
            
            try {
                $installed = Get-InstalledModule -Name $module -ErrorAction SilentlyContinue
                
                if ($installed) {
                    if ($installed.Count -gt 1) {
                        # Multiple versions installed
                        $versions = $installed | Sort-Object Version -Descending
                        $multiVersionMsg = "  INSTALLED: $module"
                        Update-Output $multiVersionMsg
                        Write-Host $multiVersionMsg -ForegroundColor Green
                        
                        $latestMsg = "    Latest: $($versions[0].Version) (Published: $($versions[0].PublishedDate.ToString('yyyy-MM-dd')))"
                        Update-Output $latestMsg
                        Write-Host $latestMsg -ForegroundColor Cyan
                        
                        if ($versions.Count -gt 1) {
                            $additionalMsg = "    Additional versions: $((($versions[1..($versions.Count-1)]).Version) -join ', ')"
                            Update-Output $additionalMsg
                            Write-Host $additionalMsg -ForegroundColor Yellow
                        }
                    } else {
                        # Single version installed
                        $singleVersionMsg = "  INSTALLED: $module (Version: $($installed.Version), Published: $($installed.PublishedDate.ToString('yyyy-MM-dd')))"
                        Update-Output $singleVersionMsg
                        Write-Host $singleVersionMsg -ForegroundColor Green
                    }
                } else {
                    $notInstalledCurrentMsg = "  NOT INSTALLED: $module"
                    Update-Output $notInstalledCurrentMsg
                    Write-Host $notInstalledCurrentMsg -ForegroundColor Red
                }
                
            } catch {
                $currentErrorMsg = "  ERROR checking $module`: $($_.Exception.Message)"
                Update-Output $currentErrorMsg
                Write-Host $currentErrorMsg -ForegroundColor Red
            }
            
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        $progressBar.Value = 100
        $statusLabel.Text = "Current version check completed"
        $currentCompletedMsg = "Current version check completed!"
        Update-Output $currentCompletedMsg
        Write-Host "`n=== CURRENT VERSION CHECK COMPLETED ===" -ForegroundColor Green -BackgroundColor Black
        
    } catch {
        $currentMainErrorMsg = "ERROR: $($_.Exception.Message)"
        Update-Output $currentMainErrorMsg
        Write-Host $currentMainErrorMsg -ForegroundColor Red -BackgroundColor Black
        $statusLabel.Text = "Error occurred during version check"
    } finally {
        $checkBtn.Enabled = $true
        $installBtn.Enabled = $true
        $currentVersionBtn.Enabled = $true
    }
})

# Show the form
Update-Output "Microsoft 365 PowerShell Module Install/Update loaded successfully!"
Update-Output "Select modules and click 'Check for Updates' to begin."
Write-Host "`n=== MICROSOFT 365 POWERSHELL MODULE INSTALL/UPDATE ===" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "GUI loaded successfully! Output will appear both in GUI and console." -ForegroundColor Green
Write-Host "Select modules and use the buttons to manage your PowerShell modules.`n" -ForegroundColor Cyan
$form.ShowDialog()
