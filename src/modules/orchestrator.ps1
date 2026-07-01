# ==========================================
# MODULE: Orchestrator
# Gerencia o fluxo principal de execução e menus.
# ==========================================

function Show-Menu {
    Write-Host "`nSELECIONE O MODO DE EXECUCAO:" -ForegroundColor Cyan
    Write-Host "1. Instalacao Completa (Otimizacao + Softwares + GLPI)" -ForegroundColor White
    Write-Host "2. Instalar GLPI (Instalar Pacote + Configurar)" -ForegroundColor White
    Write-Host "3. Só instalar programas (Sem configurar GLPI)" -ForegroundColor White
    Write-Host "4. Só reconfigurar GLPI (Apenas ajustar TAG/Servidor)" -ForegroundColor White
    Write-Host "5. Só Debloat (Privacidade e Otimizacoes)" -ForegroundColor White
    
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

    # 1.1 Coleta de TAG Antecipada (Opções que envolvem GLPI: 1, 2 ou 4)
    if ($opcao -eq "1" -or $opcao -eq "2" -or $opcao -eq "4") {
        $credFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "credentials.txt"
        $glpiServer = Get-CredentialValue -Key "GLPI_SERVER" -FilePath $credFile
        if ([string]::IsNullOrWhiteSpace($glpiServer)) { 
            $glpiServer = "http://glpi.yourcompany.com/front/inventory.php" 
        }
        
        Write-Host "`n=====================================================================" -ForegroundColor Yellow
        Write-Host "                  PARAMETRIZACAO DO GLPI AGENT" -ForegroundColor Yellow
        Write-Host "=====================================================================" -ForegroundColor Yellow
        Write-Host "Servidor GLPI Destino: $glpiServer" -ForegroundColor Cyan
        Write-Host "---------------------------------------------------------------------"
        
        do {
            $filial = Read-Host "1. Digite a FILIAL (Ex: MATRIZ)"
            $user = Read-Host "2. Digite o LOGIN SANKHYA (Ex: joao.silva)"

            # Sanitizacao basica para remover caracteres variaveis nas tags
            if ($filial) { $filial = $filial -replace '[ "&|]', '' }
            if ($user) { $user = $user -replace '[ "&|]', '' }
            
        } while ([string]::IsNullOrWhiteSpace($filial) -or [string]::IsNullOrWhiteSpace($user))

        $Global:GlpiTag = "$filial-$user"
        Write-Log "Tag temporaria armazenada: $Global:GlpiTag" -Type Info -Color Cyan
        Write-Host "Configuracao do GLPI agendada com a TAG: $Global:GlpiTag" -ForegroundColor Green
        Write-Host "=====================================================================`n"
    }

    # 2. Preparacao do Sistema (System Prep)
    if ($opcao -eq "1" -or $opcao -eq "3") {
        try {
            Enable-StoreSSLBypass
        } catch {
            Register-Failure "System Prep" "Falha no SSL Bypass: $_"
        }
    }

    # 3. Privacidade & Debloat
    if ($opcao -eq "1" -or $opcao -eq "5") {
        try {
            Disable-Telemetry
            Remove-Bloatware
            Disable-WindowsSuggestions
            Disable-PrintScreenSnipping
            Disable-BingSearch
            Disable-Copilot
            Disable-WidgetsAndChat
            Disable-ConsumerExperience
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

    # 4.1 Instalacao especifica do GLPI Agent (Opcao 2)
    if ($opcao -eq "2") {
        try {
            Install-GlpiAgent
        } catch {
            Register-Failure "GLPI Install" "Erro inesperado ao instalar pacote: $_"
        }
    }

    # 5. Configuracao do GLPI
    if ($opcao -eq "1" -or $opcao -eq "2" -or $opcao -eq "4") {
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
