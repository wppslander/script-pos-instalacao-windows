# ==========================================
# MODULE: System Debloat & Privacy
# Responsavel por desativar telemetria e servicos
# nao essenciais para o ambiente corporativo.
# ==========================================

function Disable-Telemetry {
    <#
    .SYNOPSIS
        Desabilita recursos de telemetria e rastreamento do Windows 10/11.
    .DESCRIPTION
        Altera chaves de registro e servicos para reduzir o ruido de rede
        e melhorar a privacidade do usuario corporativo.
    #>
    Write-Log "OTIMIZACAO DE PRIVACIDADE E TELEMETRIA" -Type Info -Color Cyan
    
    # 1. Desabilitar Telemetria (AllowTelemetry)
    # 0 = Seguranca (Apenas Enterprise), 1 = Basico, 3 = Completo
    Write-Log "Desabilitando coleta de dados (AllowTelemetry)..." -Type Info
    $telemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    
    # Cria a chave se nao existir
    if (!(Test-Path $telemetryPath)) { New-Item -Path $telemetryPath -Force | Out-Null }
    
    try {
        Set-ItemProperty -Path $telemetryPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "-> Telemetria desativada via Registro." -Type Success
    } catch {
        # Correção: Isolando $_ para evitar erro de parser
        Write-Log "-> Falha ao definir AllowTelemetry: $($_)" -Type Warning
    }

    # 2. Desabilitar Advertising ID (ID de Publicidade)
    # Impede que apps usem um ID unico para rastrear habitos do usuario
    Write-Log "Desabilitando ID de Publicidade..." -Type Info
    $advPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    if (!(Test-Path $advPath)) { New-Item -Path $advPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $advPath -Name "Enabled" -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "-> Advertising ID desativado." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar Advertising ID: $($_)" -Type Warning
    }

    # 3. Servicos de Telemetria e Rastreamento
    # DiagTrack: Experiencias de Usuario Conectado e Telemetria (Principal)
    # dmwappushservice: WAP Push Message Routing Service (Telemetria Mobile/Push)
    # WerSvc: Servico de Relatorio de Erros do Windows
    Write-Log "Gerenciando servicos de rastreamento e nao essenciais..." -Type Info
    
    $telemetryServices = @(
        "DiagTrack", 
        "dmwappushservice", 
        "WerSvc"
        # "SysMain" -> REMOVIDO DA LISTA: Desabilitar o Superfetch atrasa 
        # a indexação e a agilidade da barra de pesquisa do Iniciar.
    )

    foreach ($serviceName in $telemetryServices) {
        Disable-ServiceSafe -ServiceName $serviceName
    }

    # 4. Desabilitar Cortana (DESATIVADO NO SCRIPT)
    # ALERTA DE INFRA: Em versoes recentes do Win10/11, a chave AllowCortana=0 
    # destroi o backend do Windows Search para busca local de aplicativos. 
    # Mantido comentado para historico e prevencao de erros futuros.
    <#
    Write-Log "Desabilitando Cortana..." -Type Info
    $cortanaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (!(Test-Path $cortanaPath)) { New-Item -Path $cortanaPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $cortanaPath -Name "AllowCortana" -Value 0 -Type DWord -Force
        Write-Log "-> Cortana desativada via Policy." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar Cortana: $($_)" -Type Warning
    }
    #>
}

function Remove-Bloatware {
    <#
    .SYNOPSIS
        Remove aplicativos nativos (bloatware) do Windows.
    .DESCRIPTION
        Remove aplicativos AppX pre-instalados que nao sao essenciais para
        o ambiente corporativo, como Jogos, Xbox, Noticias, Clima, etc.
    #>
    Write-Log "REMOCAO DE BLOATWARE (APPS NATIVOS)" -Type Info -Color Cyan

    $bloatList = @(
        "Microsoft.XboxApp",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxSpeechToTextOverlay",
        "Microsoft.GamingApp",
        "Microsoft.YourPhone",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Microsoft.SolitaireCollection",
        "Microsoft.BingNews",
        "Microsoft.BingWeather",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.People",
        "Microsoft.WindowsFeedbackHub"
    )

    $removedCount = 0

    foreach ($app in $bloatList) {
        Write-Host "Verificando: $app" -ForegroundColor DarkGray
        try {
            # Busca com curingas para capturar variacoes de versao
            $packages = Get-AppxPackage -Name "*$app*" -ErrorAction SilentlyContinue
            if ($packages) {
                foreach ($package in $packages) {
                    Write-Log "-> Removendo $($package.Name)..." -Type Info -Color Yellow
                    # Remove do usuario atual
                    $package | Remove-AppxPackage -ErrorAction Stop
                    
                    # Tenta remover do provisionamento (para novos usuarios) - Requer Admin
                    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -match $app -or $_.PackageName -match $app } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                    
                    $removedCount++
                }
            }
        } catch {
            Write-Log "-> Falha ao remover ${app}: $($_)" -Type Warning
        }
    }

    if ($removedCount -gt 0) {
        Write-Log "Total de apps removidos: $removedCount" -Type Success
    } else {
        Write-Log "Nenhum bloatware listado foi encontrado." -Type Info
    }
}

