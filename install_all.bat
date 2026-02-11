<# : batch script portion
@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

:: 1. Verificacao de Admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Solicitando privilegios de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: 2. Handover para o PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ((Get-Content '%~f0' -Raw) -replace '(?s)^.*?<#', '<#')"
goto :EOF
: end batch / begin powershell #>

$host.UI.RawUI.WindowTitle = "Instalador Unificado - Digital Sat"

# ==================================================================================
# 1. FIX: Bypass SSL Microsoft Store
# ==================================================================================
Write-Host "1. Aplicando fix de SSL para Microsoft Store..." -ForegroundColor Cyan
$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppInstaller"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
try {
    New-ItemProperty -Path $regPath -Name "EnableBypassCertificatePinningForMicrosoftStore" -Value 1 -PropertyType DWORD -Force | Out-Null
    Write-Host "-> Bypass aplicado." -ForegroundColor Green
} catch {
    Write-Warning "Aviso: Falha ao escrever no registro (AV pode ter bloqueado)."
}

# ==================================================================================
# 2. INSTALACAO GLPI AGENT
# ==================================================================================
Write-Host "`n2. Configurando GLPI Agent..." -ForegroundColor Cyan

# 2.1 Auto-detectar MSI
$msiFile = Get-ChildItem -Path . -Filter *.msi | Select-Object -First 1

