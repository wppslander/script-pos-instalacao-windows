# ==========================================
# MODULE: System Debloat & Privacy
# ==========================================

function Disable-Telemetry {
    Write-Log "OTIMIZACAO DE PRIVACIDADE E TELEMETRIA" -Type Info -Color Cyan
    
    # 1. Desabilitar Telemetria (DataCollection)
    Write-Log "Desabilitando coleta de dados (AllowTelemetry)..." -Type Info
    $telemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (!(Test-Path $telemetryPath)) { New-Item -Path $telemetryPath -Force | Out-Null }
    try {
        Set-ItemProperty -Path $telemetryPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Log "-> Telemetria desativada via Registro." -Type Success
    } catch {
        Write-Log "-> Falha ao definir AllowTelemetry: $_" -Type Warning
    }

    # 2. Desabilitar Advertising ID
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
    Write-Log "Parando servico de rastreamento (DiagTrack)..." -Type Info
    try {
        if (Get-Service "DiagTrack" -ErrorAction SilentlyContinue) {
            Stop-Service "DiagTrack" -Force -ErrorAction SilentlyContinue
            Set-Service "DiagTrack" -StartupType Disabled -ErrorAction Stop
            Write-Log "-> Servico DiagTrack parado e desativado." -Type Success
        } else {
            Write-Log "-> Servico DiagTrack nao encontrado (ja removido?)." -Type Info -Color DarkGray
        }
    } catch {
        Write-Log "-> Erro ao gerenciar servico DiagTrack: $_" -Type Warning
    }

    # 4. Desabilitar Cortana (Opcional, mas recomendado para debloat)
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
