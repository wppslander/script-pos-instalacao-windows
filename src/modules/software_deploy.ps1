# ==========================================
# MODULE: Software Deploy (Winget)
# Este modulo gerencia a instalacao de aplicativos corporativos
# utilizando Winget como motor principal, Chocolatey como fallback
# e instaladores MSI diretos para casos especificos (Chrome).
# ==========================================

function Install-ChocolateyEngine {
    <#
    .SYNOPSIS
        Instala o motor do Chocolatey caso nao esteja presente no sistema.
    .DESCRIPTION
        Verifica se o comando 'choco' existe. Se nao, executa o script oficial
        de instalacao via PowerShell, ajustando as politicas de execucao e protocolos de seguranca.
    #>
    # Verifica se o executavel do choco ja esta disponivel no PATH
    if (Get-Command "choco" -ErrorAction SilentlyContinue) {
        return $true
    }

    Write-Log "-> Chocolatey nao encontrado. Instalando..." -Type Warning
    try {
        # Define politica de execucao temporaria para permitir o script de instalacao
        Set-ExecutionPolicy Bypass -Scope Process -Force; 
        # Habilita suporte a TLS 1.2 (necessario para baixar do site do Chocolatey)
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
        # Baixa e executa o script de instalacao oficial
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Atualiza a variavel de ambiente PATH na sessao atual para reconhecer o novo binario
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        # Verifica novamente se a instalacao foi bem sucedida
        if (Get-Command "choco" -ErrorAction SilentlyContinue) {
            Write-Log "-> Chocolatey instalado com sucesso." -Type Success
            return $true
        }
    } catch {
        # Registra falha caso ocorra erro no download ou execucao
        Write-Log "Falha ao instalar Chocolatey: $_" -Type Error
        Register-Failure "Chocolatey Install" "Falha na instalacao do motor Choco: $_"
    }
    return $false
}

