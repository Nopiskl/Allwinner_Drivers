param(
    [Parameter(Mandatory = $true)]
    [string]$RunDirectory,
    [int]$CaptureSeconds = 150
)

$ErrorActionPreference = 'Stop'
$serialLog = Join-Path $RunDirectory 'recovery-l0r-serial.log'
$statusLog = Join-Path $RunDirectory 'recovery-l0r-status.txt'
$encoding = [System.Text.UTF8Encoding]::new($false)
$port = [System.IO.Ports.SerialPort]::new(
    'COM4',
    115200,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$port.ReadTimeout = 250

$selectionCount = 0
$rolling = ''

try {
    $port.Open()
    [System.IO.File]::AppendAllText(
        $serialLog,
        "`r`n--- recovery capture opened $([DateTimeOffset]::Now.ToString('o')) ---`r`n",
        $encoding
    )
    [System.IO.File]::WriteAllText(
        $statusLog,
        "LISTENING $([DateTimeOffset]::Now.ToString('o')) PID=$PID`n",
        $encoding
    )
    Write-Output 'COM4_LISTENING'

    $writer = [System.IO.StreamWriter]::new($serialLog, $true, $encoding)
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($CaptureSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $text = $port.ReadExisting()
            if ($text.Length -gt 0) {
                $writer.Write($text)
                $writer.Flush()
                $rolling += $text
                if ($rolling.Length -gt 8192) {
                    $rolling = $rolling.Substring($rolling.Length - 8192)
                }

                if ($rolling -match '(?i)(U-Boot menu|Enter choice)') {
                    Start-Sleep -Milliseconds 250
                    $port.Write("2`r")
                    $selectionCount++
                    $rolling = ''
                    $selectionLine =
                        "SELECTED_L0R count=$selectionCount " +
                        "$([DateTimeOffset]::Now.ToString('o'))`n"
                    [System.IO.File]::AppendAllText(
                        $statusLog,
                        $selectionLine,
                        $encoding
                    )
                    $writer.Write(
                        "`r`n--- host sent menu choice 2 (l0r) ---`r`n"
                    )
                    $writer.Flush()
                    Write-Output "L0R_SELECTED count=$selectionCount"
                }
            }
            Start-Sleep -Milliseconds 25
        }
    }
    finally {
        $writer.Dispose()
    }
}
finally {
    if ($port.IsOpen) {
        $port.Close()
    }
    $port.Dispose()
}

$serialText = [System.IO.File]::ReadAllText($serialLog)
Write-Output "l0r-selection-count=$selectionCount"
Write-Output "serial-bytes=$([System.IO.FileInfo]::new($serialLog).Length)"
foreach ($pattern in @(
    'sunxi_de_atomic_flush',
    'L1 Page table invalid',
    'L2 Page table invalid',
    'rcu_preempt detected stalls',
    'Unable to handle kernel',
    'Kernel panic'
)) {
    $count = ([regex]::Matches($serialText, [regex]::Escape($pattern))).Count
    Write-Output "$pattern=$count"
}
