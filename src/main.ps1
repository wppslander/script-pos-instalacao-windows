# ==================================================================================
# MAIN ORCHESTRATOR (BOOTSTRAP)
# Ponto de entrada minimo. Carrega dependencias e inicia o fluxo.
# ==================================================================================

$ErrorActionPreference = "Stop"
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$host.UI.RawUI.WindowTitle = "Instalador Unificado - Windows Post-Install"

try {
    # Carrega todos os módulos da pasta modules/, exceto o script auto_update.ps1
    Get-ChildItem -Path "$ScriptPath\modules\*.ps1" -Exclude "auto_update.ps1" | ForEach-Object {
        . $_.FullName
    }

    # Inicializa Logging
    Init-Logging
    Write-Log "Iniciando script principal..."

    # Chama o controlador principal (definido em modules/orchestrator.ps1)
    Invoke-GeminiPostInstall

} catch {
    Write-Host "ERRO FATAL: $_" -ForegroundColor Red
    pause
    exit 1
}
