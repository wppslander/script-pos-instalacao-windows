# ==========================================
# MODULE: System Utilities
# Conjunto de ferramentas auxiliares para verificacao,
# configuracao de ambiente e auditoria (logs).
# ==========================================

function Enable-StoreSSLBypass {
    <#
    .SYNOPSIS
        Aplica correção no registro para permitir o funcionamento do Winget em redes corporativas.
    .DESCRIPTION
        Cria uma chave de registro que permite o bypass de certificate pinning para a Microsoft Store,
        resolvendo erros de conexao SSL em ambientes com inspeção de pacotes.
    #>
    Write-Host "1. Aplicando fix de SSL para Microsoft Store..." -ForegroundColor Cyan
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller"
    
    # Cria o caminho da pasta no registro se nao existir
    if (!(Test-Path $regPath)) { 
        New-Item -Path $regPath -Force | Out-Null 
    }
    
    try {
        # Define a propriedade para habilitar o bypass
        New-ItemProperty -Path $regPath -Name "EnableBypassCertificatePinningForMicrosoftStore" -Value 1 -PropertyType DWORD -Force | Out-Null
        Write-Host "-> Bypass aplicado." -ForegroundColor Green
    } catch {
        Write-Warning "Aviso: Falha ao escrever no registro (AV pode ter bloqueado)."
    }
}

function Write-Header {
    <#
    .SYNOPSIS
        Desenha um cabeçalho visual no console.
    #>
    param([string]$Title)
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "   $Title" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Test-InternetConnection {
    <#
    .SYNOPSIS
        Verifica se há conectividade com o mundo externo.
    .DESCRIPTION
        Tenta pingar o DNS do Google (8.8.8.8). Se falhar, alerta o usuário, 
        pois a maioria dos módulos depende de downloads.
    #>
    Write-Host "Verificando conexao com a internet..." -ForegroundColor DarkGray
    if (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet) {
        Write-Host "-> Conectado." -ForegroundColor Green
    } else {
        Write-Host "[ALERTA] Sem conexao com a internet detectada." -ForegroundColor Red
        Write-Host "A maioria das instalacoes (Winget/GLPI) falhara sem internet."
        $choice = Read-Host "Deseja continuar mesmo assim? (S/N)"
        if ($choice -notmatch "s|S") {
            Write-Host "Abortando." -ForegroundColor Red
            exit
        }
    }
}

function Get-CredentialValue {
    <#
    .SYNOPSIS
        Extrai valores de um arquivo de configuração (.env) estilo INI/Key-Value.
    .EXAMPLE
        Get-CredentialValue -Key "GLPI_SERVER" -FilePath "C:\temp\.env"
    #>
    param(
        [string]$Key,
        [string]$FilePath
    )
    
    # Verifica se o arquivo existe
    if (-not (Test-Path $FilePath)) { return $null }
    
    # Procura pela linha que começa com a chave especificada
    $line = Get-Content $FilePath | Where-Object { $_ -match "^$Key=" }
    
    if ($line) {
        # Divide a linha no '=' e pega a segunda parte (o valor)
        return ($line -split '=', 2)[1].Trim()
    }
    return $null
}

# ==========================================
# LOGGING & AUDIT
# Gerenciamento de logs em arquivo e resumo de erros.
# ==========================================

$Global:LogFile = $null
$Global:ExecutionFailures = @()

function Init-Logging {
    <#
    .SYNOPSIS
        Inicializa o sistema de logs criando um arquivo datado.
    #>
    # Localiza a raiz do projeto (dois níveis acima de src/modules)
    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $logDir = Join-Path $projectRoot "Logs"
    
    # Garante que a pasta Logs existe
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    
    # Nome do arquivo baseado na data e hora atual
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $Global:LogFile = Join-Path $logDir "Install_$timestamp.log"
    
    $startMsg = "=== LOG INICIADO EM $(Get-Date) ==="
    Set-Content -Path $Global:LogFile -Value $startMsg -Encoding UTF8
    Write-Host "Logs estao sendo salvos em: $Global:LogFile" -ForegroundColor DarkGray
}

function Write-Log {
    <#
    .SYNOPSIS
        Escreve uma mensagem tanto no console quanto no arquivo de log.
    .PARAMETER Type
        O tipo da mensagem (Info, Success, Warning, Error) para definir cores e prefixos.
    #>
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Type = "Info",
        [ConsoleColor]$Color = "Gray"
    )

    # Cores automáticas se o usuário não definir uma manualmente
    if ($Color -eq "Gray") {
        switch ($Type) {
            "Info"    { $Color = "White" }
            "Success" { $Color = "Green" }
            "Warning" { $Color = "Yellow" }
            "Error"   { $Color = "Red" }
        }
    }

    # Formata a linha de log com timestamp
    $prefix = "[$((Get-Date).ToString('HH:mm:ss'))] [$Type]"
    
    # Saída Visual (Console)
    Write-Host "$prefix $Message" -ForegroundColor $Color

    # Saída em Arquivo (Persistencia)
    if ($Global:LogFile) {
        Add-Content -Path $Global:LogFile -Value "$prefix $Message" -Encoding UTF8
    }
}

