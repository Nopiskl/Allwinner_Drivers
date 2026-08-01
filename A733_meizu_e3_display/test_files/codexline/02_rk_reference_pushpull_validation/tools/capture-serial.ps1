param(
    [string]$PortName = "COM4",
    [string]$OutputPath
)

$port = [System.IO.Ports.SerialPort]::new(
    $PortName,
    115200,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.ReadTimeout = 250
$port.DtrEnable = $false
$port.RtsEnable = $false

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$writer = [System.IO.StreamWriter]::new($OutputPath, $true, $utf8NoBom)
$writer.AutoFlush = $true

try {
    $port.Open()
    $writer.WriteLine("")
    $header = "===== capture start {0:o} {1} 115200-8-N-1 read-only =====" -f (
        [DateTimeOffset]::Now
    ), $PortName
    $writer.WriteLine($header)

    while ($true) {
        $text = $port.ReadExisting()
        if ($text.Length -gt 0) {
            $writer.Write($text)
        } else {
            Start-Sleep -Milliseconds 25
        }
    }
} finally {
    if ($port.IsOpen) {
        $port.Close()
    }
    $writer.Dispose()
}
