# Microsoft 365 PowerShell Module Install/Update

A comprehensive PowerShell GUI application for managing and updating Microsoft 365 PowerShell modules with an intuitive interface.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)

## 🚀 Features

- **✅ Interactive GUI** - User-friendly Windows Forms interface
- **✅ Bulk Operations** - Select multiple modules for batch processing
- **✅ Version Checking** - Compare installed vs available versions
- **✅ Smart Installation** - Handles both new installs and updates
- **✅ Real-time Progress** - Progress bars and status updates
- **✅ Dual Output** - Results shown in both GUI and PowerShell console
- **✅ Error Handling** - Comprehensive error messages and solutions
- **✅ Flexible Options** - Force installs, prerelease versions, scope selection

## 📦 Supported Modules

| Module | Description |
|--------|-------------|
| **ExchangeOnlineManagement** | Exchange Online (EXO) management |
| **Microsoft.Online.SharePoint.PowerShell** | SharePoint Online (SPO) administration |
| **MicrosoftTeams** | Microsoft Teams management |
| **Microsoft.Graph** | Microsoft Graph (Complete SDK) |
| **Microsoft.Graph.Identity.DirectoryManagement** | Entra ID Directory Management |
| **Az** | Azure PowerShell (Complete Az Module) |
| **Az.Accounts, Az.Resources, Az.KeyVault, Az.Storage** | Specific Azure modules |
| **MSOnline, AzureAD** | Legacy Azure AD modules |
| **Microsoft.PowerApps.Administration.PowerShell** | Power Platform Admin |
| **PnP.PowerShell** | PnP PowerShell (SharePoint/M365) |
| **Microsoft.PowerShell.SecretManagement** | Secret Management |

## 🔧 Requirements

- **PowerShell 5.1** or later
- **Windows** operating system
- **Internet connection** for module downloads
- **Administrator privileges** (for AllUsers scope installation)
- **PowerShellGet module** (pre-installed with PowerShell 5.1+)

## 📥 Installation

### Option 1: Direct Download
1. Download `M365ModuleUpdater.ps1` from this repository
2. Save to your desired location
3. Run the script

### Option 2: Git Clone
```powershell
git clone https://github.com/yourusername/M365-PowerShell-Module-Updater.git
cd M365-PowerShell-Module-Updater
```

## 🎮 Usage

### Quick Start
```powershell
# Run the script
.\M365ModuleUpdater.ps1

# Or with execution policy bypass
PowerShell -ExecutionPolicy Bypass -File "M365ModuleUpdater.ps1"
```

### Step-by-Step Guide

1. **Launch the GUI** - Run the PowerShell script
2. **Select Modules** - Check the boxes for modules you want to manage
3. **Configure Options** - Set installation scope and other preferences
4. **Choose Action**:
   - **Check for Updates** - See what's available
   - **Check Current Versions** - View installed versions
   - **Install/Update Modules** - Perform the installation/update

### Installation Options

| Option | Description |
|--------|-------------|
| **Force reinstall** | Reinstall even if module is up to date |
| **Include prerelease** | Install beta/preview versions |
| **Skip publisher check** | Trust all publishers (use with caution) |
| **Installation Scope** | CurrentUser (no admin) or AllUsers (requires admin) |

## 🖼️ Screenshots

### Main Interface
*The clean, intuitive GUI showing module selection and options*
![image](https://github.com/user-attachments/assets/3f593db4-09d0-4e06-9684-a0cd863c1c14)

### Progress Tracking
*Real-time progress with both GUI progress bar and console output*
![image](https://github.com/user-attachments/assets/baea0533-255f-415a-9f3e-876bdc260224)

### Results Display
![image](https://github.com/user-attachments/assets/85677818-dced-452b-9e0d-e1c525db9915)

## ⚠️ Common Issues & Solutions

### "Currently in Use" Warning
```
WARNING: The version 'X.X.X' of module 'PackageManagement' is currently in use.
```
**Solution**: Close all PowerShell windows and restart to complete the update.

### Execution Policy Error
```
ERROR: Cannot be loaded because running scripts is disabled on this system.
```
**Solution**: Run with bypass parameter:
```powershell
PowerShell -ExecutionPolicy Bypass -File "M365ModuleUpdater.ps1"
```

### Permission Denied (AllUsers scope)
**Solution**: Run PowerShell as Administrator or use CurrentUser scope.

### Module Not Found
**Solution**: Check internet connection and verify module name spelling.

## 🔒 Security Notes

- Always review modules before installation
- Use CurrentUser scope when possible (no admin rights needed)
- Be cautious with "Skip publisher check" option
- Test in non-production environments first

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 Changelog

### Version 1.0
- Initial release
- GUI interface for module management
- Support for 18+ Microsoft 365 and Azure modules
- Real-time progress tracking
- Dual output (GUI + console)
- Comprehensive error handling

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Gulab Prasad**
- Website: [https://gulabprasad.com](https://gulabprasad.com)
- GitHub: [@CodeAIGit](https://github.com/codeaigit)

## 🙏 Acknowledgments

- Microsoft PowerShell Team for the excellent module ecosystem
- PowerShell community for inspiration and feedback
- All contributors and users of this tool

## ⭐ Support

If this tool helps you, please consider:
- ⭐ **Starring** this repository
- 🐛 **Reporting** any issues you find
- 💡 **Suggesting** new features
- 🔄 **Sharing** with other administrators

---

**Made with ❤️ for the Microsoft 365 community**
