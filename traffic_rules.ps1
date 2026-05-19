###############################################################################
# traffic_rules.ps1 - Criar Traffic Rules (zona-based) no UDM Pro
# Uso: powershell -ExecutionPolicy Bypass -File traffic_rules.ps1
###############################################################################
param(
    [string]$BaseUrl = "https://192.168.1.1:443"
)

$ErrorActionPreference = "Stop"

# --- SSL ---
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsTraffic').Type) {
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsTraffic : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsTraffic
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Login ---
$pass = $env:UNIFI_PASSWORD
if (-not $pass) {
    $pass = "@Suporte" + [char]36 + "yst3m"
}
$user = $env:UNIFI_USERNAME
if (-not $user) {
    $user = "Suporte"
}
$loginBody = (@{ username = $user; password = $pass } | ConvertTo-Json)
Write-Host "Login..."
$login = Invoke-WebRequest -Uri "$BaseUrl/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json" -SessionVariable webSession -UseBasicParsing
$csrfToken = $login.Headers["X-CSRF-Token"]
$headers = @{}
if ($csrfToken) { $headers["X-CSRF-Token"] = $csrfToken }
Write-Host "Login OK!"

# --- Funcao helper para criar traffic rule ---
function New-TrafficRule {
    param(
        [string]$Name,
        [string]$Action = "BLOCK",
        [hashtable]$Matching,
        [string]$Description = ""
    )

    $rule = @{
        action             = $Action
        description        = $Description
        enabled            = $true
        matching_target    = "INTERNET"
        target_devices     = @(@{ type = "ALL" })
        schedule           = @{ mode = "ALWAYS" }
    }

    # Merge matching params
    foreach ($key in $Matching.Keys) {
        $rule[$key] = $Matching[$key]
    }

    # Adicionar nome
    $rule["app_category_ids"] = @()
    $rule["app_ids"]          = @()
    $rule["regions"]          = @()
    $rule["ip_addresses"]     = @()
    $rule["domains"]          = @()
    $rule["ip_ranges"]        = @()

    # Override with matching
    foreach ($key in $Matching.Keys) {
        $rule[$key] = $Matching[$key]
    }

    $body = $rule | ConvertTo-Json -Depth 10 -Compress

    try {
        # Verificar se regra ja existe
        $existingResp = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/v2/api/site/default/trafficrules" -Method Get -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        $existing = ($existingResp.Content | ConvertFrom-Json)
        $found = $existing | Where-Object { $_.description -eq $Name -or $_.action -eq $Action }

        # Criar regra
        Write-Host "Criando regra: $Name..."
        Write-Host "  Body: $body"
        $resp = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/v2/api/site/default/trafficrules" -Method Post -Body $body -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        Write-Host "  OK! HTTP $($resp.StatusCode)"
        return $true
    } catch {
        try {
            $s = $_.Exception.Response.GetResponseStream()
            $rd = New-Object System.IO.StreamReader($s)
            $errBody = $rd.ReadToEnd()
            Write-Host "  ERRO: $errBody"
        } catch {
            Write-Host "  ERRO: $($_.Exception.Message)"
        }
        return $false
    }
}

# ============================================================================
# Primeiro, verificar o endpoint correto listando regras existentes
# ============================================================================
Write-Host ""
Write-Host "=== Verificando endpoints de Traffic Rules ==="

$apiPaths = @(
    "/proxy/network/v2/api/site/default/trafficrules",
    "/proxy/network/api/s/default/rest/trafficrule",
    "/proxy/network/v2/api/site/default/trafficroutes"
)

$workingPath = $null
foreach ($path in $apiPaths) {
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl$path" -Method Get -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        Write-Host "  $path -> HTTP $($r.StatusCode) ($(($r.Content | ConvertFrom-Json).Count) regras)"
        $workingPath = $path
        break
    } catch {
        Write-Host "  $path -> ERRO"
    }
}

if (-not $workingPath) {
    Write-Host "Nenhum endpoint de Traffic Rules encontrado!"
    Write-Host "Tentando criar via legacy firewall rules..."
    
    # Fallback: usar legacy firewall rules com address groups
    # Regra 2 - Block IPs do planal.topazioi.help
    Write-Host ""
    Write-Host "=== Criando Address Group: BLOCK_TOPAZIO_IPS ==="
    $groupBody = (@{
        name = "BLOCK_TOPAZIO_IPS"
        group_type = "address-group"
        group_members = @("172.67.172.243", "104.21.30.134")
    } | ConvertTo-Json -Depth 5)
    
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/api/s/default/rest/firewallgroup" -Method Post -Body $groupBody -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        Write-Host "  Grupo criado! HTTP $($r.StatusCode)"
    } catch {
        try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "  ERRO: $($rd.ReadToEnd())" } catch { Write-Host "  ERRO: $($_.Exception.Message)" }
    }
    
    exit 0
}

Write-Host ""
Write-Host "Usando endpoint: $workingPath"
Write-Host ""

# ============================================================================
# Listar regras existentes para evitar duplicatas
# ============================================================================
$existingResp = Invoke-WebRequest -Uri "$BaseUrl$workingPath" -Method Get -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
$existingRules = ($existingResp.Content | ConvertFrom-Json)
Write-Host "Regras existentes: $($existingRules.Count)"
foreach ($er in $existingRules) {
    Write-Host "  - $($er.description) (action: $($er.action), enabled: $($er.enabled))"
}

