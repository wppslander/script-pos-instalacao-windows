<# :
@echo off
setlocal enabledelayedexpansion

:: Captura o caminho completo do script e seu diretorio
SET "SCRIPT_PATH=%~f0"
SET "SCRIPT_DIR=%~dp0"

:: 1. Verificacao de Admin e Elevacao automatica
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Solicitando privilegios de Administrador...
    set "ARGS="
    for %%a in (%*) do set ARGS=!ARGS! "%%a"
    powershell -Command "Start-Process '%~f0' -ArgumentList '!ARGS!' -Verb RunAs"
    exit /b
)

:: Mudar para o diretorio do script para garantir caminhos relativos corretos
cd /d "%SCRIPT_DIR%"

:: =====================================================================
:: CONFIGURAÇÃO DE VALORES PADRÃO (FALLBACK CASO CREDENTIALS.TXT NÃO EXISTA)
:: =====================================================================
SET "GLPI_SERVER=https://glpi.i.digitalsat.com.br/front/inventory.php"
SET "GLPI_USER=glpi"
SET "GLPI_PASS=md3F2eUv"
SET "GLPI_TAG="

:: =====================================================================
:: CARREGAR CREDENCIAIS DO credentials.txt SE EXISTIR
:: =====================================================================
if exist "credentials.txt" (
    for /f "usebackq tokens=1* delims==" %%i in ("credentials.txt") do (
        if "%%i"=="GLPI_SERVER" set "GLPI_SERVER=%%j"
        if "%%i"=="GLPI_USER" set "GLPI_USER=%%j"
        if "%%i"=="GLPI_PASSWORD" set "GLPI_PASS=%%j"
    )
)

:: =====================================================================
:: PARSEAMENTO E VALIDAÇÃO DOS ARGUMENTOS DO SCRIPT
:: =====================================================================
:ParseArgs
if "%~1"=="" goto CheckArgs
if /I "%~1"=="--tag" (
    if "%~2"=="" (
        echo [!] ERRO: O parametro --tag requer um valor.
        goto AskForTag
    )
    SET "GLPI_TAG=%~2"
    shift
    shift
    goto ParseArgs
) else (
    echo [!] ERRO: Parametro invalido: %1
    goto Usage
)

:CheckArgs
if "%GLPI_TAG%"=="" goto AskForTag
goto RunPowerShell

:: Caso não tenha sido passada a tag por parâmetro, solicita via teclado
:AskForTag
echo.
echo =====================================================================
echo               RECONFIGURACAO DO AGENTE GLPI
echo =====================================================================
echo.
set /p "GLPI_TAG=Por favor, digite a nova TAG (ex: MATRIZ-joao.silva): "
if "%GLPI_TAG%"=="" (
    echo [!] ERRO: A tag e obrigatoria. Finalizando.
    pause
    exit /b 1
)
goto RunPowerShell

:Usage
echo.
echo Uso correto:
echo    %~nx0 --tag "Nome Da Tag"
echo.
pause
exit /b 1

:RunPowerShell
echo.
echo --- Reconfigurando Conexao GLPI Agent para Tag: %GLPI_TAG% ---
echo.

:: Exporta variáveis para o contexto do processo para o PowerShell herdar via $env:
set "GLPI_SERVER=%GLPI_SERVER%"
set "GLPI_USER=%GLPI_USER%"
set "GLPI_PASS=%GLPI_PASS%"
set "GLPI_TAG=%GLPI_TAG%"

:: PowerShell extrai apenas o código abaixo do '#>' usando Regex e executa com Invoke-Expression
powershell -NoProfile -ExecutionPolicy Bypass -Command "$script = Get-Content -LiteralPath '%SCRIPT_PATH%' -Raw; if ($script -match '(?s)#>[\r\n]+(.*)') { Invoke-Expression $Matches[1] } else { Write-Error 'Bloco PowerShell nao encontrado.' }"

echo.
echo --- Processo Finalizado ---
echo.
pause
exit /b 0
#>

# =====================================================================
# POWERSHELL LOGIC - REGISTRY EDIT
# =====================================================================
$regPath = "HKLM:\SOFTWARE\GLPI-Agent"
$storagePath = "C:\Program Files\GLPI-Agent\var\storage"

if (-not (Test-Path $regPath)) {
    Write-Error "[ERRO] GLPI Agent nao encontrado no registro. Instale o agente primeiro."
    exit 1
}

# Validação do valor da variável de ambiente que veio do Batch
if ([string]::IsNullOrEmpty($env:GLPI_TAG)) {
    Write-Error "[ERRO] A variavel GLPI_TAG nao foi definida."
    exit 1
}

Write-Host "[1/4] Atualizando chaves de registro..." -ForegroundColor Cyan
try {
    # Define as propriedades do registro baseadas nas variáveis de ambiente
    Set-ItemProperty -Path $regPath -Name "server" -Value $env:GLPI_SERVER
    Set-ItemProperty -Path $regPath -Name "user" -Value $env:GLPI_USER
    Set-ItemProperty -Path $regPath -Name "password" -Value $env:GLPI_PASS
    Set-ItemProperty -Path $regPath -Name "tag" -Value $env:GLPI_TAG
    
    Write-Host "[OK] Registro atualizado com a tag: $env:GLPI_TAG" -ForegroundColor Green
    Write-Host "     Servidor: $env:GLPI_SERVER" -ForegroundColor Gray
} catch {
    Write-Error "[FALHA] Erro ao gravar no registro: $_"
    exit 1
}

Write-Host "[2/4] Limpando cache antigo..." -ForegroundColor Cyan
if (Test-Path $storagePath) {
    # Remove recursivamente os arquivos dentro da pasta de storage para forçar nova identificação
    Remove-Item -Path "$storagePath\*" -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "[OK] Cache limpo." -ForegroundColor Green

Write-Host "[3/4] Reiniciando servico glpi-agent..." -ForegroundColor Cyan
$svc = Get-Service -Name "glpi-agent" -ErrorAction SilentlyContinue

if ($svc) {
    Restart-Service -Name "glpi-agent" -Force
    Write-Host "[OK] Servico reiniciado com as novas configuracoes." -ForegroundColor Green
} else {
    Write-Warning "[AVISO] Servico nao encontrado. Apenas o registro foi alterado."
}

Write-Host "[4/4] Solicitando inventario imediato..." -ForegroundColor Cyan
$agentExe = "C:\Program Files\GLPI-Agent\glpi-agent.bat"
if (Test-Path $agentExe) {
    # Executa o agente manualmente para enviar o inventário inicial após a alteração da tag
    & $agentExe --force --logger=stderr
    Write-Host "[OK] Comando de inventario executado." -ForegroundColor Green
} else {
    Write-Host "[FALHA] O arquivo de lote do agente nao foi encontrado no caminho padrao." -ForegroundColor Red
}
