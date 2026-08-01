param(
    [Parameter(Mandatory = $true)]
    [string]$RunDirectory,
    [string]$UserName = 'radxa'
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $RunDirectory 'rollback-v002-over-serial.log'
$encoding = [System.Text.UTF8Encoding]::new($false)
$port = [System.IO.Ports.SerialPort]::new(
    'COM4',
    115200,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$port.ReadTimeout = 200

function Read-SerialUntil {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [int]$TimeoutSeconds = 15
    )
    $received = ''
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $text = $port.ReadExisting()
        if ($text.Length -gt 0) {
            $received += $text
            [System.IO.File]::AppendAllText($logPath, $text, $encoding)
            if ($received -match $Pattern) {
                return $received
            }
        }
        Start-Sleep -Milliseconds 35
    }
    throw "Timed out waiting for serial pattern: $Pattern"
}

function Send-SerialLine {
    param([Parameter(Mandatory = $true)][string]$Text)
    $port.Write($Text + "`r")
}

try {
    if ([string]::IsNullOrWhiteSpace($env:RADXA_SERIAL_PASSWORD)) {
        throw 'Set RADXA_SERIAL_PASSWORD before starting the serial rollback.'
    }
    $port.Open()
    [System.IO.File]::WriteAllText(
        $logPath,
        "--- rollback serial session " +
        "$([DateTimeOffset]::Now.ToString('o')) ---`r`n",
        $encoding
    )
    $pending = $port.ReadExisting()
    if ($pending.Length -gt 0) {
        [System.IO.File]::AppendAllText($logPath, $pending, $encoding)
    }

    Send-SerialLine $UserName
    Read-SerialUntil -Pattern 'Password:' -TimeoutSeconds 10 | Out-Null
    Send-SerialLine $env:RADXA_SERIAL_PASSWORD
    Read-SerialUntil -Pattern '[$#][ ]*$' -TimeoutSeconds 15 | Out-Null

    Send-SerialLine "sudo -S -p '__SUDO_PASSWORD__' -v"
    Read-SerialUntil -Pattern '__SUDO_PASSWORD__' -TimeoutSeconds 10 | Out-Null
    Send-SerialLine $env:RADXA_SERIAL_PASSWORD
    Read-SerialUntil -Pattern '[$#][ ]*$' -TimeoutSeconds 15 | Out-Null

    $rollback = @'
sudo -n sh -c 'set -eu; A=/boot/dtbo/cubie-a7a-meizu-e3-display-v002.dtbo; D=$A.disabled; test -f "$A"; test ! -e "$D"; mv "$A" "$D"; /usr/sbin/u-boot-update; sync'
'@
    Send-SerialLine $rollback.Trim()
    Read-SerialUntil -Pattern '[$#][ ]*$' -TimeoutSeconds 45 | Out-Null

    $verify = @'
echo __VERIFY_BEGIN__; cat /proc/cmdline; printf "active-count="; find /boot/dtbo -maxdepth 1 -type f -name "*.dtbo" | wc -l; find /boot/dtbo -maxdepth 1 -type f -name "cubie-a7a-meizu-e3*" -printf "%f\n" | sort; sha256sum /boot/dtbo/cubie-a7a-meizu-e3-display-v002.dtbo.disabled; awk '/^label |^[[:space:]]*fdtoverlays|^[[:space:]]*append /{print NR ":" $0}' /boot/extlinux/extlinux.conf; echo __VERIFY_DONE__
'@
    Send-SerialLine $verify.Trim()
    $result = Read-SerialUntil -Pattern '__VERIFY_DONE__' -TimeoutSeconds 20

    if ($result -notmatch 'single') {
        throw 'Rollback ran outside the expected l0r single boot'
    }
    if ($result -notmatch 'active-count=0') {
        throw 'Active DTBO count is not zero after rollback'
    }
    if ($result -notmatch 'b05d2220b31452a46ffb83940f349d1827be0d4c8e352f36b9e04fb9b0db3be2') {
        throw 'Disabled v002 DTBO hash mismatch after rollback'
    }
    if ($result -match '(?m)^[0-9]+:[ \t]*fdtoverlays') {
        throw 'Generated extlinux.conf still contains fdtoverlays'
    }

    Write-Output 'ROLLBACK_VALIDATED'
}
finally {
    if ($port.IsOpen) {
        $port.Close()
    }
    $port.Dispose()
}

Get-Content -Encoding UTF8 $logPath -Tail 180
