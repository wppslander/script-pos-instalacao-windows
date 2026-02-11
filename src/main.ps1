# ==================================================================================
# MAIN ORCHESTRATOR
# ==================================================================================

$ErrorActionPreference = "Stop"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$host.UI.RawUI.WindowTitle = "Instalador Unificado - Digital Sat"

# Load Modules
try {
    . "$ScriptPath\modules\sys_utils.ps1"
    . "$ScriptPath\modules\glpi_installer.ps1"
    . "$ScriptPath\modules\software_deploy.ps1"
    . "$ScriptPath\modules\unigetui_config.ps1"
} catch {
    Write-Host "ERRO FATAL: Falha ao carregar modulos em $ScriptPath\modules" -ForegroundColor Red
    Write-Host $_
    pause
    exit 1
}

# --- EXECUTION FLOW ---

# 0. Check Internet
Test-InternetConnection

# 1. System Prep
Enable-StoreSSLBypass

# 2. Install GLPI
Install-GlpiAgent

# 3. Deploy Software
Install-CorporateSoftware

# 4. Configure UniGetUI
Configure-UniGetUI

# 5. Finish
Write-Host "`nProcesso concluido." -ForegroundColor Green
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
