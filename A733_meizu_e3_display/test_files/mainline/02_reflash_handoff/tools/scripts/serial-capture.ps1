param(
    [string]$PortName = "COM4",
    [int]$BaudRate = 115200,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [ValidateRange(1, 3600)]
    [int]$DurationSeconds = 30,
    [string]$Command
)

$ErrorActionPreference = "Stop"
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$parent = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
}

$port = [System.IO.Ports.SerialPort]::new(
    $PortName,
    $BaudRate,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.ReadTimeout = 250
$port.DtrEnable = $false
$port.RtsEnable = $false

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$writer = [System.IO.StreamWriter]::new($resolvedOutput, $true, $utf8NoBom)
$writer.AutoFlush = $true

try {
    $port.Open()
    $writer.WriteLine("")
    $writer.WriteLine(
        "===== serial capture {0:o} {1} {2}-8-N-1 =====",
        [DateTimeOffset]::Now,
        $PortName,
        $BaudRate
    )

    if ($Command) {
        $port.Write($Command + "`r")
        $writer.WriteLine("===== command sent (recorded locally only) =====")
        $writer.WriteLine($Command)
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
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
    $port.Dispose()
}

Write-Output $resolvedOutput
