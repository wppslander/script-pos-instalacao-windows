# ==========================================
# MODULE: GLPI Agent Installer
# ==========================================

function Install-GlpiAgent {
    Write-Log "CONFIGURACAO GLPI AGENT" -Type Info -Color Cyan
    
    # Carregar Credenciais
    $credFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "credentials.txt"
    
    $glpiServer = Get-CredentialValue -Key "GLPI_SERVER" -FilePath $credFile
    $glpiUser   = Get-CredentialValue -Key "GLPI_USER" -FilePath $credFile
    $glpiPass   = Get-CredentialValue -Key "GLPI_PASSWORD" -FilePath $credFile

    # Fallback/Defaults
    if ([string]::IsNullOrWhiteSpace($glpiServer)) { 
        $glpiServer = "http://glpi.yourcompany.com/front/inventory.php" 
        Write-Log "GLPI_SERVER nao encontrado em credentials.txt. Usando padrao." -Type Warning
    }
    if ([string]::IsNullOrWhiteSpace($glpiUser)) { $glpiUser = "teste" }
    if ([string]::IsNullOrWhiteSpace($glpiPass)) { $glpiPass = "teste" }

    Write-Log "Servidor GLPI: $glpiServer" -Type Info -Color DarkGray

    # 0. Verificacao de Conectividade (Fail Fast / Softfail)
    Write-Log "Verificando alcance do servidor GLPI..." -Type Info -Color DarkGray
    try {
        $request = Invoke-WebRequest -Uri $glpiServer -Method Head -TimeoutSec 5 -ErrorAction Stop
        if ($request.StatusCode -eq 200) {
            Write-Log "-> Servidor GLPI acessivel." -Type Success
        }
    } catch {
        Write-Log "Falha ao contactar servidor GLPI ($glpiServer). Erro: $_" -Type Warning
        Register-Failure "GLPI Check" "Servidor inalcançavel ou erro de rede."
        
        $choice = Read-Host "Deseja tentar a instalacao mesmo assim? (S/N)"
        if ($choice -notmatch "s|S") {
            Write-Log "Instalacao do GLPI abortada pelo usuario (Softfail)." -Type Warning
            return
        }
    }

    # 1. Input (Mantido)
    do {
        Write-Host "`n--- DADOS DO EQUIPAMENTO ---" -ForegroundColor Yellow
        $filial = Read-Host "1. Digite a FILIAL (Ex: MATRIZ)"
        $user = Read-Host "2. Digite o LOGIN SANKHYA (Ex: joao.silva)"

        # Sanitizacao
        if ($filial) { $filial = $filial -replace '[ "&|]', '' }
        if ($user) { $user = $user -replace '[ "&|]', '' }
        
    } while ([string]::IsNullOrWhiteSpace($filial) -or [string]::IsNullOrWhiteSpace($user))

    $finalTag = "$filial-$user"
    Write-Log "TAG LIMPA: $finalTag" -Type Info -Color Cyan
    
    $null = Read-Host "Pressione ENTER para confirmar e instalar via Winget"

    # 2. Instalar via Winget
    Write-Log "Instalando GLPI Agent via Winget... (Aguarde)" -Type Info -Color Yellow
    
    # Definir parametros do MSI para passar via --override
    # Nota: --override substitui todos os args padrao, entao precisamos incluir /quiet /norestart
    $glpiArgs = "SERVER=""$glpiServer"" " +
                "USER=""$glpiUser"" " +
                "PASSWORD=""$glpiPass"" " +
                "TAG=""$finalTag"" " +
                "EXECMODE=Service " +
                "RUNNOW=1"

    $overrideStr = "/quiet /norestart $glpiArgs"

    $wingetArgs = @(
        "install", "--id", "GLPI-Project.GLPI-Agent",
        "--source", "winget",
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements", 
        "--silent", 
        "--override", "$overrideStr"
    )

    try {
        Write-Log "Executando: winget $(($wingetArgs -join ' ') -replace 'PASSWORD=.*? ', 'PASSWORD=*** ')" -Type Info -Color DarkGray
        
        & winget $wingetArgs

        if ($LASTEXITCODE -eq 0) {
             Write-Log "[SUCESSO] GLPI Instalado." -Type Success
        } else {
             Write-Log "[ERRO] Winget retornou erro: $LASTEXITCODE" -Type Error
             Register-Failure "GLPI Install" "Winget falhou com codigo $LASTEXITCODE"
        }
    } catch {
        Write-Log "[ERRO] Falha ao executar winget: $_" -Type Error
        Register-Failure "GLPI Install" "Excecao ao rodar Winget: $_"
    }

    # 3. Pos-Instalacao (Inventory Force)
    Write-Log "Aguardando servico iniciar..." -Type Info
    Start-Sleep -Seconds 5
    
    $agentBin = "C:\Program Files\GLPI-Agent\glpi-agent.bat"
    if (Test-Path $agentBin) {
        Write-Log "Forcando inventario..." -Type Info -Color Yellow
        try {
            Start-Process -FilePath $agentBin -ArgumentList "--force" -Wait
            Write-Log "Inventario enviado." -Type Success
        } catch {
            Write-Log "Erro ao executar inventario manual: $_" -Type Warning
            Register-Failure "GLPI Inventory" "Falha ao rodar glpi-agent.bat --force"
        }
    } else {
        Write-Log "Script do agente nao encontrado ($agentBin). O servico enviara os dados automaticamente." -Type Warning
    }
}
