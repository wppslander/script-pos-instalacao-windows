function Install-GlpiAgent {
    <#
    .SYNOPSIS
        Instala o pacote do GLPI Agent usando Winget (ou fallback Chocolatey).
    #>
    Write-Log "VERIFICANDO INSTALACAO DO GLPI AGENT..." -Type Info -Color Cyan
    $regPath = "HKLM:\SOFTWARE\GLPI-Agent"
    
    if (Test-Path $regPath) {
        Write-Log "GLPI Agent ja instalado no registro." -Type Success
        return $true
    }
    
    Write-Log "GLPI Agent nao instalado. Iniciando instalacao..." -Type Info
    
    # Tenta via Winget
    Write-Log "Instalando via Winget..." -Type Info -Color Green
    $wingetArgs = @("install", "--id", "GLPI-Project.GLPI-Agent", "--source", "winget", "--exact", "--accept-package-agreements", "--accept-source-agreements", "--silent", "--force", "--disable-interactivity")
    try {
        & winget $wingetArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Log "GLPI Agent instalado com sucesso via Winget." -Type Success
            return $true
        }
    } catch {
        Write-Log "Erro ao executar Winget: $_" -Type Warning
    }
    
    # Fallback para Chocolatey
    Write-Log "Winget falhou. Tentando Chocolatey..." -Type Info -Color Magenta
    if (Install-ChocolateyEngine) {
        try {
            & choco install glpi-agent -y --no-progress
            if ($LASTEXITCODE -eq 0) {
                Write-Log "GLPI Agent instalado com sucesso via Chocolatey." -Type Success
                return $true
            }
        } catch {
            Write-Log "Erro ao executar Chocolatey: $_" -Type Warning
        }
    }
    
    Write-Log "Falha ao instalar o GLPI Agent por todos os meios." -Type Error
    Register-Failure "GLPI Install" "Falha na instalacao do pacote GLPI Agent."
    return $false
}

function Configure-GlpiAgent {
    <#
    .SYNOPSIS
        Realiza a configuracao pos-instalacao do GLPI Agent.
    .DESCRIPTION
        Lê as credenciais do arquivo credentials.txt, solicita dados interativos 
        ao usuario (Filial/Usuario) para gerar a TAG e aplica as configuracoes 
        no Registro do Windows e reinicia o servico.
    #>
    Write-Log "CONFIGURACAO GLPI AGENT" -Type Info -Color Cyan
    
    # Define o caminho do arquivo de credenciais
    $credFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "credentials.txt"
    
    # Carrega as variaveis sensiveis usando funcao auxiliar
    $glpiServer = Get-CredentialValue -Key "GLPI_SERVER" -FilePath $credFile
    $glpiUser   = Get-CredentialValue -Key "GLPI_USER" -FilePath $credFile
    $glpiPass   = Get-CredentialValue -Key "GLPI_PASSWORD" -FilePath $credFile

    # Define valores padrao caso o arquivo de credenciais esteja incompleto
    if ([string]::IsNullOrWhiteSpace($glpiServer)) { 
        $glpiServer = "http://glpi.yourcompany.com/front/inventory.php" 
        Write-Log "GLPI_SERVER nao encontrado em credentials.txt. Usando padrao." -Type Warning
    }
    if ([string]::IsNullOrWhiteSpace($glpiUser)) { $glpiUser = "teste" }
    if ([string]::IsNullOrWhiteSpace($glpiPass)) { $glpiPass = "teste" }

    Write-Log "Servidor GLPI: $glpiServer" -Type Info -Color DarkGray

    # 1. OBTENÇÃO DA TAG
    $finalTag = $null
    if (![string]::IsNullOrWhiteSpace($Global:GlpiTag)) {
        $finalTag = $Global:GlpiTag
        Write-Log "Usando TAG previamente configurada: $finalTag" -Type Info -Color Cyan
    } else {
        # Loop ate que o usuario forneca valores validos se nao foi coletada no inicio
        do {
            Write-Host "`n--- DADOS DO EQUIPAMENTO ---" -ForegroundColor Yellow
            $filial = Read-Host "1. Digite a FILIAL (Ex: MATRIZ)"
            $user = Read-Host "2. Digite o LOGIN SANKHYA (Ex: joao.silva)"

            # Sanitizacao basica para remover caracteres invalidos de tags
            if ($filial) { $filial = $filial -replace '[ "&|]', '' }
            if ($user) { $user = $user -replace '[ "&|]', '' }
            
        } while ([string]::IsNullOrWhiteSpace($filial) -or [string]::IsNullOrWhiteSpace($user))

        $finalTag = "$filial-$user"
        Write-Log "TAG GERADA: $finalTag" -Type Info -Color Cyan
    }
    
    # 2. APLICACAO DE CONFIGURACOES (REGISTRY)
    Write-Log "Aplicando configuracoes no Registro..." -Type Info -Color Yellow
    
    $regPath = "HKLM:\SOFTWARE\GLPI-Agent"
    
    # Verifica se o agente foi instalado (chave de registro deve existir)
    if (!(Test-Path $regPath)) {
        Write-Log "Caminho do registro $regPath nao encontrado. O GLPI Agent esta instalado?" -Type Error
        Register-Failure "GLPI Config" "Registro nao encontrado. Verifique se a instalacao ocorreu."
        return
    }

    try {
        # Define chaves essenciais para comunicacao com o servidor
        Set-ItemProperty -Path $regPath -Name "server" -Value $glpiServer -ErrorAction Stop
        Set-ItemProperty -Path $regPath -Name "tag" -Value $finalTag -ErrorAction Stop
        Set-ItemProperty -Path $regPath -Name "user" -Value $glpiUser -ErrorAction Stop
        Set-ItemProperty -Path $regPath -Name "password" -Value $glpiPass -ErrorAction Stop
        # Define modo de execucao como servico (padrao para coleta automatica)
        Set-ItemProperty -Path $regPath -Name "execmode" -Value "service" -ErrorAction Stop
        
        Write-Log "Configuracoes de registro aplicadas com sucesso." -Type Success
    } catch {
        Write-Log "Erro ao definir chaves de registro: $_" -Type Error
        Register-Failure "GLPI Config" "Falha ao gravar no registro: $_"
    }

    # 3. REINICIALIZACAO E TESTE
    Write-Log "Reiniciando servico GLPI-Agent..." -Type Info
    try {
        # Reinicia o servico para carregar as novas configuracoes do registro
        Restart-Service -Name "glpi-agent" -ErrorAction Stop
        Write-Log "Servico reiniciado." -Type Success
    } catch {
        Write-Log "Nao foi possivel reiniciar o servico glpi-agent: $_" -Type Warning
    }

    Start-Sleep -Seconds 2
    
    # Tenta forcar um inventario imediato via linha de comando
    $agentBin = "C:\Program Files\GLPI-Agent\glpi-agent.bat"
    if (Test-Path $agentBin) {
        Write-Log "Forcando inventario..." -Type Info -Color Yellow
        try {
            Start-Process -FilePath $agentBin -ArgumentList "--force" -Wait
            Write-Log "Inventario enviado." -Type Success
        } catch {
            Write-Log "Erro ao executar inventario manual: $_" -Type Warning
        }
    }
}
