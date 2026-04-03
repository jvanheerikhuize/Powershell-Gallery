# Ollama Live Request Monitor
# Monitors active Ollama connections and displays live updates in the CLI

param(
    [string]$OllamaHost = "http://localhost:11434",
    [int]$RefreshInterval = 2,
    [switch]$Verbose,
    [switch]$VerbosePrompt,
    [switch]$ShowGenerationDetails,
    [string]$EventLogPath = "$HOME/.ollama_monitor_events.json",
    [int]$MaxHistory = 200
)

# Track request history
$script:PreviousModels = @{}
$script:MaxHistory = $MaxHistory

# Load persistent event log
function Load-EventLog {
    if (Test-Path $EventLogPath) {
        try {
            $raw = Get-Content $EventLogPath -Raw | ConvertFrom-Json
            $list = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($entry in $raw) {
                $list.Add([PSCustomObject]@{
                    Time    = [DateTime]$entry.Time
                    Model   = $entry.Model
                    Event   = $entry.Event
                    Details = $entry.Details
                    Client  = if ($entry.Client) { $entry.Client } else { "" }
                    Prompt  = if ($entry.Prompt) { $entry.Prompt } else { "" }
                })
            }
            return $list
        } catch {
            return [System.Collections.Generic.List[PSCustomObject]]::new()
        }
    }
    return [System.Collections.Generic.List[PSCustomObject]]::new()
}

function Save-EventLog {
    try {
        $script:RequestHistory | Select-Object Time, Model, Event, Details, Client, Prompt |
            ConvertTo-Json -Depth 3 -Compress |
            Set-Content $EventLogPath -Force
    } catch {}
}

$script:RequestHistory = Load-EventLog
$script:EventLogDirty = $false

