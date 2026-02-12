# 📝 Todo List - Melhorias Futuras

Este documento rastreia ideias de melhorias, refatorações e novas funcionalidades para o **Windows Post-Installation Suite**.

## 🛡️ Segurança
- [ ] **Criptografia de Credenciais**: Substituir o `credentials.txt` (texto plano) por um arquivo criptografado (DPAPI) ou `PSCredential` exportado, para evitar expor a senha do GLPI/Proxy.
- [ ] **Assinatura de Code**: Assinar os scripts `.ps1` digitalmente para permitir execução em políticas de `AllSigned` (aumentando a segurança contra modificações maliciosas).

## 🚀 Novas Funcionalidades
- [ ] **Módulo de Debloat**: Criar `src/modules/sys_debloat.ps1` para:
    - [ ] Remover Apps nativos indesejados (Candy Crush, Xbox, News, Solitaire).
    - [x] Desabilitar Telemetria básica.
- [ ] **Windows Updates**: Adicionar etapa para forçar a verificação e instalação de atualizações do Windows Update (modulo `PSWindowsUpdate`).
- [ ] **Drivers de Fabricante**: Integração com ferramentas de update de BIOS/Drivers (Dell Command Update, Lenovo System Update, HP Image Assistant).
- [ ] **Menu de Seleção (GUI/TUI)**: Permitir que o usuário marque/desmarque softwares específicos antes de iniciar a instalação (usando `Out-GridView` ou Windows Forms simples).

## ⚙️ Engenharia e Robustez
- [ ] **Retry Logic Otimizado**: Melhorar a resiliência do `Install-CorporateSoftware`. Se o Winget falhar por hash mismatch, tentar limpar o cache local automaticamente e tentar novamente.
- [ ] **Log no Event Viewer**: Além do arquivo de log, registrar eventos críticos no "Event Viewer" do Windows para auditoria de TI.
- [ ] **Validação de Hash**: Implementar verificação de integridade dos arquivos críticos (`software_list.json`, `main.ps1`) antes da execução.

## 🎨 Experiência do Usuário (UX)
- [ ] **Barra de Progresso**: Implementar `Write-Progress` no loop de instalação para mostrar visualmente quanto falta (Ex: "Instalando 3 de 15: Google Chrome...").
- [ ] **Resumo Rico**: Ao final, gerar um HTML simples com o relatório do que falhou e o que funcionou, além do log em texto.

## 🔧 DevOps & CI/CD
- [ ] **GitHub Actions**: Criar workflow para rodar o `PSScriptAnalyzer` (Linter) a cada Push/PR.
- [ ] **Testes Unitários**: Criar testes com **Pester** para validar funções isoladas (ex: validar se o JSON está bem formatado, se os URLs de ping respondem).
