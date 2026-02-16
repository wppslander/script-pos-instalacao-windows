# ==========================================
# MODULE: Software Helpers
# Funcoes auxiliares para instalacao e configuracao de softwares.
# Isoladas para manter o codigo limpo e modular.
# ==========================================

function Install-ChocolateyEngine {
    <#
    .SYNOPSIS
        Instala o motor do Chocolatey caso nao esteja presente no sistema.
    .DESCRIPTION
        Verifica se o comando 'choco' existe. Se nao, executa o script oficial
        de instalacao via PowerShell, ajustando as politicas de execucao e protocolos de seguranca.
    #>
    # Verifica se o executavel do choco ja esta disponivel no PATH
    if (Get-Command "choco" -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-Log "-> Chocolatey nao encontrado. Instalando..." -Type Warning
    try {
        # Define politica de execucao temporaria para permitir o script de instalacao
        Set-ExecutionPolicy Bypass -Scope Process -Force; 
        # Habilita suporte a TLS 1.2 (necessario para baixar do site do Chocolatey)
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
        # Baixa e executa o script de instalacao oficial
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Atualiza a variavel de ambiente PATH na sessao atual para reconhecer o novo binario
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        # Verifica novamente se a instalacao foi bem sucedida
        if (Get-Command "choco" -ErrorAction SilentlyContinue) {
            Write-Log "-> Chocolatey instalado com sucesso." -Type Success
            return $true
        }
    } catch {
        # Registra falha caso ocorra erro no download ou execucao
        Write-Log "Falha ao instalar Chocolatey: $_" -Type Error
        Register-Failure "Chocolatey Install" "Falha na instalacao do motor Choco: $_"
    }
    return $false
}

function Install-ChromeStandalone {
    <#
    .SYNOPSIS
        Instala o Google Chrome via MSI Enterprise Standalone.
    .DESCRIPTION
        Refatoracao critica: O Winget apresenta falhas frequentes de 'hash mismatch' no Chrome 
        devido ao delay entre o update do binario pela Google e a atualizacao do manifesto no Winget-PKGS.
        O uso do instalador MSI Enterprise garante a versao mais recente e instalacao silenciosa deterministica.
    #>
    Write-Log "Instalando Google Chrome (MSI Standalone)..." -Type Info -Color Green
    
    # URL direta para o instalador MSI Enterprise de 64 bits (sempre aponta para a ultima versao)
    $chromeMsiUrl = "https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi"
    # Local temporario para salvar o instalador
    $tempMsiPath = Join-Path $env:TEMP "GoogleChromeStandaloneEnterprise64.msi"

    try {
        Write-Log "-> Baixando instalador oficial da Google..." -Type Info
        # Baixa o arquivo MSI ignorando erros de parsing de HTML
        Invoke-WebRequest -Uri $chromeMsiUrl -OutFile $tempMsiPath -UseBasicParsing
        
        Write-Log "-> Executando instalacao MSI silenciosa..." -Type Info
        # Parametros MSIExec:
        # /i: Instalar
        # /qn: Quiet, No UI (Instalacao totalmente silenciosa)
        # /norestart: Impede que o computador reinicie automaticamente
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tempMsiPath`"", "/qn", "/norestart" -Wait -PassThru
        
        # Codigo 0 = Sucesso. Codigo 3010 = Sucesso (reinicializacao pendente).
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "-> Google Chrome instalado com sucesso." -Type Success
            return $true
        } else {
            Write-Log "-> Erro na instalacao do MSI. Codigo de saida: $($process.ExitCode)" -Type Error
            Register-Failure "Chrome Install" "MSI Exit Code: $($process.ExitCode)"
        }
    } catch {
        # Captura erros de rede ou permissao
        Write-Log "-> Falha critica no processo de instalacao do Chrome: $_" -Type Error
        Register-Failure "Chrome Install" "Exception: $_"
    } finally {
        # Garante que o arquivo temporario seja deletado para nao ocupar espaco
        if (Test-Path $tempMsiPath) {
            Write-Log "-> Limpando arquivo temporario..." -Type Info -Color DarkGray
            Remove-Item -Path $tempMsiPath -Force
        }
    }
    return $false
}

function Configure-FlameshotAutoStart {
    <#
    .SYNOPSIS
        Configura o Flameshot para iniciar com o Windows.
    .DESCRIPTION
        Objetivo: "Ativar o flameshot, habilitar ele inicar automaticamente"
        Adiciona a entrada no registro HKCU\Run.
    #>
    Write-Log "CONFIGURACAO DO FLAMESHOT (AUTO-START)" -Type Info -Color Cyan

    # Caminhos comuns de instalacao do Flameshot via Winget/Choco
    $potentialPaths = @(
        "$env:LOCALAPPDATA\Programs\Flameshot\bin\flameshot.exe",
        "$env:ProgramFiles\Flameshot\bin\flameshot.exe",
        "$env:ProgramFiles (x86)\Flameshot\bin\flameshot.exe"
    )

    $flameshotPath = $null
    foreach ($path in $potentialPaths) {
        if (Test-Path $path) {
            $flameshotPath = $path
            break
        }
    }

    if ($flameshotPath) {
        Write-Log "Executavel do Flameshot encontrado em: $flameshotPath" -Type Info -Color DarkGray
        $regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        
        try {
            # Define o valor no registro para iniciar automaticamente
            Set-ItemProperty -Path $regKey -Name "Flameshot" -Value "`"$flameshotPath`"" -Type String -Force -ErrorAction Stop
            Write-Log "-> Flameshot configurado para iniciar com o Windows." -Type Success
        } catch {
            Write-Log "-> Falha ao configurar auto-start do Flameshot: $_" -Type Warning
        }
    } else {
        Write-Log "-> Flameshot nao encontrado. O auto-start nao foi configurado." -Type Info -Color DarkGray
    }
}