function Write-Header {
    $width = [Math]::Max(60, $Host.UI.RawUI.WindowSize.Width - 2)
    $border = [string]::new([char]0x2550, $width - 2)
    Write-Host ([char]0x2554 + $border + [char]0x2557) -ForegroundColor Cyan
    $title = "  OLLAMA LIVE CONNECTION MONITOR"
    $padding = $width - 2 - $title.Length
    Write-Host ([string]([char]0x2551) + $title + (' ' * [Math]::Max(0, $padding)) + [char]0x2551) -ForegroundColor Cyan
    Write-Host ([char]0x255A + $border + [char]0x255D) -ForegroundColor Cyan
    Write-Host "  Host: $OllamaHost  |  Refresh: ${RefreshInterval}s  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  Ctrl+C to quit" -ForegroundColor DarkGray
    if ($Verbose) {
        Write-Host "  [VERBOSE MODE]" -ForegroundColor Yellow
    }
    if ($VerbosePrompt) {
        Write-Host "  [PROMPT MONITORING ENABLED]" -ForegroundColor Magenta
    }
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

function Get-OllamaGenerationStatus {
    # Try to get generation progress info if available
    $generationStatus = $null
    
    try {
        # Check for active generations
        $generationStatus = Invoke-RestMethod -Uri "$OllamaHost/api/generate" -Method Get -TimeoutSec 5 -ErrorAction Stop
    } catch {
        # Generation endpoint might not be available or no active generation
        $generationStatus = @{
            Active = $false
            Message = "No active generation or endpoint not available"
        }
    }
    
    return $generationStatus
}

function Format-Bytes {
    param([long]$Bytes)
    $oneGB = 1024 * 1024 * 1024
    $oneMB = 1024 * 1024
    $oneKB = 1024
    if ($Bytes -ge $oneGB) { return "{0:N1} GB" -f ($Bytes / $oneGB) }
    if ($Bytes -ge $oneMB) { return "{0:N1} MB" -f ($Bytes / $oneMB) }
    if ($Bytes -ge $oneKB) { return "{0:N1} KB" -f ($Bytes / $oneKB) }
    return "$Bytes B"
}

function Format-Duration {
    param([TimeSpan]$Duration)
    if ($Duration.TotalHours -ge 1) { return "{0:N0}h {1:N0}m" -f $Duration.TotalHours, $Duration.Minutes }
    if ($Duration.TotalMinutes -ge 1) { return "{0:N0}m {1:N0}s" -f $Duration.TotalMinutes, $Duration.Seconds }
    return "{0:N0}s" -f $Duration.TotalSeconds
}

function Get-ConnectedClients {
    # Parse the Ollama host to get the port
    $uri = [Uri]$OllamaHost
    $port = $uri.Port

    $clients = @()
    try {
        # Use ss to find established TCP connections to the Ollama port
        $ssOutput = & ss -tn state established "( dport = :$port or sport = :$port )" 2>/dev/null
        foreach ($line in $ssOutput) {
            if ($line -match '^\s*ESTAB' -or $line -match '^\d') {
                # Parse ss output: State Recv-Q Send-Q Local:Port Peer:Port
                $parts = $line.Trim() -split '\s+'
                if ($parts.Count -ge 5) {
                    $peer = $parts[4]
                } elseif ($parts.Count -ge 4) {
                    $peer = $parts[3]
                } else {
                    continue
                }
                # Extract IP from peer address (handle IPv6 bracket notation and IPv4)
                if ($peer -match '^\[(.+)\]:(\d+)$') {
                    $ip = $Matches[1]
                    $peerPort = $Matches[2]
                } elseif ($peer -match '^(.+):(\d+)$') {
                    $ip = $Matches[1]
                    $peerPort = $Matches[2]
                } else {
                    continue
                }
                # Skip our own monitor connections (we connect from ephemeral ports)
                $clients += [PSCustomObject]@{
                    IP   = $ip
                    Port = $peerPort
                    Peer = $peer
                }
            }
        }
    } catch {}
    return $clients
}

function Get-OllamaRequestLog {
    # Try to capture recent prompts from Ollama's journal logs
    $requests = @()
    try {
        # Get last 60 seconds of ollama logs, look for request lines
        $logs = & journalctl -u ollama --since "60 seconds ago" --no-pager -o cat 2>/dev/null
        if ($logs) {
            foreach ($line in $logs) {
                # Ollama logs requests with prompt content
                if ($line -match '"prompt"\s*:\s*"([^"]{1,200})') {
                    $prompt = $Matches[1] -replace '\\n', ' '
                    $requests += $prompt
                }
                # Also match the model being requested
                if ($line -match '"model"\s*:\s*"([^"]+)"') {
                    # just capture, we correlate elsewhere
                }
            }
        }
    } catch {}
    return $requests
}

function Update-RequestHistory {
    param($RunningModels, $Clients)

    $now = Get-Date
    $currentModels = @{}

    # Get recent prompts from logs
    $recentPrompts = Get-OllamaRequestLog

    # Build a client summary string
    $clientSummary = if ($Clients -and $Clients.Count -gt 0) {
        ($Clients | ForEach-Object { $_.IP } | Select-Object -Unique) -join ", "
    } else { "" }

    $promptSummary = if ($recentPrompts -and $recentPrompts.Count -gt 0) {
        $p = $recentPrompts[-1]
        if ($p.Length -gt 80) { $p.Substring(0, 80) + "..." } else { $p }
    } else { "" }

    foreach ($model in $RunningModels) {
        $key = $model.name
        $currentModels[$key] = $true

        if (-not $script:PreviousModels.ContainsKey($key)) {
            $script:RequestHistory.Add([PSCustomObject]@{
                Time    = $now
                Model   = $model.name
                Event   = "LOADED"
                Details = "Size: $(Format-Bytes $model.size)"
                Client  = $clientSummary
                Prompt  = $promptSummary
            })
            $script:EventLogDirty = $true
        }
    }

    foreach ($key in @($script:PreviousModels.Keys)) {
        if (-not $currentModels.ContainsKey($key)) {
            $script:RequestHistory.Add([PSCustomObject]@{
                Time    = $now
                Model   = $key
                Event   = "UNLOADED"
                Details = ""
                Client  = ""
                Prompt  = ""
            })
            $script:EventLogDirty = $true
        }
    }

    # Track active request events (prompt activity on already-loaded models)
    if ($promptSummary -and $clientSummary) {
        $lastRequest = $script:RequestHistory | Where-Object { $_.Event -eq "REQUEST" } | Select-Object -Last 1
        $isDuplicate = $lastRequest -and $lastRequest.Prompt -eq $promptSummary -and
                       ($now - $lastRequest.Time).TotalSeconds -lt 10
        if (-not $isDuplicate) {
            $activeModel = if ($RunningModels.Count -gt 0) { $RunningModels[0].name } else { "unknown" }
            $script:RequestHistory.Add([PSCustomObject]@{
                Time    = $now
                Model   = $activeModel
                Event   = "REQUEST"
                Details = ""
                Client  = $clientSummary
                Prompt  = $promptSummary
            })
            $script:EventLogDirty = $true
        }
    }

    $script:PreviousModels = $currentModels

    # Trim history
    while ($script:RequestHistory.Count -gt $script:MaxHistory) {
        $script:RequestHistory.RemoveAt(0)
    }

    # Persist if changed
    if ($script:EventLogDirty) {
        Save-EventLog
        $script:EventLogDirty = $false
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

    # Connected clients section
    $clients = Get-ConnectedClients
    Write-Host "  CONNECTED CLIENTS ($($clients.Count))" -ForegroundColor Yellow
    Write-Host $divider -ForegroundColor DarkGray

    if ($clients.Count -eq 0) {
        Write-Host "  (no active client connections)" -ForegroundColor DarkGray
    } else {
        $grouped = $clients | Group-Object IP
        foreach ($group in $grouped) {
            $connCount = $group.Count
            $ports = ($group.Group | ForEach-Object { $_.Port }) -join ", "
            Write-Host "  * " -ForegroundColor Green -NoNewline
            Write-Host "$($group.Name)" -ForegroundColor White -NoNewline
            Write-Host "  ($connCount connection$(if ($connCount -ne 1) {'s'}))" -ForegroundColor DarkGray -NoNewline
            if ($Verbose) {
                Write-Host "  ports: $ports" -ForegroundColor DarkGray
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

    # Generation status section (if enabled)
    if ($ShowGenerationDetails) {
        Write-Host ""
        Write-Host "  GENERATION STATUS" -ForegroundColor Magenta
        Write-Host $divider -ForegroundColor DarkGray

        $genStatus = Get-OllamaGenerationStatus
        
        if ($genStatus.Active) {
            Write-Host "  [ACTIVE GENERATION]" -ForegroundColor Green
            Write-Host "    Model: $($genStatus.model)" -ForegroundColor Gray
            Write-Host "    Status: $($genStatus.status)" -ForegroundColor Gray
            Write-Host "    Total Tokens: $($genStatus.total_duration)" -ForegroundColor Gray
            Write-Host "    Prompt: $($genStatus.prompt)" -ForegroundColor DarkYellow
            Write-Host "    Response: $($genStatus.response)" -ForegroundColor DarkYellow
        } else {
            Write-Host "  [NO ACTIVE GENERATION]" -ForegroundColor DarkGray
        }
    }

    # Event history section
    if ($script:RequestHistory.Count -gt 0) {
        Write-Host ""
        $showCount = [Math]::Min(15, $script:RequestHistory.Count)
        Write-Host "  EVENT LOG (last $showCount of $($script:RequestHistory.Count) total | saved to $EventLogPath)" -ForegroundColor Magenta
        Write-Host $divider -ForegroundColor DarkGray

        $recent = $script:RequestHistory | Select-Object -Last 15
        foreach ($entry in $recent) {
            $time = $entry.Time.ToString("yyyy-MM-dd HH:mm:ss")
            $eventColor = switch ($entry.Event) {
                "LOADED"   { "Green" }
                "UNLOADED" { "DarkYellow" }
                "REQUEST"  { "Cyan" }
                default    { "Gray" }
            }
            $details = if ($entry.Details) { " - $($entry.Details)" } else { "" }
            $client = if ($entry.Client) { " from $($entry.Client)" } else { "" }

            Write-Host "  [$time] " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($entry.Event)" -ForegroundColor $eventColor -NoNewline
            Write-Host " $($entry.Model)$details$client" -ForegroundColor White

            # Show prompt on a second line if present
            if ($entry.Prompt -and ($VerbosePrompt -or $entry.Event -eq "REQUEST")) {
                $promptDisplay = if ($entry.Prompt.Length -gt 100) {
                    $entry.Prompt.Substring(0, 100) + "..."
                } else { $entry.Prompt }
                Write-Host "    prompt: $promptDisplay" -ForegroundColor DarkMagenta
            }
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
            $clients = Get-ConnectedClients
            Update-RequestHistory -RunningModels $status.RunningModels -Clients $clients
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
    Save-EventLog
    Write-Host ""
    Write-Host "Monitor stopped. Event log saved to $EventLogPath" -ForegroundColor Yellow
}
