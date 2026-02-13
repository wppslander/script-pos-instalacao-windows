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
