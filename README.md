# 🚀 UniFi UDM Pro Branch Provisioning: Terraform + PowerShell IaC

![Terraform](https://img.shields.io/badge/Terraform-1.0+-623CE4.svg?style=flat-square&logo=terraform)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE.svg?style=flat-square&logo=powershell)
![UniFi OS](https://img.shields.io/badge/UniFi_OS-REST_API-005C9A.svg?style=flat-square&logo=ubiquiti)

Solução automatizada de Infraestrutura como Código (IaC) para provisionamento, padronização e hardening de redes, regras de firewall e *Traffic Rules v2* em múltiplos consoles UniFi UDM Pro (ou Gateways UniFi OS).

## 💡 Arquitetura e Problema Resolvido

O provedor oficial do UniFi para Terraform (`paultyng/unifi`) cobre configurações de rede padrão, mas apresenta gaps críticos de automação para operações em larga escala. Este projeto atua como um **wrapper de IaC**, combinando Terraform para gerenciamento de estado suportado e chamadas REST API via PowerShell para cobrir as limitações da API oficial.

**Limitações contornadas por este projeto:**
1. **Renomeação do Console:** O endpoint `super_identity` não é suportado pelo provider nativo.
2. **Atribuição Estática via MAC:** Injeção de IPs estáticos para switches e APs (ex: `.2`, `.5`) diretamente na reserva do DHCP, sem depender do recurso `unifi_device`.
3. **Traffic Rules v2:** Suporte ausente no Terraform para bloqueio de domínios, Geo-IP e App Filtering.

## 🛠️ Capacidades de Provisionamento

- **Identity Management:** Padronização automatizada do hostname do UDM Pro (`F[ID_Loja] - [Nome] - [UF]`).
- **Dynamic Subnetting:** Cálculo matemático da sub-rede LAN e escopo DHCP baseado no ID da Filial (ex: Loja `151` → `192.168.151.0/24` | VLAN `151`).
- **Device Onboarding:** Adoção, renomeação e amarração de IP estático via reserva DHCP:
  - `x.x.x.1` - Gateway/Firewall
  - `x.x.x.2` - Switch Core
  - `x.x.x.5` - Access Point
- **Firewall & Hardening (WAN_LOCAL):** Regras restritas para instâncias de monitoramento (Zabbix, Prometheus, AWS) e restrição de acesso SSH.
- **Traffic Rules (API REST):**
  - **DNS/Domain Block:** Bloqueio de domínios maliciosos ou não corporativos.
  - **Geo-IP Blocking:** Restrição de tráfego bidirecional para países de alto risco (ex: CN, RU, KP).
  - **L3/L4 Blocklists:** Restrição explícita a sub-redes ou IPs específicos.

## 📁 Estrutura do Repositório

```text
├── .gitignore               # Exclusão de credenciais, tfstate local e plugins
├── providers.tf             # Configuração do provedor UniFi (Variáveis de Ambiente)
├── main.tf                  # Core resources (Redes, Dispositivos e Regras Nativas)
├── variables.tf             # Schemas de validação e tipagem de variáveis
├── terraform.tfvars.example # Template de variáveis por filial
├── scripts/
│   ├── rename_udm.ps1       # Interação REST API: super_identity
│   └── traffic_rules.ps1    # Interação REST API: Traffic Rules v2
⚙️ Pré-requisitos
Binários: Terraform v1.0+ e PowerShell 5.1+ (Recomendado PS Core 7+).

Acesso: Conta de serviço (Service Account) com privilégios de Super Admin ou Owner no controlador destino.

Rede: Acesso HTTPS (443) à interface de gerência do UDM Pro.

🚀 Pipeline de Execução
1. Parametrização da Filial
Gere o arquivo de variáveis baseado no template:

Bash
cp terraform.tfvars.example terraform.tfvars
Edite o arquivo terraform.tfvars com os metadados da localidade:

Terraform
loja_id    = "0151"
loja_nome  = "Colombia"
estado_uf  = "PR"
device_mac = "28:70:4e:89:c8:4d"
switch_mac = "00:11:22:33:44:55"  # Omitir se inexistente
ap_mac     = "00:11:22:33:44:66"  # Omitir se inexistente
2. Injeção de Credenciais (Zero-Trust)
Nunca commite credenciais ou as insira em .tfvars. Exporte-as diretamente para a sessão do terminal (ou utilize secrets do GitHub Actions/GitLab CI):

PowerShell
$env:UNIFI_USERNAME = "svc_unifi_tf"
$env:UNIFI_PASSWORD = "Password_Complexa_Vault"
$env:UNIFI_API_URL  = "[https://192.168.1.1:443](https://192.168.1.1:443)"
3. Deploy da Infraestrutura
Execute o ciclo de vida do Terraform:

Bash
terraform init   # Download de providers e inicialização do backend
terraform plan   # Validação do plano de execução e diff de estado
terraform apply  # Aplicação paralela (Terraform + Execução de Scripts)
Aviso de Estado: Garanta que o estado (.tfstate) esteja sendo armazenado em um backend remoto (S3, Azure Blob, ou Terraform Cloud) se executado em equipe.


---

### 🛡️ Análise Crítica e Estratégica da Arquitetura

O modelo que você desenhou resolve o problema imediato de falta de cobertura do provedor Terraform, mas a abordagem híbrida (Terraform + Scripts *local-exec* ou *null_resource*) gera um risco arquitetônico severo: **A quebra de gerenciamento de estado e idempotência.**

#### O Problema da Abordagem Atual
O Terraform opera baseado em estado (`.tfstate`). Ele compara o que você deseja (código) com o que existe (estado remoto). Quando você delega a criação de *Traffic Rules* ou *Renomeação* para um script PowerShell, o Terraform é "cego" para o resultado final dessas operações.

**Exemplo prático de falha:**
1. O Terraform roda o script PowerShell e cria a Regra de Bloqueio Geo-IP.
2. Um analista júnior entra na interface web do UniFi e apaga ou altera essa regra.
3. No próximo `terraform plan`, o Terraform **não detectará a mudança**, pois o script PowerShell já foi executado no passado e o recurso `null_resource` no Terraform consta como concluído. A infraestrutura sofreu um *drift* (desvio de configuração) invisível.

#### Abordagens de Solução (Comparativo)

| Abordagem | Idempotência | Complexidade de Manutenção | Visibilidade de Drift | Recomendação |
| :--- | :--- | :--- | :--- | :--- |
| **Terraform + PS Scripts Simples** (Sua atual) | 🔴 Nula | 🟢 Baixa | 🔴 Nenhuma | Apenas para PoC ou deploy único (sem gerência contínua). |
| **Terraform + PS Scripts Idempotentes** | 🟡 Parcial | 🟡 Média | 🟡 Parcial (Requer lógica complexa no PS) | Exige que o script PowerShell faça um `GET` na API antes, verifique se a regra existe/foi alterada, e só então faça o `POST`/`PUT`. |
| **Terraform + Custom Provider (Go)** | 🟢 Total | 🔴 Alta (Requer desenvolvimento) | 🟢 Total | A solução definitiva. Escrever/contribuir com os recursos faltantes no provider oficial. |
| **Pipeline CI/CD (Ansible/Python) Exclusivo** | 🟢 Total | 🟡 Média | 🟡 Parcial | Se a API do UniFi não tem bom suporte no Terraform, usar Ansible (que é desenhado para execução procedural/estado desejado via módulos customizados) costuma ser mais eficiente que forçar o Terraform com PowerShell. |

**Minha recomendação para alavancagem de resultado:**
Se você precisa manter Terraform e PowerShell, você **deve** tornar seus scripts `rename_udm.ps1` e `traffic_rules.ps1` idempotentes. Eles não podem apenas fazer chamadas POST. A lógica interna do PowerShell deve ser:
1. Autenticar.
2. Fazer `GET` das regras atuais.
3. Comparar o *hash* ou os valores das regras atuais com os parâmetros do `.tfvars` (passados como argumentos para o script).
4. Se iguais, sair com código `0` (não fazer nada).
5. Se diferentes ou inexistentes, fazer `PUT`/`POST` e atualizar.

Configure o Terraform para usar gatilhos (`triggers`) no `null_resource`, forçando a re-execução do script b
