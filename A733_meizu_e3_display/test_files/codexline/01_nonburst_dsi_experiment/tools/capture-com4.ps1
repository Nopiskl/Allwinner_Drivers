param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath,
    [Parameter(Mandatory = $true)]
    [string]$StopPath,
    [Parameter(Mandatory = $true)]
    [string]$StatusPath
)

$ErrorActionPreference = 'Stop'
$encoding = [System.Text.UTF8Encoding]::new($false)
$port = [System.IO.Ports.SerialPort]::new(
    'COM4',
    115200,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$port.ReadTimeout = 250

try {
    $port.Open()
    [System.IO.File]::WriteAllText(
        $StatusPath,
        "OPEN $([DateTimeOffset]::Now.ToString('o')) PID=$PID`n",
        $encoding
    )
    $writer = [System.IO.StreamWriter]::new($LogPath, $true, $encoding)
    try {
        while (-not [System.IO.File]::Exists($StopPath)) {
            $text = $port.ReadExisting()
            if ($text.Length -gt 0) {
                $writer.Write($text)
                $writer.Flush()
            }
            Start-Sleep -Milliseconds 40
        }
    }
    finally {
        $writer.Dispose()
    }
}
catch {
    [System.IO.File]::WriteAllText(
        $StatusPath,
        "ERROR $([DateTimeOffset]::Now.ToString('o')) PID=$PID $($_.Exception.Message)`n",
        $encoding
    )
    throw
}
finally {
    if ($port.IsOpen) {
        $port.Close()
    }
    $port.Dispose()
}
