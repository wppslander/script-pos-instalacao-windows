# ==========================================
# MODULE: UniGetUI Configuration
# ==========================================

function Configure-UniGetUI {
    Write-Header "CONFIGURACAO UNIGETUI"
    Write-Host "Configurando preferencias (UAC Unico, Auto-Update)..." -ForegroundColor Yellow
    
    $configDir = "$env:LOCALAPPDATA\UniGetUI"
    $configFile = "$configDir\settings.json"

    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    }

    $settings = @{}
    if (Test-Path $configFile) {
        try {
            $jsonContent = Get-Content $configFile -Raw
            if ($jsonContent) {
                $settings = $jsonContent | ConvertFrom-Json -AsHashtable
            }
    Write-Log "CONFIGURACAO UNIGETUI" -Type Info -Color Cyan
    
    $settingsPath = "$env:LOCALAPPDATA\UniGetUI\settings.json"
    
    if (!(Test-Path $settingsPath)) {
        Write-Log "Arquivo settings.json do UniGetUI nao encontrado em $settingsPath" -Type Warning
        Write-Log "O UniGetUI pode nao ter sido aberto ainda ou nao foi instalado." -Type Warning
        Register-Failure "UniGetUI Config" "settings.json nao encontrado."
        return
    }

    try {
        $jsonContent = Get-Content $settingsPath -Raw
        $settings = $jsonContent | ConvertFrom-Json
        
        # Definir preferencias
        $settings | Add-Member -Name "DoCacheAdminRights" -Value $true -MemberType NoteProperty -Force
        $settings | Add-Member -Name "UpdatesInStartup" -Value $true -MemberType NoteProperty -Force
        
        # Tenta forcar atualizacao automatica de pacotes (Varias chaves possiveis)
        $settings | Add-Member -Name "DoAutoUpdatePackages" -Value $true -MemberType NoteProperty -Force
        $settings | Add-Member -Name "AutomaticUpdates" -Value $true -MemberType NoteProperty -Force
        $settings | Add-Member -Name "EnableAutoUpdate" -Value $true -MemberType NoteProperty -Force
        $settings | Add-Member -Name "UpdatePackagesAutomatically" -Value $true -MemberType NoteProperty -Force

        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath
        Write-Log "Configuracoes aplicadas ao UniGetUI." -Type Success

        # Remove arquivo que desativa updates, se existir
        $disableUpdateFile = "$env:LOCALAPPDATA\UniGetUI\DisableAutoCheckforUpdates"
        if (Test-Path $disableUpdateFile) {
            Remove-Item $disableUpdateFile -Force -ErrorAction SilentlyContinue
            Write-Log "Arquivo 'DisableAutoCheckforUpdates' removido." -Type Info
        }
        
        Write-Log "NOTA: Verifique nas configuracoes do UniGetUI se 'Atualizar pacotes automaticamente' esta marcado." -Type Info -Color Yellow

    } catch {
        Write-Log "Erro ao processar JSON do UniGetUI: $_" -Type Error
        Register-Failure "UniGetUI Config" "Erro ao editar settings.json: $_"
    }
}
