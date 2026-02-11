# ==========================================
# MODULE: Software Deploy (Winget)
# ==========================================

function Install-CorporateSoftware {
    Write-Header "DEPLOY DE SOFTWARES CORPORATIVOS"

    # Atualiza as fontes do Winget (Corrige falhas de 'Pacote nao encontrado' no MS Store)
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
            # Le o JSON e converte para objetos
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

    # Se a lista estiver vazia, encerra a funcao sem erro
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
}
