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

    # --- LISTA DE PACOTES (EDITE AQUI) ---
    $packages = @(
        # Diagnostico/Acesso
        [PSCustomObject]@{Id = "AnyDesk.AnyDesk";                 Source = "winget"; Locale = $null},
        [PSCustomObject]@{Id = "WinDirStat.WinDirStat";           Source = "winget"; Locale = $null},
        [PSCustomObject]@{Id = "CrystalDewWorld.CrystalDiskInfo"; Source = "winget"; Locale = $null},

        # Navegadores / Email
        [PSCustomObject]@{Id = "Google.Chrome";                 Source = "winget"; Locale = "pt-BR"},
        [PSCustomObject]@{Id = "Mozilla.Firefox";               Source = "winget"; Locale = "pt-BR"},
        [PSCustomObject]@{Id = "Mozilla.Thunderbird.pt-BR";     Source = "winget"; Locale = $null},

        # Produtividade
        [PSCustomObject]@{Id = "ONLYOFFICE.DesktopEditors";     Source = "winget"; Locale = $null}, 
        [PSCustomObject]@{Id = "Adobe.Acrobat.Reader.64-bit";   Source = "winget"; Locale = "pt-BR"},
        [PSCustomObject]@{Id = "Microsoft.Teams";               Source = "winget"; Locale = "pt-BR"},
        [PSCustomObject]@{Id = "MicroSIP.MicroSIP";             Source = "winget"; Locale = $null}, 

        # Ferramentas Tecnicas
        [PSCustomObject]@{Id = "RaMMicHaeL.Unchecky";           Source = "winget"; Locale = $null},
        [PSCustomObject]@{Id = "voidtools.Everything";          Source = "winget"; Locale = $null},
        [PSCustomObject]@{Id = "MartiCliment.UniGetUI";         Source = "winget"; Locale = $null},
        
        # Utilitarios
        [PSCustomObject]@{Id = "7zip.7zip";                     Source = "winget"; Locale = $null},
        [PSCustomObject]@{Id = "VideoLAN.VLC";                  Source = "winget"; Locale = $null},
        [PSCustomObject]@{Id = "Flameshot.Flameshot";           Source = "winget"; Locale = $null},
        [PSCustomObject]@{Id = "Microsoft.VCRedist.2015+.x64";  Source = "winget"; Locale = $null},

        # Store Only
        [PSCustomObject]@{Id = "9NKSQGP7F2NH";                  Source = "msstore"; Locale = $null} # WhatsApp
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
}
