# ========================================================================
# Rotina de Atualização Limpa via Winget (Task Scheduler)
# ========================================================================

# Array estrito de pacotes seguros para atualização autônoma (KISS)
$safeToUpdate = @(
    "7zip.7zip",
    "VideoLAN.VLC",
    "voidtools.Everything",
    "WinDirStat.WinDirStat",
    "CrystalDewWorld.CrystalDiskInfo",
    "Flameshot.Flameshot",
    "MartiCliment.UniGetUI",
    "ONLYOFFICE.DesktopEditors"
)

Write-Host "Iniciando verificação de atualizações..."

foreach ($app in $safeToUpdate) {
    Write-Host "Verificando/Atualizando: $app"
    # --id garante o pacote exato
    # --silent e accept-agreements garantem zero interação do usuário
    winget upgrade --id $app --exact --silent --accept-package-agreements --accept-source-agreements
}
