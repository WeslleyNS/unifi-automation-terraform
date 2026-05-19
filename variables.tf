###############################################################################
# variables.tf - Variáveis parametrizadas por loja (Lojas Granado)
###############################################################################

variable "loja_id" {
  description = "Número da filial com 3 dígitos (ex: 059)"
  type        = string
}

variable "loja_nome" {
  description = "Nome da unidade/filial (ex: Belramar SH)"
  type        = string
}

variable "estado_uf" {
  description = "Sigla do estado (ex: SC, RJ, SP)"
  type        = string
}

variable "device_mac" {
  description = "MAC address do UDM Pro (formato aa:bb:cc:dd:ee:ff)"
  type        = string
}

variable "switch_mac" {
  description = "MAC address do Switch da filial (formato aa:bb:cc:dd:ee:ff) - opcional"
  type        = string
  default     = ""
}

variable "ap_mac" {
  description = "MAC address do AP da filial (formato aa:bb:cc:dd:ee:ff) - opcional"
  type        = string
  default     = ""
}