function Disable-WindowsSuggestions {
    <#
    .SYNOPSIS
        Desativa notificacoes de sugestoes, dicas e experiencias de boas-vindas.
    .DESCRIPTION
        Objetivo: "Entrar em configuracao notificacao > configuracao adicional e desabilitar todas a opcoes"
        Modifica o registro do usuario atual para silenciar o ruido do sistema.
    #>
    Write-Log "OTIMIZACAO DE NOTIFICACOES E SUGESTOES" -Type Info -Color Cyan

    $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    
    # Garante que o caminho existe
    if (!(Test-Path $cdmPath)) { New-Item -Path $cdmPath -Force | Out-Null }

    # Lista de chaves e seus significados para facilitar manutencao futura
    $configuracoes = @{
        "SubscribedContent-338389Enabled" = "Dicas e Truques do Windows";
        "SubscribedContent-338388Enabled" = "Notificacoes de Provedores de Sincronizacao";
        "SubscribedContent-310093Enabled" = "Experiencia de Boas Vindas do Windows";
        "SubscribedContent-353696Enabled" = "Sugestoes sobre como usar o Windows";
        "SystemPaneSuggestionsEnabled"    = "Sugestoes no menu Iniciar e Config";
        "SoftLandingEnabled"              = "Dicas introdutorias";
        "RotatingLockScreenEnabled"       = "Sugestoes na tela de bloqueio";
        "SubscribedContent-338387Enabled" = "Sugestoes gerais de conteudo"
    }

    foreach ($key in $configuracoes.Keys) {
        $descricao = $configuracoes[$key]
        Write-Log "Desabilitando: $descricao ($key)..." -Type Info -Color DarkGray
        try {
            Set-ItemProperty -Path $cdmPath -Name $key -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Log "-> Falha ao definir ${key}: $($_)" -Type Warning
        }
    }
    
    Write-Log "-> Sugestoes do Windows desabilitadas." -Type Success
}

function Disable-PrintScreenSnipping {
    <#
    .SYNOPSIS
        Libera a tecla PrintScreen para uso de terceiros (ex: Flameshot).
    .DESCRIPTION
        Objetivo: "Entrar em configuracao > assecibilidade > teclado > desabilitar use tecla PrtSC"
        Desativa a captura de tela nativa do Windows (Snipping Tool) ao pressionar PrtSc.
    #>
    Write-Log "CONFIGURACAO DE TECLADO (PRINTSCREEN)" -Type Info -Color Cyan
    
    $keyboardPath = "HKCU:\Control Panel\Keyboard"
    
    Write-Log "Desabilitando captura nativa na tecla PrintScreen..." -Type Info
    try {
        # Valor 0 = Desabilitado (Permite que Flameshot/Lightshot assumam a tecla)
        # Valor 1 = Habilitado (Abre Ferramenta de Captura do Windows)
        Set-ItemProperty -Path $keyboardPath -Name "PrintScreenKeyForSnippingEnabled" -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "-> Tecla PrintScreen liberada para softwares de terceiros." -Type Success
    } catch {
        Write-Log "-> Falha ao configurar PrintScreen: $($_)" -Type Warning
    }
}

