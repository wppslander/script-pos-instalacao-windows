# ==========================================
# MODULE: Software Deploy (Winget)
# ==========================================

function Install-ChocolateyEngine {
    if (Get-Command "choco" -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-Host "-> Chocolatey nao encontrado. Instalando..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force; 
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Recarrega variaveis de ambiente para usar o 'choco' imediatamente
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (Get-Command "choco" -ErrorAction SilentlyContinue) {
            Write-Host "-> Chocolatey instalado com sucesso." -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Warning "Falha ao instalar Chocolatey: $_"
    }
    return $false
}

function Install-CorporateSoftware {
    Write-Header "DEPLOY DE SOFTWARES CORPORATIVOS"

    # Atualiza as fontes do Winget
    Write-Host "Atualizando catalogos do Winget..." -ForegroundColor DarkGray
    try {
        $null = & winget source update --disable-interactivity 2>&1
    } catch {
        Write-Warning "Nao foi possivel atualizar as fontes do Winget. Tentando instalar com cache atual..."
    }

    # --- LISTA DE PACOTES (CARREGADA DE JSON) ---
    $jsonPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "software_list.json"
    $packages = @()

    if (Test-Path $jsonPath) {
        try {
            $packages = Get-Content $jsonPath -Raw | ConvertFrom-Json
            Write-Host "Lista de softwares carregada de $jsonPath" -ForegroundColor Cyan
        } catch {
            Write-Warning "Falha ao ler software_list.json (Softfail). Erro: $_"
            Write-Warning "Nenhum software sera instalado nesta etapa."
        }
    } else {
        Write-Warning "Arquivo software_list.json nao encontrado em $jsonPath (Softfail)."
        Write-Warning "Nenhum software sera instalado nesta etapa."
    }

    if ($packages.Count -eq 0) {
        Write-Host "Nenhum pacote para instalar." -ForegroundColor DarkGray
        return
    }

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
            Write-Host "-> Instalando via Winget..." -ForegroundColor Green
            
            $cmdArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
            
            if ($pkg.Locale) {
                $cmdArgs += "--locale"
                $cmdArgs += $pkg.Locale
            }

            try {
                & winget $cmdArgs
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "-> Sucesso (Winget)." -ForegroundColor Green
                    $success++
                } else {
                    $wingetFailed = $true
                    
                    # Tenta fallback PT-BR se aplicavel
                    if ($pkg.Locale) {
                        Write-Host "-> Erro com locale. Tentando padrao..." -ForegroundColor DarkYellow
                        $fallbackArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
                        & winget $fallbackArgs
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "-> Sucesso (Winget Fallback)." -ForegroundColor Green
                            $success++
                            $wingetFailed = $false
                        }
                    }

                    # FALLBACK CHOCOLATEY
                    if ($wingetFailed -and $pkg.ChocoId) {
                        Write-Host "-> Falha no Winget ($LASTEXITCODE). Tentando Chocolatey: $($pkg.ChocoId)..." -ForegroundColor Magenta
                        
                        if (Install-ChocolateyEngine) {
                            try {
                                & choco install $pkg.ChocoId -y --no-progress
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Host "-> Sucesso (Chocolatey)." -ForegroundColor Green
                                    $success++
                                    $wingetFailed = $false
                                } else {
                                    Write-Warning "-> Falha tambem no Chocolatey."
                                }
                            } catch {
                                Write-Warning "-> Erro ao executar Chocolatey."
                            }
                        }
                    } elseif ($wingetFailed) {
                        Write-Host "-> FALHA (Erro: $LASTEXITCODE) e sem fallback configurado." -ForegroundColor Red
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
}