function Register-Failure {
    <#
    .SYNOPSIS
        Registra uma falha em uma lista global para exibicao no resumo final.
    #>
    param(
        [string]$Component, # Nome do modulo ou acao que falhou
        [string]$Message    # Descricao do erro
    )
    
    # Cria objeto de erro
    $failObj = [PSCustomObject]@{
        Component = $Component
        Message   = $Message
        Time      = Get-Date
    }
    # Adiciona ao array global
    $Global:ExecutionFailures += $failObj
    
    # Registra no log de arquivo imediatamente
    Write-Log -Message "FALHA REGISTRADA [$Component]: $Message" -Type Error
}

function Show-ExecutionSummary {
    <#
    .SYNOPSIS
        Exibe um relatório final da execução ao fechar o script.
    #>
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "   RESUMO DA EXECUCAO" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    if ($Global:ExecutionFailures.Count -eq 0) {
        # Caso tudo tenha ocorrido bem
        Write-Log -Message "Todos os modulos foram executados com SUCESSO!" -Type Success
    } else {
        # Lista todas as falhas acumuladas
        Write-Host "ATENCAO: Ocorreram falhas durante a execucao:" -ForegroundColor Red
        foreach ($fail in $Global:ExecutionFailures) {
            Write-Host " > [$($fail.Component)] $($fail.Message)" -ForegroundColor Red
        }
        Write-Log -Message "Verifique o log detalhado em: $Global:LogFile" -Type Warning
    }
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Register-AutoUpdateTask {
    <#
    .SYNOPSIS
        Instala e agenda o script de atualização automática.
    .DESCRIPTION
        Copia o script auto_update.ps1 para ProgramData e cria uma tarefa agendada
        para executá-lo semanalmente com privilégios de sistema.
    #>
    Write-Log "Configurando tarefa agendada de atualização..." -Type Info
    
    # 1. Definir caminhos
    $sourceScript = Join-Path $PSScriptRoot "auto_update.ps1"
    $destDir = "$env:ProgramData\GeminiPostInstall"
    $destScript = Join-Path $destDir "auto_update.ps1"
    
    # 2. Criar diretório de destino
    if (!(Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }
    
    # 3. Copiar script
    if (Test-Path $sourceScript) {
        Copy-Item -Path $sourceScript -Destination $destScript -Force
        Write-Log "Script de atualização copiado para: $destScript" -Type Success
    } else {
        Write-Log "ERRO CRITICO: Script de atualização não encontrado em $sourceScript" -Type Error
        Register-Failure "AutoUpdate" "Script fonte nao encontrado."
        return
    }
    
    # 4. Agendar Tarefa (Semanal, System, Run whether user is logged on or not)
    $taskName = "GeminiAutoUpdate"
    
    try {
        # Cria os objetos necessários para a tarefa agendada dentro do try para capturar erros de sintaxe/parâmetro
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destScript`""
        
        # Usamos o valor explícito do enum DayOfWeek para evitar ambiguidades de string em algumas versões de PS
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Wednesday -At 12:00
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Log "Tarefa '$taskName' agendada com sucesso (Toda Quarta @ 12:00)." -Type Success
    } catch {
        $errMsg = $_.Exception.Message
        Write-Log "Falha ao configurar tarefa agendada: $errMsg" -Type Error
        Register-Failure "AutoUpdate" "Falha no agendamento: $errMsg"
    }
}

function Disable-ServiceSafe {
    <#
    .SYNOPSIS
        Desativa um servico para que nao inicie no proximo boot.
    .PARAMETER ServiceName
        Nome do servico (ex: DiagTrack).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName
    )

    Write-Log "Desativando servico: $ServiceName..." -Type Info -Color DarkGray

    try {
        # 1. Desativa o inicio do servico (Operacao instantanea via Registro)
        # Isso garante que no proximo boot ele nao inicie, independente de estar rodando agora.
        Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue

        # 2. Tenta parar o servico de forma "Fire and Forget" (Nao aguarda o encerramento)
        # O parametro -NoWait impede que o PowerShell fique travado esperando o servico fechar.
        Stop-Service -Name $ServiceName -Force -NoWait -ErrorAction SilentlyContinue

        Write-Log "-> Servico $ServiceName configurado como DESATIVADO." -Type Success
    } catch {
        Write-Log "-> Nao foi possivel configurar o servico $ServiceName (pode nao existir)." -Type Info -Color DarkGray
    }
}

function Stop-ProcessIfRunning {
    <#
    .SYNOPSIS
        Fecha um processo se ele estiver em execução para evitar travamentos em instalações.
    .PARAMETER ProcessName
        Nome do processo (sem .exe).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProcessName
    )

    if (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
        Write-Log "Fechando processo ativo: $ProcessName..." -Type Warning
        try {
            Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2 # Pequena pausa para garantir a liberação de arquivos
        } catch {
            Write-Log "Nao foi possivel encerrar $ProcessName." -Type Warning
        }
    }
}

function Ensure-WinGet {
    <#
    .SYNOPSIS
        Verifica se o WinGet está instalado e funcional. Caso contrário, tenta realizar a instalação/reparo automático.
    #>
    Write-Log "Verificando se o WinGet esta instalado..." -Type Info -Color DarkGray
    
    if (Get-Command "winget" -ErrorAction SilentlyContinue) {
        Write-Log "-> WinGet ja esta instalado e disponivel." -Type Success
        return $true
    }
    
    Write-Log "WinGet nao detectado. Verificando conectividade para instalacao..." -Type Warning
    
    # Verifica conectividade simples antes de tentar baixar
    $hasInternet = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
    if (-not $hasInternet) {
        Write-Log "Instalacao do WinGet abortada: Sem conexao com a internet." -Type Error
        return $false
    }
    
    try {
        # 1. Habilita o provedor NuGet (necessário para baixar da PSGallery)
        Write-Log "Instalando provedor NuGet..." -Type Info -Color DarkGray
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop | Out-Null
        
        # 2. Configura a PSGallery como confiável temporariamente para evitar prompts interativos
        Write-Log "Configurando PSGallery como confiavel..." -Type Info -Color DarkGray
        Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        
        # 3. Instala o módulo oficial do WinGet se não estiver presente
        if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
            Write-Log "Instalando modulo Microsoft.WinGet.Client..." -Type Info -Color DarkGray
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Scope AllUsers -ErrorAction Stop | Out-Null
        } else {
            Write-Log "Modulo Microsoft.WinGet.Client ja esta presente." -Type Info -Color DarkGray
        }
        
        # 4. Importa o módulo para garantir que os cmdlets estejam disponíveis
        Import-Module Microsoft.WinGet.Client -ErrorAction Stop
        
        # 5. Executa a reinstalação/reparo do WinGet com todas as dependências
        try {
            Write-Log "Instalando/Reparando WinGet para todos os usuarios (isso pode levar alguns minutos)..." -Type Info -Color Cyan
            Repair-WinGetPackageManager -AllUsers -ErrorAction Stop
        } catch {
            Write-Log "Falha ao instalar para todos os usuarios. Tentando instalar para o usuario atual..." -Type Warning
            Repair-WinGetPackageManager -ErrorAction Stop
        }
        
        # 6. Atualiza a variável de ambiente PATH da sessão atual
        $windowsAppsPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$windowsAppsPath*") {
            $env:PATH += ";$windowsAppsPath"
        }
        
        # Verifica se passou a funcionar
        if (Get-Command "winget" -ErrorAction SilentlyContinue) {
            Write-Log "-> WinGet instalado e configurado com sucesso!" -Type Success
            return $true
        } else {
            throw "O comando 'winget' ainda nao esta disponivel no PATH apos o reparo."
        }
    } catch {
        $errMsg = $_.Exception.Message
        Write-Log "Falha ao instalar o WinGet: $errMsg" -Type Error
        Register-Failure "Winget-Install" "Nao foi possivel instalar o WinGet: $errMsg"
        return $false
    }
}

function Test-PreFlightChecks {    <#
    .SYNOPSIS
        Executa verificacoes de seguranca e ambiente antes de iniciar o menu.
    .DESCRIPTION
        1. Verifica se esta rodando como Administrador (Obrigatorio).
        2. Verifica se o Winget esta disponivel e tenta instalar se faltar.
        3. Verifica se ha reinicializacao pendente (Alerta).
    #>
    Write-Header "Pre-Flight Checks"

    # 1. Admin Check
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Register-Failure "Pre-Check" "Script executado sem privilegios de Admin."
        throw "ERRO CRITICO: Este script precisa ser executado como Administrador!"
    }
    Write-Host "[OK] Privilegios de Admin confirmados." -ForegroundColor Green

    # 2. Winget Check & Install
    $wingetOk = Ensure-WinGet
    if (-not $wingetOk) {
        Write-Warning "ALERTA: Winget nao detectado/instalado. A instalacao de softwares falhara."
    }

    # 3. Pending Reboot Check
    $rebootPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($path in $rebootPaths) {
        if (Test-Path $path) {
            Write-Warning "ALERTA: O Windows possui uma reinicializacao pendente (Windows Update/Componentes)."
            Write-Warning "Recomendado reiniciar antes de continuar para evitar erros em instalacoes."
            # Nao damos throw aqui para deixar o usuario decidir, mas avisamos.
            break
        }
    }
}
