###############################################################################
# rename_udm.ps1 - Renomear o UDM Pro via super_identity (vários endpoints)
# Uso: powershell -ExecutionPolicy Bypass -File rename_udm.ps1 -NewName "F151 - Colombia - PR"
###############################################################################
param(
    [string]$NewName = "F151 - Colombia - PR",
    [string]$BaseUrl = "https://192.168.1.1:443"
)

$ErrorActionPreference = "Continue"

if (-not ([System.Management.Automation.PSTypeName]'TrustCertsRN2').Type) {
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustCertsRN2 : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustCertsRN2
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$pass = $env:UNIFI_PASSWORD
if (-not $pass) {
    $pass = "@Suporte" + [char]36 + "yst3m"
}
$user = $env:UNIFI_USERNAME
if (-not $user) {
    $user = "Suporte"
}
$loginBody = (@{ username = $user; password = $pass } | ConvertTo-Json)
Write-Host "Login em $BaseUrl..."
$login = Invoke-WebRequest -Uri "$BaseUrl/api/auth/login" -Method Post -Body $loginBody -ContentType "application/json" -SessionVariable webSession -UseBasicParsing
$csrfToken = $login.Headers["X-CSRF-Token"]
$headers = @{}
if ($csrfToken) { $headers["X-CSRF-Token"] = $csrfToken }
Write-Host "Login OK!"

# GET super_identity atual
Write-Host "Buscando super_identity..."
$getResp = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/api/s/default/get/setting/super_identity" -Method Get -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
$identity = ($getResp.Content | ConvertFrom-Json).data[0]
Write-Host "Nome atual: $($identity.name) | Hostname: $($identity.hostname) | ID: $($identity._id)"

# Gerar hostname valido
$hostname = $NewName -replace '[^a-zA-Z0-9]', '-'
$hostname = $hostname -replace '-+', '-'
$hostname = $hostname.Trim('-')

# Modificar o objeto existente
$identity.name = $NewName
$identity.hostname = $hostname
$body = $identity | ConvertTo-Json -Depth 5 -Compress

# --- Tentativa 1: PUT rest/setting/super_identity/{id} (Padrão REST do UniFi) ---
Write-Host ""
Write-Host "=== Tentativa 1: PUT rest/setting/super_identity/$($identity._id) ==="
try {
    $r1 = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/api/s/default/rest/setting/super_identity/$($identity._id)" -Method Put -Body $body -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
    Write-Host "HTTP $($r1.StatusCode) | $($r1.Content)"
} catch {
    try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "Falhou: $($rd.ReadToEnd())" } catch { Write-Host "Falhou: $($_.Exception.Message)" }
}

# --- Tentativa 2: POST set/setting/super_identity (Muitos endpoints 'set' usam POST) ---
Write-Host ""
Write-Host "=== Tentativa 2: POST set/setting/super_identity ==="
try {
    $r2 = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/api/s/default/set/setting/super_identity" -Method Post -Body $body -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
    Write-Host "HTTP $($r2.StatusCode) | $($r2.Content)"
} catch {
    try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "Falhou: $($rd.ReadToEnd())" } catch { Write-Host "Falhou: $($_.Exception.Message)" }
}

# --- Tentativa 3: PUT set/setting/super_identity ---
Write-Host ""
Write-Host "=== Tentativa 3: PUT set/setting/super_identity ==="
try {
    $r3 = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/api/s/default/set/setting/super_identity" -Method Put -Body $body -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
    Write-Host "HTTP $($r3.StatusCode) | $($r3.Content)"
} catch {
    try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "Falhou: $($rd.ReadToEnd())" } catch { Write-Host "Falhou: $($_.Exception.Message)" }
}

# --- Tentativa 4: Enviar payload mínimo via PUT rest/setting/super_identity/{id} ---
Write-Host ""
Write-Host "=== Tentativa 4: PUT rest/setting/super_identity/$($identity._id) (payload minimo) ==="
$minBody = @{
    _id      = $identity._id
    key      = "super_identity"
    name     = $NewName
    hostname = $hostname
} | ConvertTo-Json -Depth 5 -Compress
try {
    $r4 = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/api/s/default/rest/setting/super_identity/$($identity._id)" -Method Put -Body $minBody -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
    Write-Host "HTTP $($r4.StatusCode) | $($r4.Content)"
} catch {
    try { $s = $_.Exception.Response.GetResponseStream(); $rd = New-Object System.IO.StreamReader($s); Write-Host "Falhou: $($rd.ReadToEnd())" } catch { Write-Host "Falhou: $($_.Exception.Message)" }
}

# Verificar resultado final
Write-Host ""
Write-Host "=== Verificando Nome Atual ==="
$verifyResp = Invoke-WebRequest -Uri "$BaseUrl/proxy/network/api/s/default/get/setting/super_identity" -Method Get -ContentType "application/json" -WebSession $webSession -Headers $headers -UseBasicParsing
$final = ($verifyResp.Content | ConvertFrom-Json).data[0]
Write-Host "Nome final no UDM: $($final.name) | Hostname: $($final.hostname)"
