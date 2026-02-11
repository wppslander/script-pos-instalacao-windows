# ==========================================
# MODULE: GLPI Agent Installer
# ==========================================

function Install-GlpiAgent {
    Write-Header "CONFIGURACAO GLPI AGENT"

    # Carregar Credenciais
    $credFile = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "credentials.txt"
    
    $glpiServer = Get-CredentialValue -Key "GLPI_SERVER" -FilePath $credFile
    $glpiUser   = Get-CredentialValue -Key "GLPI_USER" -FilePath $credFile
    $glpiPass   = Get-CredentialValue -Key "GLPI_PASSWORD" -FilePath $credFile

    # Fallback/Defaults
    if ([string]::IsNullOrWhiteSpace($glpiServer)) { 
        $glpiServer = "http://glpi.d.digitalsat.com.br/front/inventory.php" 
        Write-Warning "GLPI_SERVER nao encontrado em credentials.txt. Usando padrao."
    }
    if ([string]::IsNullOrWhiteSpace($glpiUser)) { $glpiUser = "teste" }
    if ([string]::IsNullOrWhiteSpace($glpiPass)) { $glpiPass = "teste" }

    Write-Host "Servidor GLPI: $glpiServer" -ForegroundColor DarkGray

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
    Write-Host "`nTAG LIMPA: $finalTag" -ForegroundColor Cyan
    
    $null = Read-Host "Pressione ENTER para confirmar e instalar via Winget"

    # 2. Instalar via Winget
    Write-Host "Instalando GLPI Agent via Winget... (Aguarde)" -ForegroundColor Yellow
    
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
        "install", "--id", "GLPI-Project.GLPIAgent",
        "--source", "winget",
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements", 
        "--silent", 
        "--override", "$overrideStr"
    )

    try {
        Write-Host "Executando: winget $(($wingetArgs -join ' ') -replace 'PASSWORD=.*? ', 'PASSWORD=*** ')" -ForegroundColor DarkGray
        
        & winget $wingetArgs

        if ($LASTEXITCODE -eq 0) {
             Write-Host "[SUCESSO] GLPI Instalado." -ForegroundColor Green
        } else {
             Write-Host "[ERRO] Winget retornou erro: $LASTEXITCODE" -ForegroundColor Red
        }
    } catch {
        Write-Host "[ERRO] Falha ao executar winget: $_" -ForegroundColor Red
    }

    # 3. Pos-Instalacao (Inventory Force)
    Write-Host "Aguardando servico iniciar..."
    Start-Sleep -Seconds 5
    
    $agentBin = "C:\Program Files\GLPI-Agent\glpi-agent.bat"
    if (Test-Path $agentBin) {
        Write-Host "Forcando inventario..." -ForegroundColor Yellow
        Start-Process -FilePath $agentBin -ArgumentList "--force" -Wait
        Write-Host "Inventario enviado." -ForegroundColor Green
    } else {
        Write-Warning "Script do agente nao encontrado. O servico enviara os dados automaticamente."
    }
}
