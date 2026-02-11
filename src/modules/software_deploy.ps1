# ==========================================
# MODULE: Software Deploy (Winget)
# ==========================================

function Install-ChocolateyEngine {
    if (Get-Command "choco" -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-Log "-> Chocolatey nao encontrado. Instalando..." -Type Warning
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force; 
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Recarrega variaveis de ambiente
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (Get-Command "choco" -ErrorAction SilentlyContinue) {
            Write-Log "-> Chocolatey instalado com sucesso." -Type Success
            return $true
        }
    } catch {
        Write-Log "Falha ao instalar Chocolatey: $_" -Type Error
        Register-Failure "Chocolatey Install" "Falha na instalacao do motor Choco: $_"
    }
    return $false
}

function Install-CorporateSoftware {
    Write-Log "DEPLOY DE SOFTWARES CORPORATIVOS" -Type Info -Color Cyan

    # Atualiza as fontes do Winget
    Write-Log "Atualizando catalogos do Winget..." -Type Info -Color DarkGray
    try {
        $null = & winget source update --disable-interactivity 2>&1
    } catch {
        Write-Log "Nao foi possivel atualizar as fontes do Winget. Tentando instalar com cache atual..." -Type Warning
    }

    # --- LISTA DE PACOTES (CARREGADA DE JSON) ---
    $jsonPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "software_list.json"
    $packages = @()

    if (Test-Path $jsonPath) {
        try {
            $packages = Get-Content $jsonPath -Raw | ConvertFrom-Json
            Write-Log "Lista de softwares carregada de $jsonPath" -Type Info -Color Cyan
        } catch {
            Write-Log "Falha ao ler software_list.json (Softfail). Erro: $_" -Type Warning
            Register-Failure "Software Config" "Erro ao ler JSON: $_"
            Write-Log "Nenhum software sera instalado nesta etapa." -Type Warning
        }
    } else {
        Write-Log "Arquivo software_list.json nao encontrado em $jsonPath (Softfail)." -Type Warning
        Register-Failure "Software Config" "Arquivo JSON nao encontrado."
        Write-Log "Nenhum software sera instalado nesta etapa." -Type Warning
    }

    if ($packages.Count -eq 0) {
        Write-Log "Nenhum pacote para instalar." -Type Info -Color DarkGray
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
        Write-Log "Verificando: $($pkg.Id)" -Type Info -Color Yellow
        
        $isInstalled = $false
        try {
            $null = & winget list --id $pkg.Id --exact --source $pkg.Source 2>&1
            if ($LASTEXITCODE -eq 0) { $isInstalled = $true }
        } catch { }

        if ($isInstalled) {
            Write-Log "-> OK (Instalado)" -Type Info -Color Gray
            $success++
        } else {
            Write-Log "-> Instalando via Winget..." -Type Info -Color Green
            
            $cmdArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
            
            if ($pkg.Locale) {
                $cmdArgs += "--locale"
                $cmdArgs += $pkg.Locale
            }

            try {
                & winget $cmdArgs
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "-> Sucesso (Winget)." -Type Success
                    $success++
                } else {
                    $wingetFailed = $true
                    $wingetError = $LASTEXITCODE
                    
                    # Tenta fallback PT-BR se aplicavel
                    if ($pkg.Locale) {
                        Write-Log "-> Erro com locale. Tentando padrao..." -Type Warning
                        $fallbackArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
                        & winget $fallbackArgs
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "-> Sucesso (Winget Fallback)." -Type Success
                            $success++
                            $wingetFailed = $false
                        }
                    }

                    # FALLBACK CHOCOLATEY
                    if ($wingetFailed -and $pkg.ChocoId) {
                        Write-Log "-> Falha no Winget ($wingetError). Tentando Chocolatey: $($pkg.ChocoId)..." -Type Info -Color Magenta
                        
                        if (Install-ChocolateyEngine) {
                            try {
                                & choco install $pkg.ChocoId -y --no-progress
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Log "-> Sucesso (Chocolatey)." -Type Success
                                    $success++
                                    $wingetFailed = $false
                                } else {
                                    Write-Log "-> Falha tambem no Chocolatey." -Type Warning
                                }
                            } catch {
                                Write-Log "-> Erro ao executar Chocolatey." -Type Warning
                            }
                        }
                    } 
                    
                    if ($wingetFailed) {
                        Write-Log "-> FALHA (Erro: $wingetError) e sem sucesso no fallback." -Type Error
                        Register-Failure "Install $($pkg.Id)" "Winget: $wingetError"
                        $fail++
                    }
                }
            } catch {
                Write-Log "-> Erro de execucao: $_" -Type Error
                Register-Failure "Install $($pkg.Id)" "Exception: $_"
                $fail++
            }
        }
    }

    Write-Log "`nDeploy Finalizado. Sucesso: $success | Falhas: $fail" -Type Info -Color Cyan
}
