# ==========================================
# MODULE: System Utilities
# ==========================================

function Enable-StoreSSLBypass {
    Write-Host "1. Aplicando fix de SSL para Microsoft Store..." -ForegroundColor Cyan
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller"
    
    if (!(Test-Path $regPath)) { 
        New-Item -Path $regPath -Force | Out-Null 
    }
    
    try {
        New-ItemProperty -Path $regPath -Name "EnableBypassCertificatePinningForMicrosoftStore" -Value 1 -PropertyType DWORD -Force | Out-Null
        Write-Host "-> Bypass aplicado." -ForegroundColor Green
    } catch {
        Write-Warning "Aviso: Falha ao escrever no registro (AV pode ter bloqueado)."
    }
}

function Write-Header {
    param([string]$Title)
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "   $Title" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Test-InternetConnection {
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
    param(
        [string]$Key,
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) { return $null }
    
    if ($line) {
        return ($line -split '=', 2)[1].Trim()
    }
    return $null
}

# ==========================================
# LOGGING & AUDIT
# ==========================================

$Global:LogFile = $null
$Global:ExecutionFailures = @()

function Init-Logging {
    # Define logs na raiz do projeto (mesma pasta do script executado/raiz)
    # $PSScriptRoot aqui eh src/modules. Voltamos 2 niveis para a raiz.
    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $logDir = Join-Path $projectRoot "Logs"
    
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $Global:LogFile = Join-Path $logDir "Install_$timestamp.log"
    
    $startMsg = "=== LOG INICIADO EM $(Get-Date) ==="
    Set-Content -Path $Global:LogFile -Value $startMsg -Encoding UTF8
    Write-Host "Logs estao sendo salvos em: $Global:LogFile" -ForegroundColor DarkGray
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Type = "Info",
        [ConsoleColor]$Color = "Gray"
    )

    # Cores padrao se nao especificado
    if ($Color -eq "Gray") {
        switch ($Type) {
            "Info"    { $Color = "White" }
            "Success" { $Color = "Green" }
            "Warning" { $Color = "Yellow" }
            "Error"   { $Color = "Red" }
        }
    }

    # Console Output
    $prefix = "[$((Get-Date).ToString('HH:mm:ss'))] [$Type]"
    Write-Host "$prefix $Message" -ForegroundColor $Color

    # File Output
    if ($Global:LogFile) {
        Add-Content -Path $Global:LogFile -Value "$prefix $Message"
    }
}

function Register-Failure {
    param(
        [string]$Component,
        [string]$Message
    )
    
    $failObj = [PSCustomObject]@{
        Component = $Component
        Message   = $Message
        Time      = Get-Date
    }
    $Global:ExecutionFailures += $failObj
    
    # Tambem loga como erro
    Write-Log -Message "FALHA REGISTRADA [$Component]: $Message" -Type Error
}

function Show-ExecutionSummary {
    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host "   RESUMO DA EXECUCAO" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    if ($Global:ExecutionFailures.Count -eq 0) {
        Write-Log -Message "Todos os modulos foram executados com SUCESSO!" -Type Success
    } else {
        Write-Host "ATENCAO: Ocorreram falhas durante a execucao:" -ForegroundColor Red
        foreach ($fail in $Global:ExecutionFailures) {
            Write-Host " > [$($fail.Component)] $($fail.Message)" -ForegroundColor Red
        }
        Write-Log -Message "Verifique o log detalhado em: $Global:LogFile" -Type Warning
    }
    Write-Host "========================================================" -ForegroundColor Cyan
}
