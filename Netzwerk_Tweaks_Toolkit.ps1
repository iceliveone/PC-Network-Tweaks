# Netzwerk-Tweaks Toolkit mit GUI und MTU-Optimierung
Add-Type -AssemblyName PresentationFramework

# Admin-Rechte prüfen
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Logfile
$LogFile = "$PSScriptRoot\\Netzwerk_Tweaks_Log.txt"

function Log($msg) {
    Add-Content -Path $LogFile -Value "[$(Get-Date)] $msg"
}

# Adapterliste
$adapters = (Get-NetAdapter | Where-Object {$_.Status -eq "Up"}).Name

# GUI erstellen
$Window = New-Object Windows.Window
$Window.Title = "Netzwerk-Tweaks Toolkit"
$Window.SizeToContent = "WidthAndHeight"
$Window.WindowStartupLocation = "CenterScreen"

$StackPanel = New-Object Windows.Controls.StackPanel
$Window.Content = $StackPanel

# Dropdown für Adapter
$ComboBox = New-Object Windows.Controls.ComboBox
$ComboBox.ItemsSource = $adapters
$ComboBox.SelectedIndex = 0
$StackPanel.Children.Add($ComboBox)

# Buttons
$buttons = @("DNS-Flush","IP-Renew","Adapter-Neustart","TCP/IP Reset","Winsock Reset","Alle Tweaks","MTU anpassen","Optimale MTU finden","Beenden")
foreach ($b in $buttons) {
    $btn = New-Object Windows.Controls.Button
    $btn.Content = $b
    $btn.Margin = "5"
    $btn.Add_Click({
        switch ($b) {
            "DNS-Flush" { ipconfig /flushdns; Log "DNS-Cache geleert" }
            "IP-Renew" { ipconfig /release; ipconfig /renew; Log "IP-Adresse erneuert" }
            "Adapter-Neustart" {
                $adapter = $ComboBox.SelectedItem
                Disable-NetAdapter -Name $adapter -Confirm:$false
                Start-Sleep -Seconds 5
                Enable-NetAdapter -Name $adapter -Confirm:$false
                Log "Adapter $adapter neu gestartet"
            }
            "TCP/IP Reset" { netsh int ip reset; Log "TCP/IP-Stack zurückgesetzt" }
            "Winsock Reset" { netsh winsock reset; Log "Winsock zurückgesetzt" }
            "Alle Tweaks" {
                ipconfig /flushdns
                ipconfig /release
                ipconfig /renew
                $adapter = $ComboBox.SelectedItem
                Disable-NetAdapter -Name $adapter -Confirm:$false
                Start-Sleep -Seconds 5
                Enable-NetAdapter -Name $adapter -Confirm:$false
                netsh int ip reset
                netsh winsock reset
                Log "Alle Tweaks ausgeführt"
            }
            "MTU anpassen" {
                $adapter = $ComboBox.SelectedItem
                $mtu = [Microsoft.VisualBasic.Interaction]::InputBox("Neuen MTU-Wert eingeben (z.B. 1500):","MTU anpassen","1500")
                netsh interface ipv4 set subinterface "$adapter" mtu=$mtu store=persistent
                Log "MTU für $adapter auf $mtu gesetzt"
            }
            "Optimale MTU finden" {
                $adapter = $ComboBox.SelectedItem
                $host = "8.8.8.8"
                $size = 1472
                while ($size -gt 1200) {
                    $ping = Test-Connection -ComputerName $host -Count 1 -BufferSize $size -DontFragment -ErrorAction SilentlyContinue
                    if ($ping) { break } else { $size -= 10 }
                }
                $optimal = $size + 28
                [System.Windows.MessageBox]::Show("Optimale MTU: $optimal","MTU-Test")
                Log "Optimale MTU für $adapter: $optimal"
            }
            "Beenden" { $Window.Close() }
        }
    })
    $StackPanel.Children.Add($btn)
}

$Window.ShowDialog() | Out-Null