if (-not $msiFile) {
    Write-Host "[ERRO] Nenhum arquivo .msi encontrado nesta pasta." -ForegroundColor Red
    Write-Host "O script e o instalador devem estar juntos."
    Write-Host "Pulando instalacao do GLPI..." -ForegroundColor DarkGray
} else {
    Write-Host "Instalador detectado: $($msiFile.Name)" -ForegroundColor Green

    # 2.2 Input
    do {
        Write-Host "`n--- CADASTRO DE EQUIPAMENTO ---" -ForegroundColor Yellow
        $filial = Read-Host "1. Digite a FILIAL (Ex: MATRIZ)"
        $user = Read-Host "2. Digite o LOGIN SANKHYA (Ex: joao.silva)"

        # Sanitizacao (Removendo espacos e caracteres perigosos)
        if ($filial) { $filial = $filial -replace '[ "&|]', '' }
        if ($user) { $user = $user -replace '[ "&|]', '' }
        
    } while ([string]::IsNullOrWhiteSpace($filial) -or [string]::IsNullOrWhiteSpace($user))

    $finalTag = "$filial-$user"
    Write-Host "`nTAG LIMPA: $finalTag" -ForegroundColor Cyan
    
    $confirm = Read-Host "Pressione ENTER para confirmar e instalar"

    # 2.3 Instalar
    Write-Host "Instalando GLPI Agent... (Aguarde)" -ForegroundColor Yellow
    
    $msiArgs = @(
        "/i", "`"$($msiFile.FullName)`"",
        "/quiet", "/norestart",
        "SERVER=`"http://glpi.d.digitalsat.com.br/front/inventory.php`"",
        "USER=`"teste`"",
        "PASSWORD=`"teste`"",
        "TAG=`"$finalTag`"",
        "EXECMODE=Service",
        "RUNNOW=1"
    )

    try {
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Host "[ERRO] O instalador retornou erro: $($proc.ExitCode)" -ForegroundColor Red
        } else {
             Write-Host "[SUCESSO] GLPI Instalado." -ForegroundColor Green
        }
    } catch {
        Write-Host "[ERRO] Falha ao executar msiexec: $_" -ForegroundColor Red
    }

    # 2.4 Pos-Instalacao (Inventory Force)
    Write-Host "Aguardando servico iniciar..."
    Start-Sleep -Seconds 5
    
    $agentBin = "C:\Program Files\GLPI-Agent\glpi-agent.bat"
    if (Test-Path $agentBin) {
        Write-Host "Forcando inventario..." -ForegroundColor Yellow
        Start-Process -FilePath $agentBin -ArgumentList "--force" -Wait
        Write-Host "Inventario enviado." -ForegroundColor Green
    } else {
        Write-Warning "Script do agente nao encontrado em $agentBin. O servico enviara os dados automaticamente."
    }
}

# ==================================================================================
# 3. SOFTWARE DEPLOY (WINGET)
# ==================================================================================
Write-Host "`n3. Iniciando deploy de softwares corporativos..." -ForegroundColor Cyan

# Lista de Pacotes
$packages = @(
    # --- Diagnostico/Acesso ---
    [PSCustomObject]@{Id = "AnyDesk.AnyDesk";                 Source = "winget"; Locale = $null},
    [PSCustomObject]@{Id = "WinDirStat.WinDirStat";           Source = "winget"; Locale = $null},
    [PSCustomObject]@{Id = "CrystalDewWorld.CrystalDiskInfo"; Source = "winget"; Locale = $null},

    # --- Navegadores / Email ---
    [PSCustomObject]@{Id = "Google.Chrome";                 Source = "winget"; Locale = "pt-BR"},
    [PSCustomObject]@{Id = "Mozilla.Firefox";               Source = "winget"; Locale = "pt-BR"},
    [PSCustomObject]@{Id = "Mozilla.Thunderbird.pt-BR";     Source = "winget"; Locale = $null},

    # --- Produtividade ---
    [PSCustomObject]@{Id = "ONLYOFFICE.DesktopEditors";     Source = "winget"; Locale = $null}, 
    [PSCustomObject]@{Id = "Adobe.Acrobat.Reader.64-bit";   Source = "winget"; Locale = "pt-BR"},
    [PSCustomObject]@{Id = "Microsoft.Teams";               Source = "winget"; Locale = "pt-BR"},
    [PSCustomObject]@{Id = "MicroSIP.MicroSIP";               Source = "winget"; Locale = $null}, 

    # --- Ferramentas Tecnicas ---
    [PSCustomObject]@{Id = "RaMMicHaeL.Unchecky";           Source = "winget"; Locale = $null},
    [PSCustomObject]@{Id = "voidtools.Everything";          Source = "winget"; Locale = $null},
    [PSCustomObject]@{Id = "MartiCliment.UniGetUI";         Source = "winget"; Locale = $null},
    
    # --- Utilitarios ---
    [PSCustomObject]@{Id = "7zip.7zip";                     Source = "winget"; Locale = $null},
    [PSCustomObject]@{Id = "VideoLAN.VLC";                  Source = "winget"; Locale = $null},
    [PSCustomObject]@{Id = "Flameshot.Flameshot";           Source = "winget"; Locale = $null},
    [PSCustomObject]@{Id = "Microsoft.VCRedist.2015+.x64";  Source = "winget"; Locale = $null},

    # --- Store Only ---
    [PSCustomObject]@{Id = "9NKSQGP7F2NH";                  Source = "msstore"; Locale = $null}
)

$globalArgs = @(
    "--accept-package-agreements",
    "--accept-source-agreements", 
    "--silent", 
    "--force",
    "--disable-interactivity" 
)

$success = 0
$fail = 0

foreach ($pkg in $packages) {
    Write-Host "Verificando: $($pkg.Id)" -ForegroundColor Yellow
    
    $isInstalled = $false
    try {
        $null = & winget list --id $pkg.Id --exact --source $pkg.Source 2>&1
        if ($LASTEXITCODE -eq 0) { $isInstalled = $true }
    } catch { }

    if ($isInstalled) {
        Write-Host "-> OK (Instalado)" -ForegroundColor Gray
        $success++
    } else {
        Write-Host "-> Instalando..." -ForegroundColor Green
        
        $cmdArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
        
        if ($pkg.Locale) {
            $cmdArgs += "--locale"
            $cmdArgs += $pkg.Locale
        }

        try {
            & winget $cmdArgs
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "-> Sucesso." -ForegroundColor Green
                $success++
            } else {
                if ($pkg.Locale) {
                    Write-Host "-> Erro com PT-BR. Tentando padrao..." -ForegroundColor DarkYellow
                    $fallbackArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
                    & winget $fallbackArgs
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "-> Sucesso (Fallback)." -ForegroundColor Green
                        $success++
                    } else {
                        Write-Host "-> FALHA (Erro: $LASTEXITCODE)" -ForegroundColor Red
                        $fail++
                    }
                } else {
                    Write-Host "-> FALHA (Erro: $LASTEXITCODE)" -ForegroundColor Red
                    $fail++
                }
            }
        } catch {
            Write-Host "-> Erro de execucao: $_" -ForegroundColor Red
            $fail++
        }
    }
}

Write-Host "`nDeploy Finalizado. Sucesso: $success | Falhas: $fail" -ForegroundColor Cyan
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
