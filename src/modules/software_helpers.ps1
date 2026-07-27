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

function Install-DirectSoftware {
    <#
    .SYNOPSIS
        Baixa um instalador de uma URL direta e instala-o silenciosamente.
    .DESCRIPTION
        Útil para softwares com pacotes do Winget/MS Store desatualizados ou instáveis.
        Suporta instaladores do tipo MSI e EXE.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [string]$Url,
        [Parameter(Mandatory=$true)]
        [string]$Id,
        [Parameter(Mandatory=$true)]
        [string]$Type,
        [string]$Args
    )
    
    Write-Log "Iniciando instalacao direta para $Id..." -Type Info -Color Cyan
    Write-Log "Download URL: $Url" -Type Info -Color DarkGray
    
    $tempDir = Join-Path $env:TEMP "DirectInstallers"
    if (!(Test-Path $tempDir)) {
        $null = New-Item -ItemType Directory -Path $tempDir -Force
    }
    
    $ext = if ($Type -eq "msi") { "msi" } else { "exe" }
    $tempFile = Join-Path $tempDir "$Id.$ext"
    
    try {
        # Habilita TLS 1.2 e TLS 1.3
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 -bor 12288
        
        # Faz o download do arquivo de instalacao
        Write-Log "Baixando arquivo temporario em $tempFile..." -Type Info -Color DarkGray
        Invoke-WebRequest -Uri $Url -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
        Write-Log "Download concluido com sucesso." -Type Success
        
        # Define os argumentos de instalacao silenciosa padrao
        $installArgs = $Args
        if ([string]::IsNullOrWhiteSpace($installArgs)) {
            if ($Type -eq "msi") {
                $installArgs = "/i `"$tempFile`" /quiet /norestart"
            } else {
                $installArgs = "/S"
            }
        } else {
            # Se for MSI, garante o /i do arquivo
            if ($Type -eq "msi" -and $installArgs -notmatch "/i") {
                $installArgs = "/i `"$tempFile`" $installArgs"
            }
        }
        
        Write-Log "Executando instalador silencioso..." -Type Info -Color DarkGray
        if ($Type -eq "msi") {
            Write-Log "Comando: msiexec.exe $installArgs" -Type Info -Color DarkGray
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -NoNewWindow -PassThru
        } else {
            Write-Log "Comando: $tempFile $installArgs" -Type Info -Color DarkGray
            $process = Start-Process -FilePath $tempFile -ArgumentList $installArgs -Wait -NoNewWindow -PassThru
        }
        
        # Retornos validos (0: OK, 3010: OK porem necessita reboot)
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "Instalacao direta de $Id concluida com sucesso (ExitCode: $($process.ExitCode))." -Type Success
            # Limpa o arquivo temporario
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            return $true
        } else {
            Write-Log "O instalador retornou codigo de erro: $($process.ExitCode)" -Type Error
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        Write-Log "Erro durante o download ou instalacao direta de $($Id): $_" -Type Error
        return $false
    }
}

