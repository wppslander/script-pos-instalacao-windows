# ==================================================================================
# MAIN ORCHESTRATOR
# Ponto de entrada principal do script de pos-instalacao.
# Gerencia o fluxo de execucao, tratamento de erros globais e carregamento de modulos.
# ==================================================================================

# Define que erros devem parar a execucao imediata do bloco atual
$ErrorActionPreference = "Stop"

# Identifica o diretorio onde o script esta rodando para carregar dependencias relativas
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Define titulo da janela para facil identificacao
$host.UI.RawUI.WindowTitle = "Instalador Unificado - Windows Post-Install"

# --- CARREGAMENTO DE MODULOS ---
try {
    # Carrega utilitarios base primeiro (Logs, Checks)
    . "$ScriptPath\modules\sys_utils.ps1"
    
    # Inicializa o sistema de logs
    Init-Logging
    Write-Log "Iniciando script principal..."

    # Carrega os demais modulos de funcionalidade
    . "$ScriptPath\modules\glpi_installer.ps1"
    . "$ScriptPath\modules\software_helpers.ps1"
    . "$ScriptPath\modules\software_deploy.ps1"
    . "$ScriptPath\modules\sys_debloat.ps1"
} catch {
    # Se falhar no load, nao ha muito o que fazer alem de alertar e sair
    Write-Host "ERRO FATAL: Falha ao carregar modulos em $ScriptPath\modules" -ForegroundColor Red
    Write-Host $_
    if (Get-Command "Write-Log" -ErrorAction SilentlyContinue) {
        Register-Failure "Main" "Erro fatal ao carregar modulos: $_"
    }
    pause
    exit 1
}

# --- FLUXO DE EXECUCAO ---

# 0. Verificacao de Conectividade
# Essencial pois quase tudo depende de download
try {
    Test-InternetConnection
} catch {
    Register-Failure "Internet Check" "Falha na verificacao de internet: $_"
}

# --- SELECAO DE MODO DE OPERACAO ---
Write-Host "`nSELECIONE O MODO DE EXECUCAO:" -ForegroundColor Cyan
    Write-Host "1. Instalacao Completa (Otimizacao + Softwares + GLPI)" -ForegroundColor White
    Write-Host "2. Apenas Configuracao do GLPI" -ForegroundColor White
    Write-Host "3. Apenas Instalacao de Softwares" -ForegroundColor White
    $opcao = Read-Host "`nOpcao (Padrao: 1)"
if ([string]::IsNullOrWhiteSpace($opcao)) { $opcao = "1" }

# 1. Preparacao do Sistema (System Prep)
if ($opcao -eq "1" -or $opcao -eq "3") {
    # Ajustes de registro necessarios antes de instalar qualquer coisa (ex: SSL Fix)
    try {
        Enable-StoreSSLBypass
    } catch {
        Register-Failure "System Prep" "Falha no SSL Bypass: $_"
    }
}

if ($opcao -eq "1") {
    # 1.1 Privacidade & Debloat
    # Remove bloatware e telemetria antes de instalar softs corporativos
    try {
        Disable-Telemetry
        Remove-Bloatware
        Disable-WindowsSuggestions
        Disable-PrintScreenSnipping
    } catch {
        Register-Failure "Debloat" "Falha na otimizacao de privacidade/bloatware: $_"
    }
}

# 2. Deploy de Software (Winget/Choco/MSI)
if ($opcao -eq "1" -or $opcao -eq "3") {
    try {
        Install-CorporateSoftware
    } catch {
        Register-Failure "Software Deploy" "Erro inesperado: $_"
    }
}

# 3. Configuracao do GLPI
if ($opcao -eq "1" -or $opcao -eq "2") {
    # Configura o agente de inventario apos as instalacoes
    try {
        Configure-GlpiAgent
    } catch {
        Register-Failure "GLPI Config" "Erro inesperado: $_"
    }
}

# 4. Finalizacao
# Exibe resumo de erros e sucessos
Show-ExecutionSummary

Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
