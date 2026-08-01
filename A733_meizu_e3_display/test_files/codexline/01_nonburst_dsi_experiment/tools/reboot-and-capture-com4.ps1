param(
    [Parameter(Mandatory = $true)]
    [string]$RunDirectory,
    [int]$CaptureSeconds = 48,
    [switch]$SkipReboot,
    [string]$HostName = $env:RADXA_HOST,
    [string]$UserName = 'radxa',
    [string]$KnownHostsPath = $env:RADXA_KNOWN_HOSTS
)

$ErrorActionPreference = 'Stop'
$serialLog = Join-Path $RunDirectory 'v002-serial-live.log'
$actionLog = Join-Path $RunDirectory 'reboot-action.txt'
$helper = Join-Path $RunDirectory 'reboot-radxa.py'
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
    [System.IO.File]::AppendAllText(
        $serialLog,
        "`r`n--- capture opened $([DateTimeOffset]::Now.ToString('o')) ---`r`n",
        $encoding
    )

    if (-not $SkipReboot) {
        if ([string]::IsNullOrWhiteSpace($env:RADXA_TEST_PASSWORD)) {
            throw 'Set RADXA_TEST_PASSWORD before requesting an SSH reboot.'
        }
        if ([string]::IsNullOrWhiteSpace($HostName)) {
            throw 'Pass -HostName or set RADXA_HOST.'
        }
        if ([string]::IsNullOrWhiteSpace($KnownHostsPath)) {
            throw 'Pass -KnownHostsPath or set RADXA_KNOWN_HOSTS.'
        }
        $env:PYTHONWARNINGS = 'ignore'
        try {
            $savedErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $action = & python $helper `
                --host $HostName `
                --user $UserName `
                --known-hosts $KnownHostsPath 2>&1
            $helperExitCode = $LASTEXITCODE
            $ErrorActionPreference = $savedErrorActionPreference
            $actionText = ($action | Out-String)
            [System.IO.File]::WriteAllText($actionLog, $actionText, $encoding)
            $action | ForEach-Object { Write-Output $_ }
            if ($helperExitCode -ne 0) {
                throw "Reboot helper failed with exit code $helperExitCode"
            }
        }
        finally {
            $ErrorActionPreference = 'Stop'
            Remove-Item Env:PYTHONWARNINGS -ErrorAction SilentlyContinue
        }
    }

    $writer = [System.IO.StreamWriter]::new($serialLog, $true, $encoding)
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds($CaptureSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $text = $port.ReadExisting()
            if ($text.Length -gt 0) {
                $writer.Write($text)
                $writer.Flush()
            }
            Start-Sleep -Milliseconds 35
        }
        $text = $port.ReadExisting()
        if ($text.Length -gt 0) {
            $writer.Write($text)
            $writer.Flush()
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
$patterns = @(
    'sunxi_de_atomic_flush',
    'L1 Page table invalid',
    'L2 Page table invalid',
    'Bug in DE',
    'rcu_preempt detected stalls',
    'Unable to handle kernel',
    'Kernel panic'
)
foreach ($pattern in $patterns) {
    $count = ([regex]::Matches($serialText, [regex]::Escape($pattern))).Count
    Write-Output "$pattern=$count"
}
Write-Output "serial-bytes=$([System.IO.FileInfo]::new($serialLog).Length)"
