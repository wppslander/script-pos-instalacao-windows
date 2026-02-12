# 📝 Todo / Roadmap

Lista de melhorias planejadas para futuras versões do script.

- [ ] **Logging e Auditoria**: Implementar função `Write-Log` para salvar histórico de execução em arquivo (ex: `C:\Logs\install.log`).
- [ ] **Interface Gráfica (GUI)**: Substituir `Read-Host` por uma janela de input (WinForms/WPF) para Filial e Usuário.
- [ ] **Retry no Winget**: Adicionar loop de tentativa (3x) para instalações de software para mitigar falhas de rede.
- [ ] **Modo "Dry Run"**: Criar parâmetro `-WhatIf` para simular a execução sem aplicar mudanças.
- [ ] **Validação de Disco**: Verificar espaço em disco antes de iniciar as instalações.
- [ ] **Notificação Final**: Enviar email ou mensagem (Teams/Slack) ao finalizar a instalação com sucesso.
