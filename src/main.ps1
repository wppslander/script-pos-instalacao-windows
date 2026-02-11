# ==================================================================================
# MAIN ORCHESTRATOR
# ==================================================================================

$ErrorActionPreference = "Stop"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$host.UI.RawUI.WindowTitle = "Instalador Unificado - Windows Post-Install"

# Load Modules
try {
    . "$ScriptPath\modules\sys_utils.ps1"
    
    # Inicia Log
    Init-Logging
    Write-Log "Iniciando script principal..."

    . "$ScriptPath\modules\glpi_installer.ps1"
    . "$ScriptPath\modules\software_deploy.ps1"
    . "$ScriptPath\modules\unigetui_config.ps1"
} catch {
    Write-Host "ERRO FATAL: Falha ao carregar modulos em $ScriptPath\modules" -ForegroundColor Red
    Write-Host $_
    if (Get-Command "Write-Log" -ErrorAction SilentlyContinue) {
        Register-Failure "Main" "Erro fatal ao carregar modulos: $_"
    }
    pause
    exit 1
}

# --- EXECUTION FLOW ---

# 0. Check Internet
try {
    Test-InternetConnection
} catch {
    Register-Failure "Internet Check" "Falha na verificacao de internet: $_"
}

# 1. System Prep
try {
    Enable-StoreSSLBypass
} catch {
    Register-Failure "System Prep" "Falha no SSL Bypass: $_"
}

# 2. Install GLPI
try {
    Install-GlpiAgent
} catch {
    Register-Failure "GLPI Installer" "Erro inesperado: $_"
}

# 3. Deploy Software
try {
    Install-CorporateSoftware
} catch {
    Register-Failure "Software Deploy" "Erro inesperado: $_"
}

# 4. Configure UniGetUI
try {
    Configure-UniGetUI
} catch {
    Register-Failure "UniGetUI Config" "Erro inesperado: $_"
}

# 5. Finish
Show-ExecutionSummary

Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
