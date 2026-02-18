# ==========================================
# MODULE: Orchestrator
# Gerencia o fluxo principal de execução e menus.
# ==========================================

function Show-Menu {
    Write-Host "`nSELECIONE O MODO DE EXECUCAO:" -ForegroundColor Cyan
    Write-Host "1. Instalacao Completa (Otimizacao + Softwares + GLPI)" -ForegroundColor White
    Write-Host "2. Apenas Configuracao do GLPI" -ForegroundColor White
    Write-Host "3. Apenas Instalacao de Softwares" -ForegroundColor White
    
    $val = Read-Host "`nOpcao (Padrao: 1)"
    if ([string]::IsNullOrWhiteSpace($val)) { return "1" }
    return $val
}

function Invoke-GeminiPostInstall {
    <#
    .SYNOPSIS
        Controlador principal do fluxo de instalação.
    #>
    
    # 0. Verificacao de Ambiente (Pre-Flight)
    try {
        Test-PreFlightChecks
    } catch {
        # Erro fatal se nao for admin
        Write-Host $_ -ForegroundColor Red
        Register-Failure "Pre-Flight" $_
        pause
        exit 1
    }

    # 0.1 Verificacao de Conectividade
    try {
        Test-InternetConnection
    } catch {
        Register-Failure "Internet Check" "Falha na verificacao de internet: $_"
    }

    # 1. Menu de Opções
    $opcao = Show-Menu

    # 2. Preparacao do Sistema (System Prep)
    if ($opcao -eq "1" -or $opcao -eq "3") {
        try {
            Enable-StoreSSLBypass
        } catch {
            Register-Failure "System Prep" "Falha no SSL Bypass: $_"
        }
    }

    # 3. Privacidade & Debloat
    if ($opcao -eq "1") {
        try {
            Disable-Telemetry
            Remove-Bloatware
            Disable-WindowsSuggestions
            Disable-PrintScreenSnipping
        } catch {
            Register-Failure "Debloat" "Falha na otimizacao de privacidade/bloatware: $_"
        }
    }

    # 4. Deploy de Software (Winget/Choco/MSI)
    if ($opcao -eq "1" -or $opcao -eq "3") {
        try {
            Install-CorporateSoftware
            
            # Configura atualizacao automatica silenciosa (Apenas na Instalação Completa)
            if ($opcao -eq "1") {
                Register-AutoUpdateTask
            }
        } catch {
            Register-Failure "Software Deploy" "Erro inesperado: $_"
        }
    }

    # 5. Configuracao do GLPI
    if ($opcao -eq "1" -or $opcao -eq "2") {
        try {
            Configure-GlpiAgent
        } catch {
            Register-Failure "GLPI Config" "Erro inesperado: $_"
        }
    }

    # 6. Finalizacao
    Show-ExecutionSummary

    Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