# ============================================================================
# Regra 1: BLOCK planal.topazioi.help pa (domain block)
# ============================================================================
Write-Host ""
Write-Host "=== Regra 1: BLOCK planal.topazioi.help pa ==="
$rule1Exists = $existingRules | Where-Object { $_.description -like "*planal.topazioi.help pa*" -or $_.description -like "*BLOCK planal.topazioi.help pa*" }
if ($rule1Exists) {
    Write-Host "  Ja existe, pulando."
} else {
    $body1 = @{
        action          = "BLOCK"
        description     = "BLOCK planal.topazioi.help pa"
        enabled         = $true
        matching_target = "INTERNET"
        target_devices  = @(@{ type = "ALL" })
        schedule        = @{ mode = "ALWAYS" }
        domains         = @(@{ domain = "planal.topazioi.help"; ports = @() })
        ip_addresses    = @()
        ip_ranges       = @()
        regions         = @()
        app_category_ids = @()
        app_ids         = @()
        network_ids     = @()
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl$workingPath" -Method Post -Body $body1 -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        Write-Host "  Criada! HTTP $($r.StatusCode)"
    } catch {
        try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "  ERRO: $($rd.ReadToEnd())" } catch { Write-Host "  ERRO: $($_.Exception.Message)" }
    }
}

# ============================================================================
# Regra 2: BLOCK planal.topazioi.help > IP (IP block)
# ============================================================================
Write-Host ""
Write-Host "=== Regra 2: BLOCK planal.topazioi.help > IP ==="
$rule2Exists = $existingRules | Where-Object { $_.description -like "*planal.topazioi.help*IP*" }
if ($rule2Exists) {
    Write-Host "  Ja existe, pulando."
} else {
    $body2 = @{
        action          = "BLOCK"
        description     = "BLOCK planal.topazioi.help > IP"
        enabled         = $true
        matching_target = "INTERNET"
        target_devices  = @(@{ type = "ALL" })
        schedule        = @{ mode = "ALWAYS" }
        ip_addresses    = @(
            @{ ip_or_subnet = "172.67.172.243"; ports = @() },
            @{ ip_or_subnet = "104.21.30.134"; ports = @() }
        )
        domains         = @()
        ip_ranges       = @()
        regions         = @()
        app_category_ids = @()
        app_ids         = @()
        network_ids     = @()
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl$workingPath" -Method Post -Body $body2 -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        Write-Host "  Criada! HTTP $($r.StatusCode)"
    } catch {
        try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "  ERRO: $($rd.ReadToEnd())" } catch { Write-Host "  ERRO: $($_.Exception.Message)" }
    }
}

# ============================================================================
# Regra 3: BLOCK EXTERNAL REGION CHINA (geo-IP block China + Russia)
# ============================================================================
Write-Host ""
Write-Host "=== Regra 3: BLOCK EXTERNAL REGION CHINA ==="
$rule3Exists = $existingRules | Where-Object { $_.description -like "*REGION CHINA*" -or $_.description -like "*EXTERNAL REGION*" }
if ($rule3Exists) {
    Write-Host "  Ja existe, pulando."
} else {
    $body3 = @{
        action          = "BLOCK"
        description     = "BLOCK EXTERNAL REGION CHINA"
        enabled         = $true
        matching_target = "INTERNET"
        target_devices  = @(@{ type = "ALL" })
        schedule        = @{ mode = "ALWAYS" }
        regions         = @("CN", "RU")
        ip_addresses    = @()
        ip_ranges       = @()
        domains         = @()
        app_category_ids = @()
        app_ids         = @()
        network_ids     = @()
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl$workingPath" -Method Post -Body $body3 -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        Write-Host "  Criada! HTTP $($r.StatusCode)"
    } catch {
        try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "  ERRO: $($rd.ReadToEnd())" } catch { Write-Host "  ERRO: $($_.Exception.Message)" }
    }
}

# ============================================================================
# Regra 4: BLOCK 175.74 (domain block)
# ============================================================================
Write-Host ""
Write-Host "=== Regra 4: BLOCK 175.74 ==="
$rule4Exists = $existingRules | Where-Object { $_.description -like "*175.74*" -or $_.description -like "*BLOCK 175*" }
if ($rule4Exists) {
    Write-Host "  Ja existe, pulando."
} else {
    $body4 = @{
        action          = "BLOCK"
        description     = "BLOCK 175.74"
        enabled         = $true
        matching_target = "INTERNET"
        target_devices  = @(@{ type = "ALL" })
        schedule        = @{ mode = "ALWAYS" }
        domains         = @(@{ domain = "175.74.70.216.host.secureserver.net"; ports = @() })
        ip_addresses    = @()
        ip_ranges       = @()
        regions         = @()
        app_category_ids = @()
        app_ids         = @()
        network_ids     = @()
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl$workingPath" -Method Post -Body $body4 -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
        Write-Host "  Criada! HTTP $($r.StatusCode)"
    } catch {
        try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "  ERRO: $($rd.ReadToEnd())" } catch { Write-Host "  ERRO: $($_.Exception.Message)" }
    }
}

# ============================================================================
# Verificacao final
# ============================================================================
Write-Host ""
Write-Host "=== Verificacao Final ==="
$finalResp = Invoke-WebRequest -Uri "$BaseUrl$workingPath" -Method Get -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
$finalRules = ($finalResp.Content | ConvertFrom-Json)
Write-Host "Total de Traffic Rules: $($finalRules.Count)"
foreach ($fr in $finalRules) {
    Write-Host "  [$($fr.action)] $($fr.description) (enabled: $($fr.enabled))"
}
Write-Host ""
Write-Host "Concluido!"
