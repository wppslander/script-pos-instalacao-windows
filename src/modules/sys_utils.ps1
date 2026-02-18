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
        Extrai valores de um arquivo de configuração (.txt) estilo INI/Key-Value.
    .EXAMPLE
        Get-CredentialValue -Key "GLPI_SERVER" -FilePath "C:\temp\credentials.txt"
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
        Add-Content -Path $Global:LogFile -Value "$prefix $Message"
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
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destScript`""
    $trigger = New-ScheduledTaskTrigger -Weekly -Days Wednesday -At 12:00
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Log "Tarefa '$taskName' agendada com sucesso (Toda Quarta @ 12:00)." -Type Success
    } catch {
        $errMsg = $_.Exception.Message
        Write-Log "Falha ao agendar tarefa: $errMsg" -Type Error
        Register-Failure "AutoUpdate" "Falha no agendamento: $errMsg"
    }
}

function Test-PreFlightChecks {
    <#
    .SYNOPSIS
        Executa verificacoes de seguranca e ambiente antes de iniciar o menu.
    .DESCRIPTION
        1. Verifica se esta rodando como Administrador (Obrigatorio).
        2. Verifica se o Winget esta disponivel (Alerta).
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

    # 2. Winget Check
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
         Register-Failure "Pre-Check" "Winget nao encontrado no PATH."
         Write-Warning "ALERTA: Winget nao detectado. A instalacao de softwares falhara."
    } else {
        Write-Host "[OK] Winget detectado." -ForegroundColor Green
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
