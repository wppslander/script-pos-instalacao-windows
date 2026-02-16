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

    # 3. Servico DiagTrack (Experiencias de Usuario Conectado e Telemetria)
    # Servico principal responsavel pelo envio de dados de diagnostico
    Write-Log "Parando servico de rastreamento (DiagTrack)..." -Type Info
    try {
        if (Get-Service "DiagTrack" -ErrorAction SilentlyContinue) {
            # Para o servico imediatamente
            Stop-Service "DiagTrack" -Force -ErrorAction SilentlyContinue
            # Desabilita o inicio automatico
            Set-Service "DiagTrack" -StartupType Disabled -ErrorAction Stop
            Write-Log "-> Servico DiagTrack parado e desativado." -Type Success
        } else {
            Write-Log "-> Servico DiagTrack nao encontrado (ja removido?)." -Type Info -Color DarkGray
        }
    } catch {
        Write-Log "-> Erro ao gerenciar servico DiagTrack: $_" -Type Warning
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
            $package = Get-AppxPackage -Name $app -ErrorAction SilentlyContinue
            if ($package) {
                Write-Log "-> Removendo $app..." -Type Info -Color Yellow
                # Remove do usuario atual
                $package | Remove-AppxPackage -ErrorAction Stop
                
                # Tenta remover do provisionamento (para novos usuarios) - Requer Admin
                Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $app } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
                
                $removedCount++
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
