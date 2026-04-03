# Ollama Live Request Monitor
# Monitors active Ollama connections and displays live updates in the CLI

param(
    [string]$OllamaHost = "http://localhost:11434",
    [int]$RefreshInterval = 2,
    [switch]$Verbose
)

# Track request history
$script:RequestHistory = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:PreviousModels = @{}
$script:MaxHistory = 50

function Write-Header {
    $width = [Math]::Max(60, $Host.UI.RawUI.WindowSize.Width - 2)
    $border = [string]::new([char]0x2550, $width - 2)
    Write-Host ([char]0x2554 + $border + [char]0x2557) -ForegroundColor Cyan
    $title = "  OLLAMA LIVE CONNECTION MONITOR"
    $padding = $width - 2 - $title.Length
    Write-Host ([string]([char]0x2551) + $title + (' ' * [Math]::Max(0, $padding)) + [char]0x2551) -ForegroundColor Cyan
    Write-Host ([char]0x255A + $border + [char]0x255D) -ForegroundColor Cyan
    Write-Host "  Host: $OllamaHost  |  Refresh: ${RefreshInterval}s  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  Ctrl+C to quit" -ForegroundColor DarkGray
    Write-Host ""
}

function Get-OllamaStatus {
    # Fetch running models (active connections) and available models in parallel
    $ps = $null
    $tags = $null

    try {
        $ps = Invoke-RestMethod -Uri "$OllamaHost/api/ps" -Method Get -TimeoutSec 5 -ErrorAction Stop
    } catch {
        return @{ Online = $false; Error = $_.Exception.Message }
    }

    try {
        $tags = Invoke-RestMethod -Uri "$OllamaHost/api/tags" -Method Get -TimeoutSec 5 -ErrorAction Stop
    } catch {}

    return @{
        Online = $true
        RunningModels = if ($ps.models) { @($ps.models) } else { @() }
        AvailableModels = if ($tags -and $tags.models) { @($tags.models) } else { @() }
    }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Format-Duration {
    param([TimeSpan]$Duration)
    if ($Duration.TotalHours -ge 1) { return "{0:N0}h {1:N0}m" -f $Duration.TotalHours, $Duration.Minutes }
    if ($Duration.TotalMinutes -ge 1) { return "{0:N0}m {1:N0}s" -f $Duration.TotalMinutes, $Duration.Seconds }
    return "{0:N0}s" -f $Duration.TotalSeconds
}

function Update-RequestHistory {
    param($RunningModels)

    $now = Get-Date
    $currentModels = @{}

    foreach ($model in $RunningModels) {
        $key = $model.name
        $currentModels[$key] = $true

        if (-not $script:PreviousModels.ContainsKey($key)) {
            # New model loaded - a new connection started
            $script:RequestHistory.Add([PSCustomObject]@{
                Time      = $now
                Model     = $model.name
                Event     = "LOADED"
                Details   = "Size: $(Format-Bytes $model.size)"
            })
        }
    }

    foreach ($key in @($script:PreviousModels.Keys)) {
        if (-not $currentModels.ContainsKey($key)) {
            # Model was unloaded
            $script:RequestHistory.Add([PSCustomObject]@{
                Time      = $now
                Model     = $key
                Event     = "UNLOADED"
                Details   = ""
            })
        }
    }

    $script:PreviousModels = $currentModels

    # Trim history
    while ($script:RequestHistory.Count -gt $script:MaxHistory) {
        $script:RequestHistory.RemoveAt(0)
    }
}

function Write-Dashboard {
    param($Status)

    Clear-Host
    Write-Header

    if (-not $Status.Online) {
        Write-Host "  [OFFLINE] Cannot connect to Ollama" -ForegroundColor Red
        Write-Host "  Error: $($Status.Error)" -ForegroundColor DarkRed
        Write-Host ""
        Write-Host "  Make sure Ollama is running: ollama serve" -ForegroundColor Yellow
        return
    }

    Write-Host "  SERVER STATUS: ONLINE" -ForegroundColor Green
    Write-Host ""

    # Active connections section
    $running = $Status.RunningModels
    $divider = "  " + ("-" * 56)

    Write-Host "  ACTIVE CONNECTIONS ($($running.Count))" -ForegroundColor Yellow
    Write-Host $divider -ForegroundColor DarkGray

    if ($running.Count -eq 0) {
        Write-Host "  (no active connections)" -ForegroundColor DarkGray
    } else {
        foreach ($model in $running) {
            $name = $model.name
            $size = Format-Bytes $model.size
            $vramSize = if ($model.size_vram) { Format-Bytes $model.size_vram } else { "N/A" }

            # Calculate how long the model has been loaded
            $expiresAt = $null
            $runningFor = ""
            if ($model.expires_at) {
                try {
                    $expiresAt = [DateTimeOffset]::Parse($model.expires_at)
                    $remaining = $expiresAt - [DateTimeOffset]::Now
                    if ($remaining.TotalSeconds -gt 0) {
                        $runningFor = "expires in $(Format-Duration $remaining)"
                    } else {
                        $runningFor = "expiring..."
                    }
                } catch {
                    $runningFor = ""
                }
            }

            $details = $model.details
            $quantization = if ($details.quantization_level) { $details.quantization_level } else { "" }
            $family = if ($details.family) { $details.family } else { "" }
            $paramSize = if ($details.parameter_size) { $details.parameter_size } else { "" }

            Write-Host "  * " -ForegroundColor Green -NoNewline
            Write-Host "$name" -ForegroundColor White -NoNewline
            Write-Host "  [$paramSize $family $quantization]" -ForegroundColor DarkGray

            Write-Host "    RAM: $size  |  VRAM: $vramSize" -ForegroundColor Gray -NoNewline
            if ($runningFor) {
                Write-Host "  |  $runningFor" -ForegroundColor DarkYellow
            } else {
                Write-Host ""
            }
        }
    }

    Write-Host ""

    # Available models section
    $available = $Status.AvailableModels
    Write-Host "  AVAILABLE MODELS ($($available.Count))" -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor DarkGray

    if ($available.Count -eq 0) {
        Write-Host "  (no models installed)" -ForegroundColor DarkGray
    } else {
        foreach ($model in $available) {
            $isActive = $running | Where-Object { $_.name -eq $model.name }
            $indicator = if ($isActive) { "[ACTIVE]" } else { "        " }
            $color = if ($isActive) { "Green" } else { "Gray" }
            $size = Format-Bytes $model.size

            Write-Host "  $indicator " -ForegroundColor $color -NoNewline
            Write-Host "$($model.name)" -ForegroundColor White -NoNewline
            Write-Host "  ($size)" -ForegroundColor DarkGray
        }
    }

    # Event history section
    if ($script:RequestHistory.Count -gt 0) {
        Write-Host ""
        Write-Host "  EVENT LOG (last $([Math]::Min(10, $script:RequestHistory.Count)))" -ForegroundColor Magenta
        Write-Host $divider -ForegroundColor DarkGray

        $recent = $script:RequestHistory | Select-Object -Last 10
        foreach ($entry in $recent) {
            $time = $entry.Time.ToString("HH:mm:ss")
            $eventColor = if ($entry.Event -eq "LOADED") { "Green" } else { "DarkYellow" }
            $details = if ($entry.Details) { " - $($entry.Details)" } else { "" }
            Write-Host "  [$time] " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($entry.Event)" -ForegroundColor $eventColor -NoNewline
            Write-Host " $($entry.Model)$details" -ForegroundColor White
        }
    }

    Write-Host ""
}

# Main loop
try {
    [Console]::CursorVisible = $false

    while ($true) {
        $status = Get-OllamaStatus

        if ($status.Online) {
            Update-RequestHistory -RunningModels $status.RunningModels
        }

        Write-Dashboard -Status $status
        Start-Sleep -Seconds $RefreshInterval
    }
} catch {
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException] -or
        $_.Exception.InnerException -is [System.OperationCanceledException]) {
        # Ctrl+C - graceful exit
    } else {
        Write-Host "Error: $_" -ForegroundColor Red
    }
} finally {
    [Console]::CursorVisible = $true
    Write-Host ""
    Write-Host "Monitor stopped." -ForegroundColor Yellow
}
