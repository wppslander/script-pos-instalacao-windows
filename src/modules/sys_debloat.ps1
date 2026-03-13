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
        Write-Log "-> Falha ao definir AllowTelemetry: $_" -Type Warning
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
        Write-Log "-> Falha ao desativar Advertising ID: $_" -Type Warning
    }

    # 3. Servicos de Telemetria e Rastreamento
    # DiagTrack: Experiencias de Usuario Conectado e Telemetria (Principal)
    # dmwappushservice: WAP Push Message Routing Service (Telemetria Mobile/Push)
    # WerSvc: Servico de Relatorio de Erros do Windows
    # SysMain: Superfetch (Opcional, mas reduz uso de disco em ambientes virtualizados/HDD)
    Write-Log "Gerenciando servicos de rastreamento e nao essenciais..." -Type Info
    
    $telemetryServices = @(
        "DiagTrack", 
        "dmwappushservice", 
        "WerSvc",
        "SysMain"
    )

    foreach ($serviceName in $telemetryServices) {
        Disable-ServiceSafe -ServiceName $serviceName
    }

    # 4. Desabilitar Cortana
    # Remove a assistente pessoal da barra de tarefas e pesquisa
    Write-Log "Desabilitando Cortana..." -Type Info
    $cortanaPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    if (!(Test-Path $cortanaPath)) { New-Item -Path $cortanaPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $cortanaPath -Name "AllowCortana" -Value 0 -Type DWord -Force
        Write-Log "-> Cortana desativada via Policy." -Type Success
    } catch {
        Write-Log "-> Falha ao desativar Cortana: $_" -Type Warning
    }
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
            Write-Log "-> Falha ao remover ${app}: $_" -Type Warning
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
            Write-Log "-> Falha ao definir ${key}: $_" -Type Warning
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
        Write-Log "-> Falha ao configurar PrintScreen: $_" -Type Warning
    }
}
