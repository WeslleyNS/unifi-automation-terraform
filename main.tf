###############################################################################
# main.tf - Infraestrutura UniFi para Lojas Granado
# Recursos: Rede LAN, Grupos de Firewall, Regras de Firewall
###############################################################################

# ---------------------------------------------------------------------------
# Locals - Cálculos derivados das variáveis da loja
# ---------------------------------------------------------------------------
locals {
  subnet_prefix = "192.168.${tonumber(var.loja_id)}"
  firewall_name = "F${var.loja_id} - ${var.loja_nome} - ${var.estado_uf}"
}

# ---------------------------------------------------------------------------
# Renomear o UDM Pro com o nome da loja (via API REST direta)
# O provider unifi_device não suporta renomear o próprio console/gateway.
# Usa o endpoint super_identity para alterar o nome do dispositivo.
# ---------------------------------------------------------------------------
resource "null_resource" "rename_udm" {
  triggers = {
    name = local.firewall_name
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-ExecutionPolicy", "Bypass", "-File"]
    command     = "${path.module}/rename_udm.ps1 -NewName \"${local.firewall_name}\""
  }
}

# ---------------------------------------------------------------------------
# Rede LAN Corporativa da Filial
# ---------------------------------------------------------------------------
resource "unifi_network" "lan_loja" {
  name    = "LAN-F${var.loja_id}"
  purpose = "corporate"

  vlan_id      = tonumber(var.loja_id)
  subnet       = "${local.subnet_prefix}.0/24"
  dhcp_start   = "${local.subnet_prefix}.40"
  dhcp_stop    = "${local.subnet_prefix}.189"
  dhcp_enabled = true

  # DNS Público (Google)
  dhcp_dns = ["8.8.8.8", "8.8.4.4"]
}

# ---------------------------------------------------------------------------
# Grupo de Firewall 1 - Endereços do Servidor Zabbix / AWS
# ---------------------------------------------------------------------------
resource "unifi_firewall_group" "server_zabbix_aws" {
  name = "SERVER ZABBIX AWS"
  type = "address-group"

  members = [
    "100.64.5.0/24",
    "3.209.185.128",
    "35.153.181.251",
    "201.48.191.109",
    "187.102.181.230",
  ]
}

# ---------------------------------------------------------------------------
# Grupo de Firewall 2 - Portas de Monitoramento AWS
# ---------------------------------------------------------------------------
resource "unifi_firewall_group" "portas_monitoramento_aws" {
  name = "PORTAS MONITORAMENTO AWS"
  type = "port-group"

  members = [
    "22",
    "80",
    "161",
    "199",
    "443",
    "7443",
    "7445",
    "8080",
    "8429",
    "8443",
    "8880",
    "9543",
  ]
}

# ---------------------------------------------------------------------------
# Regra de Firewall 1 - ICMP (Permitir ping do Zabbix/SYSTEM)
# ---------------------------------------------------------------------------
resource "unifi_firewall_rule" "icmp_allow" {
  name    = "ICMP"
  action  = "accept"
  ruleset = "WAN_LOCAL"

  protocol = "icmp"

  src_firewall_group_ids = [unifi_firewall_group.server_zabbix_aws.id]

  rule_index = 20000
}

# ---------------------------------------------------------------------------
# Regra de Firewall 2 - SSH/WG (Permitir acesso restrito via SSH)
# ---------------------------------------------------------------------------
resource "unifi_firewall_rule" "ssh_wg_allow" {
  name    = "SSH WG"
  action  = "accept"
  ruleset = "WAN_LOCAL"

  protocol = "tcp_udp"

  src_firewall_group_ids = [unifi_firewall_group.server_zabbix_aws.id]
  dst_firewall_group_ids = [unifi_firewall_group.portas_monitoramento_aws.id]

  rule_index = 20001
}

# ---------------------------------------------------------------------------
# Traffic Rules (zona-based) - Bloqueios de domínio, IP e geo-IP
# Estas regras usam a API v2 do UniFi (Traffic Rules), não suportada
# pelo provider Terraform. Executadas via script PowerShell.
# ---------------------------------------------------------------------------
resource "null_resource" "traffic_rules" {
  triggers = {
    rules_hash = "v1-block-topazio-china-175"
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-ExecutionPolicy", "Bypass", "-File"]
    command     = "${path.module}/traffic_rules.ps1"
  }

  depends_on = [
    unifi_firewall_rule.icmp_allow,
    unifi_firewall_rule.ssh_wg_allow,
  ]
}

# ---------------------------------------------------------------------------
# Equipamentos de Rede - Switch e Access Points (Adotados e Renomeados)
# Configura o nome e o IP estático correspondente ao ID da loja
# ---------------------------------------------------------------------------

# Renomear os equipamentos na lista de Dispositivos UniFi
resource "unifi_device" "switch_loja" {
  count = var.switch_mac != "" ? 1 : 0

  mac  = var.switch_mac
  name = "SW-F${var.loja_id} - ${var.loja_nome} - ${var.estado_uf}"
}

resource "unifi_device" "ap_loja" {
  count = var.ap_mac != "" ? 1 : 0

  mac  = var.ap_mac
  name = "AP-F${var.loja_id} - ${var.loja_nome} - ${var.estado_uf}"
}

# Configurar IP Fixo (DHCP Reservation) na rede corporativa da loja
resource "unifi_user" "switch_ip" {
  count = var.switch_mac != "" ? 1 : 0

  mac            = var.switch_mac
  name           = "SW-F${var.loja_id} - ${var.loja_nome} - ${var.estado_uf}"
  fixed_ip       = "${local.subnet_prefix}.2"
  network_id     = unifi_network.lan_loja.id
  allow_existing = true
}

resource "unifi_user" "ap_ip" {
  count = var.ap_mac != "" ? 1 : 0

  mac            = var.ap_mac
  name           = "AP-F${var.loja_id} - ${var.loja_nome} - ${var.estado_uf}"
  fixed_ip       = "${local.subnet_prefix}.5"
  network_id     = unifi_network.lan_loja.id
  allow_existing = true
}
