<#
.Netzwerk_Tweaks_Toolkit.ps1
Erweiterte Version mit:
 - Auto-Update (wie zuvor)
 - Menü + Grundfunktionen (DNS flush, renew, winsock, mtu, etc.)
 - Erweiterte Diagnose + folgende neue Features:
    * Internet Speedtest (versucht Ookla speedtest CLI, sonst Fallback-Download/Upload)
    * Traceroute (Test-NetConnection -TraceRoute)
    * WLAN-Diagnose (Signalstärke, Kanal, Nachbarnetzwerke)
    * Öffentliche IP-Ermittlung (api.ipify.org Fallback)
    * Paketverlust-Heatmap (mehrere Hosts über mehrere Runden, ASCII + HTML-Report)
#>

# ---------------------------
# Admin-Prüfung
# ---------------------------
If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Administratorrechte erforderlich. Starte neu als Administrator..."
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ---------------------------
# Auto-Update (von GitHub)
# ---------------------------
$GitHubURL  = "https://raw.githubusercontent.com/iceliveone/PC-Network-Tweaks/main/Netzwerk_Tweaks_Toolkit.ps1"
$LocalFile  = $PSCommandPath
$TempFile   = "$env:TEMP\update.ps1"

Write-Host "Prüfe auf Updates..."
try {
    Invoke-WebRequest -Uri $GitHubURL -OutFile $TempFile -ErrorAction Stop -UseBasicParsing
    if (-not (Compare-Object (Get-Content $TempFile -ErrorAction SilentlyContinue) (Get-Content $LocalFile -ErrorAction SilentlyContinue))) {
        # identisch -> nichts
    } else {
        Write-Host "Neue Version gefunden! Aktualisiere..."
        Copy-Item $TempFile $LocalFile -Force
        Write-Host "Update abgeschlossen. Starte neu..."
        Start-Process powershell "-ExecutionPolicy Bypass -File `"$LocalFile`""
        exit
    }
}
catch {
    Write-Host "Update-Check fehlgeschlagen (kein Internet oder GitHub nicht erreichbar). Fortfahren..."
}

# ---------------------------
# Basis-Aktionen (aus vorherigem Skript)
# ---------------------------
function Flush-DNS { ipconfig /flushdns }
function Renew-IP { ipconfig /release; Start-Sleep -Seconds 1; ipconfig /renew }
function Restart-NetworkAdapter {
    param($AdapterName = "Ethernet")
    try {
        Disable-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 5
        Enable-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Warning "Fehler beim Neustart des Adapters '$AdapterName'. Versuche Netsh-Fallback..."
        netsh interface set interface "$AdapterName" admin=disable
        Start-Sleep -Seconds 5
        netsh interface set interface "$AdapterName" admin=enable
    }
}
function Reset-TCPIP { netsh int ip reset }
function Reset-Winsock { netsh winsock reset }

function Set-MTU {
    Clear-Host
    Write-Host "Aktuelle MTU-Werte:"
    netsh interface ipv4 show subinterfaces
    $mtu = Read-Host "Neuen MTU-Wert eingeben (z.B. 1500)"
    $adapter = Read-Host "Adaptername eingeben (z.B. Ethernet)"
    netsh interface ipv4 set subinterface "$adapter" mtu=$mtu store=persistent
    Write-Host "MTU angepasst!"
    Read-Host "Enter drücken..."
}

# ---------------------------
# Erweiterte Netzwerk-Diagnose (vorher)
# ---------------------------
function Run-NetworkDiagnostics {
    Clear-Host
    Write-Host "===== Erweiterte Netzwerk-Diagnose =====`n"

    $adapter = Get-NetAdapter | Where-Object {$_.Status -ne "Disabled"} | Select-Object -First 1
    if (-not $adapter) { Write-Warning "Kein aktiver Netzwerkadapter gefunden."; return }

    Write-Host "Verwendeter Netzwerkadapter: $($adapter.Name) ($($adapter.InterfaceDescription))"
    Write-Host "--------------------------------------------------"

    # IP-Konfiguration
    Write-Host "`n[1] IP-Konfiguration"
    $ipcfg = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
    if ($ipcfg) {
        $ipv4 = $ipcfg.IPv4Address | Select-Object -First 1
        Write-Host "IPv4: $($ipv4.IPAddress)"
        Write-Host "Gateway: $($ipcfg.IPv4DefaultGateway.NextHop)"
        Write-Host "DNS: $($ipcfg.DNSServer.ServerAddresses -join ', ')"
    } else {
        Write-Warning "Keine IP-Konfigurationsdaten verfügbar."
    }

    # Gateway Ping
    Write-Host "`n[2] Gateway erreichbar?"
    if ($ipcfg.IPv4DefaultGateway.NextHop) {
        Test-Connection -Count 3 -Quiet $ipcfg.IPv4DefaultGateway.NextHop | ForEach-Object { if ($_){ Write-Host "Gateway antwortet." } else { Write-Warning "Gateway nicht erreichbar." } }
    } else { Write-Warning "Kein Gateway eingetragen." }

    # Ping Internet
    Write-Host "`n[3] Internet-Ping (8.8.8.8)"
    Test-Connection -Count 3 8.8.8.8 | Format-Table Address, ResponseTime, StatusCode -AutoSize

    # DNS-Auflösung
    Write-Host "`n[4] DNS-Auflösung (google.com)"
    try {
        Resolve-DnsName google.com -ErrorAction Stop | Select-Object Name,IPAddress,Type | Format-Table -AutoSize
    } catch { Write-Warning "DNS-Auflösung fehlgeschlagen." }

    # HTTP-Test
    Write-Host "`n[5] HTTP-Test (https://www.microsoft.com)"
    try {
        $r = Invoke-WebRequest -Uri "https://www.microsoft.com" -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
        Write-Host "HTTP erreichbar (StatusCode: $($r.StatusCode))"
    } catch { Write-Warning "HTTP-Abfrage fehlgeschlagen." }

    # Adapterstatus
    Write-Host "`n[6] Adapterstatus"
    $adapter | Format-List Name, Status, LinkSpeed, MacAddress, InterfaceDescription

    # Paketverlust über kurze Serie
    Write-Host "`n[7] Paketverlust (8.8.8.8 - 20 Pings)"
    $pings = Test-Connection -Count 20 -ComputerName 8.8.8.8 -ErrorAction SilentlyContinue
    if ($pings) {
        $sent = 20
        $received = ($pings | Where-Object { $_.StatusCode -eq 0 }).Count
        $loss = ($sent - $received) / $sent * 100
        Write-Host "Gesendet: $sent; Empfangen: $received; Verlust: $([math]::Round($loss,2))%"
    } else {
        Write-Warning "Ping fehlgeschlagen."
    }

    # MTU-Test (DF)
    Write-Host "`n[8] MTU-Test (DF gesetzt, Ziel 8.8.8.8). Werte > 1472 deuten auf MTU >=1500"
    try {
        $pingout = & ping -f -l 1472 8.8.8.8 2>&1
        $pingout
    } catch {}

    # ARP
    Write-Host "`n[9] ARP-Tabelle"
    arp -a | Out-Host

    Write-Host "`n===== Diagnose abgeschlossen ====="
    Read-Host "Enter drücken..."
}

# ---------------------------
# NEU: Speedtest (Download/Upload über Measurement-API / Fallback)
# ---------------------------
function Run-SpeedTest {
    Clear-Host
    Write-Host "===== Internet-Speedtest =====`n"

    # 1) Wenn Ookla Speedtest CLI installiert ist, benutze es (genauer)
    $speedCli = Get-Command speedtest -ErrorAction SilentlyContinue
    if ($speedCli) {
        Write-Host "Ookla Speedtest-CLI gefunden. Starte ausführlichen Test..."
        try {
            # JSON-Ausgabe parsen (wenn verfügbar)
            $out = & speedtest --accept-license --accept-gdpr --format=json 2>&1
            if ($LASTEXITCODE -eq 0) {
                try {
                    $json = $out | Out-String | ConvertFrom-Json
                    Write-Host "Server: $($json.server.name) ($($json.server.country))"
                    Write-Host "Ping: $($json.ping.latency) ms"
                    Write-Host "Download: $([math]::Round($json.download.bandwidth/125000,2)) Mbps"
                    Write-Host "Upload: $([math]::Round($json.upload.bandwidth/125000,2)) Mbps"
                    Read-Host "Enter drücken..."
                    return
                } catch {
                    Write-Host $out
                    Read-Host "Enter drücken..."
                    return
                }
            } else {
                Write-Warning "Speedtest CLI scheiterte, fallback..."
            }
        } catch {
            Write-Warning "Fehler beim Ausführen der Speedtest-CLI: $_"
        }
    }

    # 2) Fallback-Download-Test (HTTP)
    Write-Host "Fallback: HTTP-Download/Upload-Test (ungenauer als Dedicated-Measurement)."

    $downloadUrl = "http://speedtest.tele2.net/10MB.zip"  # gebräuchliche testdatei (kann blockiert sein)
    $tmpFile = Join-Path $env:TEMP "st_dl_test.tmp"

    try {
        Write-Host "`nDownload-Test: $downloadUrl"
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
        $dwTime = Measure-Command { Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpFile -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop }
        $sizeBytes = (Get-Item $tmpFile).Length
        $bps = $sizeBytes / $dwTime.TotalSeconds
        $mbps = $bps / 1MB * 8  # Bytes->bits, Bytes per sec -> Mbps
        Write-Host "Heruntergeladen: $([math]::Round($sizeBytes/1KB,2)) KB in $([math]::Round($dwTime.TotalSeconds,2))s -> $([math]::Round($mbps,2)) Mbps"
    } catch {
        Write-Warning "Download-Test fehlgeschlagen: $_"
    } finally {
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }

    # 3) Einfacher Upload-Test (POST an httpbin) - erzeugt Messdaten; abhängig von Server und Limits
    $uploadUrl = "https://httpbin.org/post"
    try {
        Write-Host "`nUpload-Test (POST an httpbin.org)"
        $payload = New-Object byte[] (1MB * 5) # 5 MB
        (New-Object System.Random).NextBytes($payload)
        $mem = [System.IO.MemoryStream]::new($payload)
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("Content-Type","application/octet-stream")
        $upTime = Measure-Command { $wc.UploadData($uploadUrl,"POST",$payload) }
        $bpsUp = $payload.Length / $upTime.TotalSeconds
        $mbpsUp = $bpsUp / 1MB * 8
        Write-Host "Hochgeladen: $([math]::Round($payload.Length/1KB,2)) KB in $([math]::Round($upTime.TotalSeconds,2))s -> $([math]::Round($mbpsUp,2)) Mbps"
    } catch {
        Write-Warning "Upload-Test fehlgeschlagen: $_"
    }

    Read-Host "Enter drücken..."
}

# ---------------------------
# NEU: Traceroute
# ---------------------------
function Run-Traceroute {
    Clear-Host
    $target = Read-Host "Ziel für Traceroute eingeben (z.B. 8.8.8.8 oder google.com)"
    if (-not $target) { Write-Warning "Kein Ziel angegeben."; return }
    Write-Host "Traceroute zu $target..."
    try {
        Test-NetConnection -TraceRoute -ComputerName $target | Out-Host
    } catch {
        Write-Warning "Traceroute fehlgeschlagen: $_"
    }
    Read-Host "Enter drücken..."
}

# ---------------------------
# NEU: WLAN-Diagnose (Signalstärke, Kanal, Nachbarn)
# ---------------------------
function Run-WiFiDiagnostics {
    Clear-Host
    Write-Host "===== WLAN-Diagnose =====`n"

    # Lokale Schnittstelleninfo
    try {
        Write-Host "[Aktuelle Schnittstelleninfo]"
        netsh wlan show interfaces | Out-Host
    } catch {
        Write-Warning "Fehler beim Abfragen der WLAN-Interfaces."
    }

    # Nachbarnetzwerke (SSID, BSSID, Signal, Kanal)
    try {
        Write-Host "`n[Erkannte Netzwerke (SSID / BSSID / Signal / Kanal)]"
        netsh wlan show networks mode=bssid | Out-Host
    } catch {
        Write-Warning "Fehler beim Scannen nach Netzwerken."
    }

    # Option: Signalstärke Trends (einfach)
    $doTrend = Read-Host "Kurzzeit-Signalstärke-Messung durchführen? (y/n)"
    if ($doTrend -match '^[Yy]') {
        $adapter = (Get-NetAdapter -Physical | Where-Object {$_.Name -like "*Wi-Fi*" -or $_.InterfaceDescription -match "Wireless"} | Select-Object -First 1)
        if (-not $adapter) {
            Write-Warning "Kein WLAN-Adapter erkannt."
            Read-Host "Enter drücken..."
            return
        }
        $samples = @()
        Write-Host "Erfasse 15 Messwerte (1s Abstand)..."
        for ($i=0; $i -lt 15; $i++) {
            $raw = netsh wlan show interfaces
            $line = ($raw | Where-Object { $_ -match "^\s*Signal" }) -join ""
            $signal = ($line -replace ".*:\s*","") -replace "%",""
            $samples += [int]$signal
            Start-Sleep -Seconds 1
        }
        Write-Host "Signalstärken: $($samples -join ', ')"
    }

    Read-Host "Enter drücken..."
}

# ---------------------------
# NEU: Öffentliche IP ermitteln
# ---------------------------
function Get-PublicIP {
    Clear-Host
    Write-Host "Ermittle öffentliche IP..."
    $services = @(
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://checkip.amazonaws.com"
    )
    $public = $null
    foreach ($s in $services) {
        try {
            $r = Invoke-RestMethod -Uri $s -TimeoutSec 5 -ErrorAction Stop
            if ($r -and ($r -match '\d+\.\d+\.\d+\.\d+')) {
                $public = $r.Trim()
                break
            }
        } catch { }
    }
    if ($public) {
        Write-Host "Öffentliche IP: $public"
    } else {
        Write-Warning "Öffentliche IP konnte nicht ermittelt werden."
    }
    Read-Host "Enter drücken..."
}

# ---------------------------
# NEU: Paketverlust-Heatmap (ASCII + HTML Report)
# ---------------------------
function Run-PacketLossHeatmap {
    Clear-Host
    Write-Host "===== Paketverlust-Heatmap =====`n"
    $targets = @()
    $defaultTargets = @("Gateway","8.8.8.8","1.1.1.1","google.com")
    $useDefaults = Read-Host "Voreingestellte Ziele verwenden? (Gateway, 8.8.8.8, 1.1.1.1, google.com) (y/n)"
    if ($useDefaults -match '^[Yy]') {
        # Gateway auflösen
        $gw = (Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway} | Select-Object -First 1).IPv4DefaultGateway.NextHop
        if ($gw) { $targets += $gw } else { $targets += "8.8.8.8" }
        $targets += "8.8.8.8","1.1.1.1","google.com"
        $targets = $targets | Select-Object -Unique
    } else {
        $input = Read-Host "Gib Ziele kommasepariert ein (z.B. 8.8.8.8,google.com)"
        $targets = $input -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        if (-not $targets) { Write-Warning "Keine Ziele angegeben."; return }
    }

    $rounds = Read-Host "Wie viele Messrunden? (z.B. 10)"
    if (-not [int]::TryParse($rounds,[ref]$null)) { $rounds = 10 } else { $rounds = [int]$rounds }
    Write-Host "Starte $rounds Runden Pings zu $($targets -join ', ')..."

    # Matrix: rows = rounds, cols = targets (we'll also produce heat % per target)
    $results = @()
    for ($r=1; $r -le $rounds; $r++) {
        $row = [ordered]@{}
        foreach ($t in $targets) {
            $ok = $false
            try {
                $p = Test-Connection -Count 3 -Quiet -ComputerName $t -ErrorAction SilentlyContinue
                # Test-Connection -Quiet mit Count 3 returns boolean if ANY reply? We'll do fallback with Test-Connection normal:
                if ($p -is [bool]) {
                    $status = if ($p) { 0 } else { 100 } # 0% loss or 100% loss (approx)
                } else {
                    # robust approach: do 3 pings, count replies
                    $pfull = Test-Connection -Count 3 -ComputerName $t -ErrorAction SilentlyContinue
                    if ($pfull) {
                        $recv = ($pfull | Where-Object { $_.StatusCode -eq 0 }).Count
                        $loss = (3 - $recv) / 3 * 100
                        $status = [math]::Round($loss,0)
                    } else {
                        $status = 100
                    }
                }
            } catch {
                $status = 100
            }
            $row[$t] = $status
        }
        $results += ,$row
        Start-Sleep -Seconds 1
    }

    # Erzeuge ASCII Heatmap (runde -> spalte)
    Write-Host "`nASCII Heatmap (Zeile = Runde, Spalte = Ziel; Werte = Paketverlust%)"
    # Header
    $header = "Rnd".PadRight(5)
    foreach ($t in $targets) { $header += ($t.PadRight(15)) }
    Write-Host $header
    $i = 1
    foreach ($row in $results) {
        $line = $i.ToString().PadRight(5)
        foreach ($t in $targets) {
            $v = $row[$t]
            $line += ($v.ToString().PadRight(15))
        }
        Write-Host $line
        $i++
    }

    # HTML Report erzeugen
    $htmlRows = ""
    $i = 1
    foreach ($row in $results) {
        $htmlRows += "<tr><td>$i</td>"
        foreach ($t in $targets) {
            $v = $row[$t]
            # Farbe: grün 0%, gelb 1-30, orange 31-70, rot >70
            if ($v -eq 0) { $col = "#8fd19e" } elseif ($v -le 30) { $col = "#ffe082" } elseif ($v -le 70) { $col = "#ffb74d" } else { $col = "#ef9a9a" }
            $htmlRows += "<td style='background:$col;text-align:center;'>$v%</td>"
        }
        $htmlRows += "</tr>`n"
        $i++
    }

    $htmlHeaderCols = ""
    foreach ($t in $targets) { $htmlHeaderCols += "<th style='padding:6px;'>$t</th>" }

    $html = @"
<html>
<head>
<meta charset='utf-8' />
<title>Paketverlust Heatmap</title>
</head>
<body>
<h2>Paketverlust Heatmap - Generated: $(Get-Date -Format u)</h2>
<table border='1' cellpadding='4' cellspacing='0' style='border-collapse:collapse;'>
<thead><tr><th>Runde</th>$htmlHeaderCols</tr></thead>
<tbody>$htmlRows</tbody>
</table>
<p>Legende: Grün 0% | Gelb 1-30% | Orange 31-70% | Rot &gt;70%</p>
</body>
</html>
"@

    $outHtml = Join-Path $env:TEMP "packet_loss_heatmap.html"
    $html | Out-File -FilePath $outHtml -Encoding UTF8
    Write-Host "`nHTML-Report erstellt: $outHtml"
    Start-Process $outHtml

    Read-Host "Enter drücken..."
}

