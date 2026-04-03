# Powershell-Gallery

A collection of PowerShell scripts for system monitoring and automation on Linux.

## Scripts

### ollama_monitor.ps1

A live dashboard for monitoring [Ollama](https://ollama.com) server activity. Displays active model connections, connected clients, available models, and a persistent event log -- all in a refreshing terminal UI.

#### Features

- Real-time server status and active model connections with RAM/VRAM usage
- Connected client detection via TCP socket inspection
- Prompt capture from Ollama journal logs
- Persistent event log (survives restarts) saved to JSON
- Generation status monitoring
- Color-coded terminal dashboard with box-drawing UI

#### Usage

```powershell
# Basic monitoring
./ollama_monitor.ps1

# Custom host and refresh interval
./ollama_monitor.ps1 -OllamaHost "http://192.168.1.100:11434" -RefreshInterval 5

# Enable prompt monitoring in the event log
./ollama_monitor.ps1 -VerbosePrompt

# Show generation details and verbose output
./ollama_monitor.ps1 -ShowGenerationDetails -Verbose

# Custom event log location
./ollama_monitor.ps1 -EventLogPath "/var/log/ollama_monitor.json" -MaxHistory 500
```

#### Parameters

| Parameter | Default | Description |
|---|---|---|
| `-OllamaHost` | `http://localhost:11434` | Ollama server URL |
| `-RefreshInterval` | `2` | Dashboard refresh interval in seconds |
| `-Verbose` | off | Show verbose output (client ports, etc.) |
| `-VerbosePrompt` | off | Show prompts for all event types in the log |
| `-ShowGenerationDetails` | off | Show active generation status section |
| `-EventLogPath` | `~/.ollama_monitor_events.json` | Path to persistent event log |
| `-MaxHistory` | `200` | Maximum number of events to retain |

#### Requirements

- PowerShell 7+ (Linux)
- Ollama server running locally or on the network
- `ss` (from iproute2) for client detection
- `journalctl` access for prompt capture (optional, requires Ollama running as a systemd service)

## License

[MIT](LICENSE)
