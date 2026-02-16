@echo off
setlocal
cd /d "%~dp0"

:: 1. Verificacao de Admin
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Solicitando privilegios de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: 2. Launch Main PowerShell Script
:: Pass the current directory (%~dp0) as the RootPath argument
echo [INFO] Carregando modulos...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\main.ps1"

if %errorlevel% NEQ 0 (
    echo [ERRO] O script PowerShell falhou ou foi fechado inesperadamente.
    pause
)