function Disable-BingSearch {
    <#
    .SYNOPSIS
        Desativa pesquisas da web (Bing) no Menu Iniciar do Windows.
    .DESCRIPTION
        Faz com que as pesquisas no menu iniciar retornem apenas resultados locais,
        tornando a pesquisa instantânea e economizando recursos de internet/rede.
    #>
    Write-Log "DESABILITANDO BING NO MENU INICIAR" -Type Info -Color Cyan
    
    $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    $policyPath = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    
    if (!(Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
    if (!(Test-Path $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
    
    try {
        Set-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $searchPath -Name "CortanaConsent" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $policyPath -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force
        Write-Log "-> Bing desativado no Menu Iniciar com sucesso." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar pesquisa do Bing no menu iniciar: $($_)" -Type Warning
    }
}

function Disable-Copilot {
    <#
    .SYNOPSIS
        Desativa o Windows Copilot (assistente AI integrado no sistema).
    #>
    Write-Log "DESABILITANDO WINDOWS COPILOT" -Type Info -Color Cyan
    
    $hkcuCopilot = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
    $hklmCopilot = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    $hkcuAdvanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    
    if (!(Test-Path $hkcuCopilot)) { New-Item -Path $hkcuCopilot -Force | Out-Null }
    if (!(Test-Path $hklmCopilot)) { New-Item -Path $hklmCopilot -Force | Out-Null }
    
    try {
        Set-ItemProperty -Path $hkcuCopilot -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $hklmCopilot -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $hkcuAdvanced -Name "ShowCopilotButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "-> Copilot desabilitado com sucesso." -Type Success
    } catch {
        Write-Log "-> Falha ao desabilitar Copilot: $($_)" -Type Warning
    }
}

function Disable-WindowsAI {
    <#
    .SYNOPSIS
        Desativa recursos adicionais de Inteligencia Artificial (AI) do Windows 11.
    .DESCRIPTION
        Desativa o Windows Recall (gravação de tela/snapshots), recursos de analise de dados de AI
        e o Copilot no navegador Microsoft Edge.
    #>
    Write-Log "DESABILITANDO RECURSOS DE AI DO WINDOWS (RECALL, EDGE COPILOT, ETC)" -Type Info -Color Cyan
    
    $windowsAIPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    $searchPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"

    # 1. Desativar Windows Recall (Recall/AI Explorer) e Data Analysis
    if (!(Test-Path $windowsAIPath)) { New-Item -Path $windowsAIPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $windowsAIPath -Name "AllowRecallEnablement" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $windowsAIPath -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force
        Write-Log "-> Windows Recall e Analise de Dados de AI desativados." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar Windows Recall/AI: $($_)" -Type Warning
    }

    # 2. Desativar Copilot no Microsoft Edge
    if (!(Test-Path $edgePolicyPath)) { New-Item -Path $edgePolicyPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $edgePolicyPath -Name "EdgeCopilotEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $edgePolicyPath -Name "Microsoft365CopilotChatIconEnabled" -Value 0 -Type DWord -Force
        Write-Log "-> Copilot no Microsoft Edge desativado." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar Copilot no Edge: $($_)" -Type Warning
    }

    # 3. Desativar Search Highlights (Destaques de Pesquisa / Bing AI na barra)
    if (!(Test-Path $searchPolicyPath)) { New-Item -Path $searchPolicyPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $searchPolicyPath -Name "EnableDynamicContentInWSB" -Value 0 -Type DWord -Force
        Write-Log "-> Destaques de Pesquisa (Search Highlights) desativados." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar Destaques de Pesquisa: $($_)" -Type Warning
    }
}

function Disable-WidgetsAndChat {
    <#
    .SYNOPSIS
        Desativa os Widgets (Noticias e Interesses) e o icone de Chat na Barra de Tarefas.
    .DESCRIPTION
        Remove os icones da barra de tarefas e desativa os servicos de feeds de noticias em background,
        liberando cerca de 200MB a 400MB de RAM (processos WebView2).
    #>
    Write-Log "DESABILITANDO WIDGETS E CHAT DA BARRA DE TAREFAS" -Type Info -Color Cyan
    
    $dshPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    $advancedPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    
    if (!(Test-Path $dshPath)) { New-Item -Path $dshPath -Force | Out-Null }
    
    try {
        # Desativa feeds e barra de widgets por diretiva
        Set-ItemProperty -Path $dshPath -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force
        
        # Oculta icones na barra de tarefas para o usuario atual
        Set-ItemProperty -Path $advancedPath -Name "TaskbarDa" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $advancedPath -Name "TaskbarMn" -Value 0 -Type DWord -Force
        
        Write-Log "-> Widgets e Chat desativados e removidos da barra de tarefas." -Type Success
    } catch {
        Write-Log "-> Falha ao desabilitar Widgets/Chat: $($_)" -Type Warning
    }
}

function Disable-ConsumerExperience {
    <#
    .SYNOPSIS
        Desativa a Experiencia do Consumidor da Microsoft (instalação automatica de jogos/apps).
    .DESCRIPTION
        Evita que o Windows baixe silenciosamente aplicativos como Candy Crush, Spotify,
        Disney+, etc., para novos perfis de usuario.
    #>
    Write-Log "DESABILITANDO INSTALACAO AUTOMATICA DE APPS DE CONSUMO (CANDY CRUSH, ETC)" -Type Info -Color Cyan
    
    $cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (!(Test-Path $cloudPath)) { New-Item -Path $cloudPath -Force | Out-Null }
    
    try {
        Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
        Write-Log "-> Instalacao automatica de apps de consumo bloqueada." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar Experiencia do Consumidor: $($_)" -Type Warning
    }
}
