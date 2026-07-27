function Install-GlpiAgent {
    <#
    .SYNOPSIS
        Instala o pacote do GLPI Agent usando Winget, configurando-o com os parâmetros corretos.
        Se já estiver instalado, executa a reconfiguração.
    #>
    Write-Log "VERIFICANDO INSTALACAO DO GLPI AGENT..." -Type Info -Color Cyan
    $regPath = "HKLM:\SOFTWARE\GLPI-Agent"
    $svcCheck = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue

    if ((Test-Path $regPath) -or ($svcCheck -ne $null)) {
        Write-Log "GLPI Agent ja detectado no sistema. Executando a reconfiguracao..." -Type Info -Color Yellow
        Configure-GlpiAgent
        return $true
    }

    Write-Log "GLPI Agent nao instalado. Iniciando instalacao..." -Type Info

    # Define o caminho do arquivo de credenciais
    $credFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".env"

    # Carrega credenciais do arquivo .env se existir, com fallbacks adequados
    $server = Get-CredentialValue -Key "GLPI_SERVER" -FilePath $credFile
    $user   = Get-CredentialValue -Key "GLPI_USER" -FilePath $credFile
    $pass   = Get-CredentialValue -Key "GLPI_PASSWORD" -FilePath $credFile

    if ([string]::IsNullOrWhiteSpace($server)) { 
        $server = "https://glpi.i.digitalsat.com.br/front/inventory.php" 
        Write-Log "GLPI_SERVER nao encontrado em .env. Usando padrao." -Type Warning
    }
    if ([string]::IsNullOrWhiteSpace($user)) { $user = "glpi" }
    if ([string]::IsNullOrWhiteSpace($pass)) { $pass = "md3F2eUv" }

    # Define a TAG a ser utilizada (resgata da variável global ou gera uma)
    $tag = $null
    if (![string]::IsNullOrWhiteSpace($Global:GlpiTag)) {
        $tag = $Global:GlpiTag
        Write-Log "Usando TAG previamente configurada: $tag" -Type Info -Color Cyan
    } else {
        # Loop até obter uma TAG válida caso não tenha sido coletada no início
        do {
            Write-Host "`n--- DADOS DO EQUIPAMENTO ---" -ForegroundColor Yellow
            $filial = Read-Host "1. Digite a FILIAL (Ex: MATRIZ)"
            $setor  = Read-Host "2. Digite o SETOR (Ex: TI)"
            $nome   = Read-Host "3. Digite o NOME/LOGIN (Ex: joao.silva)"

            # Sanitização básica para remover espaços e caracteres especiais
            if ($filial) { $filial = $filial -replace '[ "&|]', '' }
            if ($setor)  { $setor  = $setor  -replace '[ "&|]', '' }
            if ($nome)   { $nome   = $nome   -replace '[ "&|]', '' }
            
        } while ([string]::IsNullOrWhiteSpace($filial) -or [string]::IsNullOrWhiteSpace($setor) -or [string]::IsNullOrWhiteSpace($nome))

        $tag = "$filial-$setor-$nome"
        $Global:GlpiTag = $tag
        Write-Log "TAG gerada: $tag" -Type Info -Color Cyan
    }

    # Define as variáveis de ambiente temporárias para herdar
    $env:GLPI_SERVER = $server
    $env:GLPI_USER = $user
    $env:GLPI_PASS = $pass
    $env:GLPI_TAG = $tag

    $msiArgs = "RUNNOW=1 SERVER=`"$server`" USER=`"$user`" PASSWORD=`"$pass`" TAG=`"$tag`" EXECMODE=Service"
    $installed = $false

    # 1. TENTATIVA DIRETA VIA GITHUB RELEASES
    Write-Log "Tentando baixar e instalar o GLPI Agent diretamente do GitHub..." -Type Info -Color Cyan
    try {
        # Garante o uso de TLS 1.2 para download seguro
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $apiUri = "https://api.github.com/repos/glpi-project/glpi-agent/releases/latest"
        $apiResponse = Invoke-RestMethod -Uri $apiUri -UseBasicParsing
        $msiAsset = $apiResponse.assets | Where-Object { $_.name -match "x64\.msi$" } | Select-Object -First 1

        if ($msiAsset -and $msiAsset.browser_download_url) {
            $downloadUrl = $msiAsset.browser_download_url
            $tempMsi = Join-Path $env:TEMP "glpi-agent-latest-x64.msi"
            
            Write-Log "Baixando $downloadUrl..." -Type Info -Color Green
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempMsi -UseBasicParsing
            
            if (Test-Path $tempMsi) {
                Write-Log "Executando instalacao silenciosa do MSI..." -Type Info -Color Green
                $arguments = "/i `"$tempMsi`" /quiet /norestart $msiArgs"
                $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
                
                if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                    Write-Log "GLPI Agent instalado com sucesso via GitHub MSI." -Type Success
                    $installed = $true
                } else {
                    Write-Log "Falha na execucao do MSI. Codigo de retorno: $($proc.ExitCode)" -Type Warning
                }
                
                # Remove o arquivo temporario
                Remove-Item -Path $tempMsi -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-Log "Nao foi possivel localizar o pacote MSI de 64 bits nos assets do GitHub." -Type Warning
        }
    } catch {
        Write-Log "Erro durante tentativa de instalacao via GitHub: $_" -Type Warning
    }

    # 2. SE FALHAR, TENTA VIA WINGET (FALLBACK)
    if (-not $installed) {
        Write-Log "Tentando instalar via Winget como fallback..." -Type Info -Color Cyan
        try {
            $wingetArgs = @("install", "-e", "--id", "GLPI-Project.GLPI-Agent", "--source", "winget", "--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements", "--override", "/quiet /norestart $msiArgs")
            & winget $wingetArgs
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "GLPI Agent instalado com sucesso via Winget." -Type Success
                $installed = $true
            } else {
                Write-Log "Winget falhou com codigo de retorno $LASTEXITCODE" -Type Warning
            }
        }
        catch {
            Write-Log "Erro ao executar Winget: $_" -Type Warning
        }
    }

    # 3. SE AINDA FALHAR, TENTA VIA CHOCOLATEY (FALLBACK SEGUNDO)
    if (-not $installed) {
        Write-Log "Tentando instalar via Chocolatey como ultimo fallback..." -Type Info -Color Magenta
        if (Install-ChocolateyEngine) {
            try {
                & choco install glpi-agent -y --no-progress
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "GLPI Agent instalado via Chocolatey." -Type Success
                    $installed = $true
                }
            } catch {
                Write-Log "Erro ao executar Chocolatey: $_" -Type Warning
            }
        }
    }

    if (-not $installed) {
        Write-Log "Falha ao instalar o GLPI Agent por todos os metodos (GitHub, Winget, Chocolatey)." -Type Error
        Register-Failure "GLPI Install" "Falha na instalacao do pacote por todos os meios."
        return $false
    }

    ### VERIFICANDO SE O SERVIÇO DO GLPI ESTA RODANDO
    Write-Log "Validando status do servico..." -Type Info -Color Cyan
    Start-Sleep -Seconds 10
    $svc = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue

    if ($svc -and $svc.Status -eq 'Running') {
        Write-Log "GLPI Agent instalado com sucesso." -Type Success
        Write-Log "- Servico: RUNNING" -Type Success -Color Green
        Write-Log "- Tag: $tag" -Type Success -Color Green
        Write-Log "- Servidor: $server" -Type Success -Color Green
        
        # Marca como configurado para evitar reconfiguração duplicada no orchestrator
        $Global:GlpiConfigured = $true
    }
    else {
        Write-Log "O servico GLPI Agent nao esta no status Running ou nao foi iniciado." -Type Warning
    }

    ### INVENTARIO IMEDIATO (VALIDACAO DE COMUNICACAO)
    Write-Log "Solicitando inventario imediato..." -Type Info -Color Cyan
    $agentExe = "C:\Program Files\GLPI-Agent\glpi-agent.bat"

    if (Test-Path $agentExe) {
        & $agentExe --force --logger=stderr
        Write-Log "Comando de inventario executado." -Type Success
    } else {
        Write-Log "O arquivo de lote do agente nao foi encontrado no caminho padrao." -Type Error
        Register-Failure "GLPI Install" "Arquivo glpi-agent.bat nao encontrado."
        return $false
    }

    return $true
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
    
    # Evita executar duas vezes se já configurado
    if ($Global:GlpiConfigured) {
        Write-Log "Configuracao do GLPI ja aplicada anteriormente nesta sessao." -Type Info -Color Gray
        return
    }

    Write-Log "CONFIGURACAO GLPI AGENT" -Type Info -Color Cyan
    
    # Define o caminho do arquivo de credenciais
    $credFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".env"
    
    # Carrega as variaveis sensiveis usando funcao auxiliar
    $glpiServer = Get-CredentialValue -Key "GLPI_SERVER" -FilePath $credFile
    $glpiUser   = Get-CredentialValue -Key "GLPI_USER" -FilePath $credFile
    $glpiPass   = Get-CredentialValue -Key "GLPI_PASSWORD" -FilePath $credFile

    # Define valores padrao caso o arquivo de credenciais esteja incompleto
    if ([string]::IsNullOrWhiteSpace($glpiServer)) { 
        $glpiServer = "https://glpi.i.digitalsat.com.br/front/inventory.php" 
        Write-Log "GLPI_SERVER nao encontrado em .env. Usando padrao." -Type Warning
    }
    if ([string]::IsNullOrWhiteSpace($glpiUser)) { $glpiUser = "glpi" }
    if ([string]::IsNullOrWhiteSpace($glpiPass)) { $glpiPass = "md3F2eUv" }

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
            $setor  = Read-Host "2. Digite o SETOR (Ex: TI)"
            $nome   = Read-Host "3. Digite o NOME/LOGIN (Ex: joao.silva)"

            # Sanitizacao basica para remover caracteres invalidos de tags
            if ($filial) { $filial = $filial -replace '[ "&|]', '' }
            if ($setor)  { $setor  = $setor  -replace '[ "&|]', '' }
            if ($nome)   { $nome   = $nome   -replace '[ "&|]', '' }
            
        } while ([string]::IsNullOrWhiteSpace($filial) -or [string]::IsNullOrWhiteSpace($setor) -or [string]::IsNullOrWhiteSpace($nome))

        $finalTag = "$filial-$setor-$nome"
        $Global:GlpiTag = $finalTag
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

    # Limpando cache antigo para forçar envio de novo inventário
    Write-Log "Limpando cache antigo..." -Type Info -Color Yellow
    $storagePath = "C:\Program Files\GLPI-Agent\var\storage"
    if (Test-Path $storagePath) {
        Remove-Item -Path "$storagePath\*" -Recurse -Force -ErrorAction SilentlyContinue
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

    $Global:GlpiConfigured = $true
}