# ---------------------------
# Menü & Loop (erweitert)
# ---------------------------
function Show-Menu {
    Clear-Host
    Write-Host "============================================"
    Write-Host " Netzwerk-Tweaks Toolkit (PowerShell)"
    Write-Host "============================================"
    Write-Host "[1] DNS-Cache leeren"
    Write-Host "[2] IP-Adresse erneuern"
    Write-Host "[3] Netzwerkadapter neu starten"
    Write-Host "[4] TCP/IP-Stack zurücksetzen"
    Write-Host "[5] Winsock zurücksetzen"
    Write-Host "[6] MTU-Wert anpassen"
    Write-Host "[7] Erweiterte Netzwerk-Diagnose"
    Write-Host "[8] Internet-Speedtest (Download/Upload)"
    Write-Host "[9] Traceroute"
    Write-Host "[10] WLAN-Diagnose"
    Write-Host "[11] Öffentliche IP ermitteln"
    Write-Host "[12] Paketverlust-Heatmap"
    Write-Host "[0] Beenden"
    Write-Host "============================================"
    return (Read-Host "Bitte wähle eine Option")
}

while ($true) {
    switch (Show-Menu) {
        "1"  { Flush-DNS }
        "2"  { Renew-IP }
        "3"  { $an = Read-Host "Adaptername (Standard: Ethernet)"; if (-not $an) { $an = "Ethernet" }; Restart-NetworkAdapter -AdapterName $an }
        "4"  { Reset-TCPIP }
        "5"  { Reset-Winsock }
        "6"  { Set-MTU }
        "7"  { Run-NetworkDiagnostics }
        "8"  { Run-SpeedTest }
        "9"  { Run-Traceroute }
        "10" { Run-WiFiDiagnostics }
        "11" { Get-PublicIP }
        "12" { Run-PacketLossHeatmap }
        "0"  { exit }
        default { Write-Host "Ungültige Eingabe!"; Start-Sleep -Seconds 1 }
    }
}