function Install-ChromeStandalone {
    <#
    .SYNOPSIS
        Instala o Google Chrome via MSI Enterprise Standalone.
    .DESCRIPTION
        Refatoracao critica: O Winget apresenta falhas frequentes de 'hash mismatch' no Chrome 
        devido ao delay entre o update do binario pela Google e a atualizacao do manifesto no Winget-PKGS.
        O uso do instalador MSI Enterprise garante a versao mais recente e instalacao silenciosa deterministica.
    #>
    Write-Log "Instalando Google Chrome (MSI Standalone)..." -Type Info -Color Green
    
    # URL direta para o instalador MSI Enterprise de 64 bits (sempre aponta para a ultima versao)
    $chromeMsiUrl = "https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi"
    # Local temporario para salvar o instalador
    $tempMsiPath = Join-Path $env:TEMP "GoogleChromeStandaloneEnterprise64.msi"

    try {
        Write-Log "-> Baixando instalador oficial da Google..." -Type Info
        # Baixa o arquivo MSI ignorando erros de parsing de HTML
        Invoke-WebRequest -Uri $chromeMsiUrl -OutFile $tempMsiPath -UseBasicParsing
        
        Write-Log "-> Executando instalacao MSI silenciosa..." -Type Info
        # Parametros MSIExec:
        # /i: Instalar
        # /qn: Quiet, No UI (Instalacao totalmente silenciosa)
        # /norestart: Impede que o computador reinicie automaticamente
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tempMsiPath`"", "/qn", "/norestart" -Wait -PassThru
        
        # Codigo 0 = Sucesso. Codigo 3010 = Sucesso (reinicializacao pendente).
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Log "-> Google Chrome instalado com sucesso." -Type Success
            return $true
        } else {
            Write-Log "-> Erro na instalacao do MSI. Codigo de saida: $($process.ExitCode)" -Type Error
            Register-Failure "Chrome Install" "MSI Exit Code: $($process.ExitCode)"
        }
    } catch {
        # Captura erros de rede ou permissao
        Write-Log "-> Falha critica no processo de instalacao do Chrome: $_" -Type Error
        Register-Failure "Chrome Install" "Exception: $_"
    } finally {
        # Garante que o arquivo temporario seja deletado para nao ocupar espaco
        if (Test-Path $tempMsiPath) {
            Write-Log "-> Limpando arquivo temporario..." -Type Info -Color DarkGray
            Remove-Item -Path $tempMsiPath -Force
        }
    }
    return $false
}

function Install-CorporateSoftware {
    <#
    .SYNOPSIS
        Orquestrador principal de deploy de software.
    .DESCRIPTION
        Lê a lista de pacotes do arquivo software_list.json e tenta instalar cada um.
        Utiliza Winget como primeira opcao, mas possui excecoes (Chrome) e fallback (Chocolatey).
    #>
    Write-Log "DEPLOY DE SOFTWARES CORPORATIVOS" -Type Info -Color Cyan

    # Sincroniza os catalogos locais com os servidores do Winget e MS Store
    Write-Log "Atualizando catalogos do Winget..." -Type Info -Color DarkGray
    try {
        $null = & winget source update --disable-interactivity 2>&1
    } catch {
        Write-Log "Nao foi possivel atualizar as fontes do Winget. Tentando instalar com cache atual..." -Type Warning
    }

    # --- CARREGAMENTO DA CONFIGURACAO ---
    # Define o caminho do JSON subindo dois niveis a partir de src/modules
    $jsonPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "software_list.json"
    $packages = @()

    if (Test-Path $jsonPath) {
        try {
            # Converte o arquivo JSON em um objeto PowerShell manipulavel
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

    # Se a lista estiver vazia, encerra a funcao
    if ($packages.Count -eq 0) {
        Write-Log "Nenhum pacote para instalar." -Type Info -Color DarkGray
        return
    }

    # Argumentos padrao para garantir que o Winget nao peça interacao humana
    $globalArgs = @(
        "--accept-package-agreements", # Aceita EULAs automaticamente
        "--accept-source-agreements",  # Aceita termos da fonte (ex: MS Store)
        "--silent",                    # Instalacao silenciosa
        "--force",                     # Forca se houver conflitos menores
        "--disable-interactivity"      # Garante que nao haja prompts
    )

    $success = 0
    $fail = 0
    
    # Variaveis para Barra de Progresso
    $totalPackages = $packages.Count
    $currentStep = 0

    # Itera sobre cada software definido no JSON
    foreach ($pkg in $packages) {
        $currentStep++
        $percentComplete = [math]::Round(($currentStep / $totalPackages) * 100)
        $progressPrefix = "[$currentStep/$totalPackages]"
        
        # Atualiza Barra de Progresso (Status Inicial)
        Write-Progress -Id 1 -Activity "Deploy de Software Corporativo" -Status "$progressPrefix Analisando $($pkg.Id)" -PercentComplete $percentComplete -CurrentOperation "Verificando instalacao..."

        Write-Log "$progressPrefix Verificando: $($pkg.Id)" -Type Info -Color Yellow
        
        # Verifica se o software ja esta no sistema para evitar reinstalacao desnecessaria
        $isInstalled = $false
        try {
            # winget list retorna 0 se encontrar o pacote exato
            $null = & winget list --id $pkg.Id --exact --source $pkg.Source 2>&1
            if ($LASTEXITCODE -eq 0) { $isInstalled = $true }
        } catch { }

        if ($isInstalled) {
            Write-Log "-> OK (Instalado)" -Type Info -Color Gray
            $success++
        } else {
            # --- CASO ESPECIAL: GOOGLE CHROME ---
            # Bypass Winget para evitar erros de hash mismatch recorrentes
            if ($pkg.Id -eq "Google.Chrome") {
                Write-Progress -Id 1 -Activity "Deploy de Software Corporativo" -Status "$progressPrefix Instalando Chrome (MSI)" -PercentComplete $percentComplete -CurrentOperation "Baixando e Instalando..."
                
                if (Install-ChromeStandalone) {
                    $success++
                } else {
                    $fail++
                }
                continue # Pula para o proximo item do loop
            }

            Write-Log "-> Instalando via Winget..." -Type Info -Color Green
            Write-Progress -Id 1 -Activity "Deploy de Software Corporativo" -Status "$progressPrefix Instalando $($pkg.Id)" -PercentComplete $percentComplete -CurrentOperation "Executando Winget..."
            
            # Monta os argumentos especificos do pacote
            $cmdArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
            
            # Adiciona localidade se especificado no JSON (ex: pt-BR)
            if ($pkg.Locale) {
                $cmdArgs += "--locale"
                $cmdArgs += $pkg.Locale
            }

            try {
                # Executa o comando winget
                & winget $cmdArgs
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "-> Sucesso (Winget)." -Type Success
                    $success++
                } else {
                    # Se falhar no Winget, inicia logica de fallback
                    $wingetFailed = $true
                    $wingetError = $LASTEXITCODE
                    
                    # TENTATIVA 1: Fallback removendo o locale (as vezes o locale pt-BR falha no Winget)
                    if ($pkg.Locale) {
                        Write-Log "-> Erro com locale. Tentando padrao..." -Type Warning
                        Write-Progress -Id 1 -Activity "Deploy de Software Corporativo" -Status "$progressPrefix Retry $($pkg.Id)" -PercentComplete $percentComplete -CurrentOperation "Winget (Sem Locale)..."
                        
                        $fallbackArgs = @("install", "--id", $pkg.Id, "--source", $pkg.Source, "--exact") + $globalArgs
                        & winget $fallbackArgs
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "-> Sucesso (Winget Fallback)." -Type Success
                            $success++
                            $wingetFailed = $false
                        }
                    }

                    # TENTATIVA 2: FALLBACK PARA CHOCOLATEY (Se houver ID de fallback configurado)
                    if ($wingetFailed -and $pkg.ChocoId) {
                        Write-Log "-> Falha no Winget ($wingetError). Tentando Chocolatey: $($pkg.ChocoId)..." -Type Info -Color Magenta
                        Write-Progress -Id 1 -Activity "Deploy de Software Corporativo" -Status "$progressPrefix Fallback $($pkg.Id)" -PercentComplete $percentComplete -CurrentOperation "Instalando via Chocolatey..."
                        
                        # Garante que o motor do Choco esta instalado
                        if (Install-ChocolateyEngine) {
                            try {
                                # Instala via Chocolatey com flag -y (Yes para tudo)
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
                    
                    # Se todas as tentativas falharem
                    if ($wingetFailed) {
                        Write-Log "-> FALHA (Erro: $wingetError) e sem sucesso no fallback." -Type Error
                        Register-Failure "Install $($pkg.Id)" "Winget: $wingetError"
                        $fail++
                    }
                }
            } catch {
                # Erro de excecao (ex: winget nao encontrado)
                Write-Log "-> Erro de execucao: $_" -Type Error
                Register-Failure "Install $($pkg.Id)" "Exception: $_"
                $fail++
            }
        }
    }
    
    # Remove a barra de progresso ao finalizar
    Write-Progress -Id 1 -Activity "Deploy de Software Corporativo" -Completed

    # Resumo final da etapa de deploy
    Write-Log "`nDeploy Finalizado. Sucesso: $success | Falhas: $fail" -Type Info -Color Cyan
}
