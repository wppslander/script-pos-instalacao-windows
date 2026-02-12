# Windows Post-Installation Suite

**Project Purpose**: This repository contains a modular, automated, and maintainable script suite designed for post-installation configuration of Windows 11 workstations. It combines administrative privilege management, system tweaks, GLPI Agent deployment, and bulk software installation via `winget`.

---

## 🚀 Quick Start

1.  **Download** or **Clone** this repository to the target machine (or a USB drive).
2.  **Edit `credentials.txt`** (optional) to set your GLPI server, username, or password.
3.  **Double-click** on `bootstrap.bat`.
4.  **Confirm** the User Account Control (UAC) prompt to allow Administrator privileges.
5.  **Follow the on-screen prompts**:
    -   The script will verify internet connectivity automatically.
    -   Enter the **FILIAL** (Branch) (e.g., HEADQUARTERS).
    -   Enter the **USER** (e.g., john.doe).
    -   Confirm the generated TAG.
6.  **Wait** for the installation to complete. The script will install the GLPI Agent, a standard list of corporate software, and configure UniGetUI.

---

## 📂 Project Structure

The project is organized into a modular structure to facilitate maintenance and updates.

```
/ (Root)
├── bootstrap.bat             # Entry point. Handles elevation and launches PowerShell.
├── credentials.txt           # Configuration file (GLPI Server, User, Password).
├── software_list.json        # List of applications to install (JSON format).
├── GEMINI.md                 # Project documentation.
├── src/
    ├── main.ps1              # Main orchestrator script.
    └── modules/
        ├── sys_utils.ps1     # System utilities (Internet Check, Credentials, SSL Fix).
        ├── glpi_installer.ps1 # Logic for installing and configuring GLPI Agent.
        ├── software_deploy.ps1 # Software deployment logic.
        └── unigetui_config.ps1 # Post-install configuration for UniGetUI.
```

---

## 🛠 Maintenance & Customization

### GLPI Configuration (`credentials.txt`)
The `credentials.txt` file allows changing the server URL without modifying the code:
```ini
GLPI_SERVER=http://glpi.yourcompany.com/front/inventory.php
GLPI_USER=glpi_user
GLPI_PASSWORD=glpi_password
```

### Adding or Removing Software
To modify the list of installed applications:
1.  Open `src/modules/software_deploy.ps1`.
2.  Edit the `$packages` array by adding or removing lines.

---

## 🔍 Troubleshooting

-   **"Requesting Administrator Privileges..." loops**: Ensure you are not running the script from a restricted network share.
-   **No Internet**: The script checks connectivity (pinging 8.8.8.8) at startup and warns if offline.
-   **WhatsApp Failing**: The script runs `winget source update` automatically to fix MS Store catalog issues.
-   **UniGetUI Config**: Settings (Single UAC prompt, Auto-Update) are applied to `%LOCALAPPDATA%\UniGetUI\settings.json`.

---

**Version**: 1.2.0 (Modular + Config File)
**Author**: Daniel Wppslander and Gemini CLI Agent
**Date**: 2026-02-11
