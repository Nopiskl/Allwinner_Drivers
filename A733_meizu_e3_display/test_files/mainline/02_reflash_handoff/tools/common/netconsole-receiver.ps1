param(
    [string]$BindAddress = "0.0.0.0",
    [int]$Port = 6666,
    [string]$LogPath = (Join-Path $PSScriptRoot 'radxa-netconsole.log')
)

$endpoint = [System.Net.IPEndPoint]::new(
    [System.Net.IPAddress]::Parse($BindAddress),
    $Port
)
$udp = [System.Net.Sockets.UdpClient]::new()
$udp.Client.SetSocketOption(
    [System.Net.Sockets.SocketOptionLevel]::Socket,
    [System.Net.Sockets.SocketOptionName]::ReuseAddress,
    $true
)
$udp.Client.Bind($endpoint)

$utf8 = [System.Text.UTF8Encoding]::new($false)
$started = "{0:o} receiver started on {1}:{2}`n" -f
    [DateTimeOffset]::Now, $BindAddress, $Port
[System.IO.File]::AppendAllText($LogPath, $started, $utf8)

try {
    while ($true) {
        $remote = [System.Net.IPEndPoint]::new(
            [System.Net.IPAddress]::Any,
            0
        )
        $payload = $udp.Receive([ref]$remote)
        $message = $utf8.GetString($payload)
        $line = "{0:o} {1}:{2} {3}" -f
            [DateTimeOffset]::Now, $remote.Address, $remote.Port, $message
        if (-not $line.EndsWith("`n")) {
            $line += "`n"
        }
        [System.IO.File]::AppendAllText($LogPath, $line, $utf8)
    }
}
finally {
    $udp.Dispose()
}
