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
        } catch {
            Write-Warning "Falha ao ler settings.json existente. Criando novo."
        }
    }

    # Definir preferencias
    # DoCacheAdminRights: Pede UAC apenas uma vez por sessao
    # UpdatesInStartup: Busca updates ao iniciar
    $settings["DoCacheAdminRights"] = $true
    $settings["UpdatesInStartup"] = $true
    
    # Tenta forcar atualizacao automatica de pacotes
    $settings["DoAutoUpdatePackages"] = $true 
    $settings["AutomaticUpdates"] = $true

    try {
        $settings | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
        Write-Host "-> Configuracao aplicada com sucesso." -ForegroundColor Green
    } catch {
        Write-Host "-> Erro ao salvar configuracao: $_" -ForegroundColor Red
    }
}
