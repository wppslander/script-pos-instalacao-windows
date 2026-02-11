# Suíte de Pós-Instalação Digital Sat

**Objetivo do Projeto**: Este repositório contém uma suíte de scripts modular, automatizada e de fácil manutenção projetada para a configuração pós-instalação de estações de trabalho Windows 11 na Digital Sat. Ele combina gerenciamento de privilégios administrativos, ajustes de sistema, implantação do Agente GLPI e instalação de softwares em massa via `winget`.

---

## 🚀 Como Usar

1.  **Baixe** ou **Clone** este repositório na máquina alvo (ou em um Pen Drive).
2.  **Edite o arquivo `credentials.txt`** (opcional) se precisar alterar o servidor GLPI ou usuário/senha.
3.  **Clique duas vezes** em `bootstrap.bat`.
4.  **Confirme** a solicitação do Controle de Conta de Usuário (UAC) para permitir privilégios de Administrador.
5.  **Siga as instruções na tela**:
    -   O script verificará a conexão com a internet automaticamente.
    -   Digite a **FILIAL** (ex: MATRIZ).
    -   Digite o **USUÁRIO SANKHYA** (ex: joao.silva).
    -   Confirme a TAG gerada.
6.  **Aguarde** a conclusão da instalação. O script instalará o Agente GLPI, a lista padrão de softwares corporativos e configurará o UniGetUI.

---

## 📂 Estrutura do Projeto

O projeto está organizado em uma estrutura modular para facilitar a manutenção e atualizações.

```
/ (Raiz)
├── bootstrap.bat             # Ponto de entrada. Gerencia elevação e inicia o PowerShell.
├── credentials.txt           # Arquivo de configuração (Servidor GLPI, Usuário, Senha).
├── src/
    ├── main.ps1              # Script orquestrador principal.
    └── modules/
        ├── sys_utils.ps1     # Utilitários (Internet Check, Fix SSL, Leitura de Credenciais).
        ├── glpi_installer.ps1 # Instalação do Agente GLPI via Winget.
        ├── software_deploy.ps1 # Instalação de Softwares (Winget).
        └── unigetui_config.ps1 # Configuração pós-install do UniGetUI.
```

---

## 🛠 Manutenção e Personalização

### Configuração do GLPI (`credentials.txt`)
O arquivo `credentials.txt` permite alterar o servidor sem mexer no código:
```ini
GLPI_SERVER=http://glpi.d.digitalsat.com.br/front/inventory.php
GLPI_USER=teste
GLPI_PASSWORD=teste
```

### Adicionando ou Removendo Softwares
Para modificar a lista de aplicativos instalados:
1.  Abra `src/modules/software_deploy.ps1`.
2.  Edite o array `$packages` adicionando ou removendo linhas.

---

## 🔍 Solução de Problemas

-   **Sem Internet**: O script avisa no início se não houver conexão com o Google DNS (8.8.8.8).
-   **WhatsApp Falhando**: O script executa `winget source update` automaticamente para corrigir erros de catálogo da MS Store.
-   **Configuração do UniGetUI**: As configurações (UAC único, Auto-Update) são aplicadas em `%LOCALAPPDATA%\UniGetUI\settings.json`.

---

**Autor**: Daniel Wppslander (@wppslander)
