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
    
    $line = Get-Content $FilePath | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($line) {
        return ($line -split '=', 2)[1].Trim()
    }
    return $null
}
