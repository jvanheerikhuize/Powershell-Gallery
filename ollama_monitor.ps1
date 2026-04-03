# Ollama Live Request Monitor
# Monitors Ollama API requests and displays live updates in the CLI

param(
    [string]$OllamaHost = "http://localhost:11434",
    [string]$Model = "llama2",
    [string]$Prompt = "Hello, how are you?",
    [switch]$WatchMode = $true,
    [switch]$Verbose = $false
)

# Colors for terminal output
$Colors = @{
    Green = "Green"
    Yellow = "Yellow"
    Red = "Red"
    Cyan = "Cyan"
    White = "White"
    Blue = "Blue"
}

# Clear screen and set title
function Clear-Screen {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  OLLAMA LIVE REQUEST MONITOR                                 ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# Get current timestamp
function Get-Timestamp {
    return (Get-Date -Format "HH:mm:ss")
}

# Check if Ollama is running
function Test-OllamaConnection {
    try {
        $response = Invoke-RestMethod -Uri "$OllamaHost/api/tags" -Method Get -ErrorAction Stop
        Write-Host "✓ Ollama is running at $OllamaHost" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Cannot connect to Ollama at $OllamaHost" -ForegroundColor Red
        Write-Host "  Make sure Ollama is running: ollama serve" -ForegroundColor Yellow
        return $false
    }
}

# Monitor a single request
function Monitor-Request {
    param(
        [string]$Model,
        [string]$Prompt
    )
    
    $startTime = Get-Date
    $requestId = [Guid]::NewGuid().ToString().Substring(0, 8)
    
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  REQUEST ID: $requestId" -ForegroundColor Cyan
    Write-Host "  MODEL: $Model" -ForegroundColor Cyan
    Write-Host "  TIMESTAMP: $(Get-Timestamp)" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    # Send request to Ollama with streaming
    $response = Invoke-RestMethod -Uri "$OllamaHost/api/generate" -Method Post -ContentType "application/json" -Body @{
        model = $Model
        prompt = $Prompt
        stream = $true
    } | ConvertFrom-Json
    
    # Process streaming response
    $output = ""
    $elapsed = (Get-Date) - $startTime
    $elapsedStr = [math]::Round($elapsed.TotalSeconds, 2)
    
    if ($response.Stream) {
        $response.Stream | ForEach-Object {
            $data = $_ | ConvertFrom-Json
            $output += $data.Response
            Write-Host "  [STREAMING] $output" -ForegroundColor Green -NoNewline
            Write-Host "  (elapsed: $elapsedStr s)" -ForegroundColor Gray
            Start-Sleep -Milliseconds 10
        }
    }
    else {
        $output = $response.Response
        Write-Host "  [COMPLETE] $output" -ForegroundColor Green
        Write-Host "  (elapsed: $elapsedStr s)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  STATUS: COMPLETED" -ForegroundColor Green
    Write-Host "  DURATION: $elapsedStr s" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
}

# Main monitoring loop
function Start-Monitoring {
    if (-not $WatchMode) {
        Monitor-Request -Model $Model -Prompt $Prompt
        return
    }
    
    Write-Host "Starting live monitoring mode..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""
    
    while ($true) {
        Clear-Screen
        
        # Check connection
        if (-not (Test-OllamaConnection)) {
            Write-Host "Waiting for Ollama to be available..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            continue
        }
        
        # Get available models
        try {
            $models = Invoke-RestMethod -Uri "$OllamaHost/api/tags" -Method Get | ConvertFrom-Json
            Write-Host "Available Models:" -ForegroundColor Cyan
            $models.Models | ForEach-Object {
                Write-Host "  - $_.Name" -ForegroundColor Gray
            }
            Write-Host ""
        }
        catch {
            Write-Host "Error fetching models: $_" -ForegroundColor Red
        }
        
        # Monitor request
        Monitor-Request -Model $Model -Prompt $Prompt
        
        # Wait before next request
        Start-Sleep -Seconds 5
    }
}

# Main entry point
try {
    Clear-Screen
    Start-Monitoring
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Please check the error and try again." -ForegroundColor Yellow
}
