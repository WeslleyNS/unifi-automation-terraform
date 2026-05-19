🚀 Automação de Provisionamento de Filiais UniFi UDM Pro com Terraform e PowerShell
Este projeto fornece uma solução automatizada de Infraestrutura como Código (IaC) para provisionar e padronizar redes, grupos de firewall, regras de firewall e regras de tráfego avançadas (Traffic Rules v2) em múltiplos consoles UniFi UDM Pro (ou qualquer Gateway UniFi OS).

💡 Por que este projeto existe?
Embora o provedor oficial do UniFi para Terraform (paultyng/unifi ou suas bifurcações) seja excelente para configurações padrão, ele possui algumas limitações importantes no momento:

Não consegue renomear o próprio console/gateway UDM Pro (gerenciado no endpoint super_identity).
Não suporta a configuração de IPs estáticos diretamente pelo recurso unifi_device para switches/APs.
Não possui suporte para as novas Regras de Tráfego v2 (bloqueio de domínios, bloqueio de países por Geo-IP, bloqueio de aplicativos, etc.).
Este projeto resolve essas limitações combinando os recursos nativos do Terraform com scripts em PowerShell que interagem diretamente com a API REST interna e não documentada do UniFi OS.

🛠️ Funcionalidades
Renomeação do Console: Altera o nome do gateway UDM Pro para o padrão da empresa (F[ID_Loja] - [Nome] - [UF]).
Endereçamento de Rede Dinâmico: Calcula e provisiona automaticamente a sub-rede LAN corporativa e o escopo DHCP com base no ID da Loja (ex: a loja 151 recebe a sub-rede 192.168.151.0/24 com a VLAN 151).
Gerenciamento de Dispositivos e IPs Estáticos: Adota, renomeia switches/APs e atribui IPs estáticos através de reservas DHCP permanentes:
Gateway/Firewall: .1
Switch: .2
Access Point (AP): .5
Regras de Segurança WAN_LOCAL: Cria regras de firewall padronizadas para servidores de monitoramento (Zabbix/AWS) e controle de acesso SSH.
Regras de Tráfego Avançadas v2 (Via API): Utiliza scripts em PowerShell para enviar blocos de segurança diretamente para a API do UniFi:
Bloqueio de domínios (ex: bloqueio de domínios indesejados ou maliciosos).
Bloqueio por Geo-IP / Região (ex: bloquear tráfego de/para países de alto risco como China ou Rússia).
Lista de bloqueio de IPs/Sub-redes.
📁 Estrutura do Repositório
text


├── .gitignore               # Impede o envio de arquivos .tfstate, plugins e credenciais para o Git
├── providers.tf             # Configuração do provedor UniFi (ajustado para variáveis de ambiente)
├── main.tf                  # Definição principal da infraestrutura (Redes, Dispositivos e Regras)
├── variables.tf             # Schema das variáveis de entrada
├── terraform.tfvars.example # Modelo de arquivo para preenchimento de variáveis da filial
├── rename_udm.ps1           # Script para renomear o UDM Pro via API REST
└── traffic_rules.ps1        # Script para configurar as Traffic Rules v2 via API REST
⚙️ Pré-requisitos
Terraform v1.0+ instalado.
PowerShell 5.1+ (PowerShell 7+ recomendado).
Conta com privilégios de Super Administrador (Owner ou Super Admin) no controlador UniFi de destino.
🚀 Como Executar
1. Configurar as Variáveis da Filial
Faça uma cópia do arquivo terraform.tfvars.example renomeando-o para terraform.tfvars:

bash


cp terraform.tfvars.example terraform.tfvars
Abra o arquivo terraform.tfvars e preencha com os dados da filial correspondente:

hcl


loja_id    = "0151"
loja_nome  = "Colombia"
estado_uf  = "PR"
device_mac = "28:70:4e:89:c8:4d"
switch_mac = "00:11:22:33:44:55"  # Deixe vazio se não houver switch dedicado
ap_mac     = "00:11:22:33:44:66"  # Deixe vazio se não houver AP dedicado
2. Configurar Credenciais da API (Método Seguro)
Para evitar salvar senhas em arquivos de texto no Git, defina as credenciais do UniFi OS como variáveis de ambiente na sessão atual do seu terminal:

powershell


$env:UNIFI_USERNAME = "seu_usuario_admin"
$env:UNIFI_PASSWORD = "sua_senha_segura"
$env:UNIFI_API_URL  = "https://192.168.1.1:443" # IP local ou público do UDM Pro
3. Aplicar com o Terraform
Execute o fluxo de trabalho padrão do Terraform:

powershell


# 1. Inicializar os provedores e baixar plugins
terraform init
# 2. Verificar as alterações planejadas antes de aplicar
terraform plan
# 3. Aplicar as configurações (digite 'yes' quando solicitado)
terraform apply
