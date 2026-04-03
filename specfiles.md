# Ollama Monitor PowerShell Script - Test Specifications

## Overview
This document contains test specifications for the ollama_monitor.ps1 PowerShell script based on the repository analysis.

## Test Suite: Basic Functionality

### Test Case 1: Script Initialization
**Description**: Verify script initializes correctly with default parameters
**Preconditions**: 
- PowerShell 7+ installed
- Ollama server running locally
**Steps**:
1. Execute `./ollama_monitor.ps1` without parameters
2. Verify default values are set correctly
3. Verify script starts without errors
**Expected Results**:
- Script runs without errors
- Default OllamaHost = "http://localhost:11434"
- Default RefreshInterval = 2
- Default EventLogPath = "$HOME/.ollama_monitor_events.json"

### Test Case 2: Parameter Parsing
**Description**: Verify all command-line parameters are parsed correctly
**Preconditions**: 
- PowerShell 7+ installed
- Ollama server running locally
**Steps**:
1. Execute script with various parameter combinations
2. Verify each parameter is correctly assigned
**Expected Results**:
- All parameters are correctly parsed and assigned
- Parameter validation works as expected

## Test Suite: Network Connectivity

### Test Case 3: Ollama Server Status
**Description**: Verify script can connect to Ollama server and retrieve status
**Preconditions**: 
- Ollama server running
**Steps**:
1. Execute script with valid Ollama server
2. Monitor dashboard output
3. Verify server status is displayed as "ONLINE"
**Expected Results**:
- Server status shows "ONLINE"
- Active connections are displayed
- Available models are listed

### Test Case 4: Offline Server Handling
**Description**: Verify script handles offline Ollama server gracefully
**Preconditions**: 
- Ollama server not running
**Steps**:
1. Execute script with offline Ollama server
2. Monitor dashboard output
**Expected Results**:
- Server status shows "OFFLINE"
- Error message is displayed
- Script continues running without crashing

## Test Suite: Dashboard Functionality

### Test Case 5: Active Connections Display
**Description**: Verify active model connections are displayed correctly
**Preconditions**: 
- Ollama server with loaded models
**Steps**:
1. Load a model in Ollama
2. Execute monitor script
3. Observe active connections section
**Expected Results**:
- Model name is displayed
- RAM/VRAM usage is shown
- Model details (family, quantization) are displayed

### Test Case 6: Connected Clients Detection
**Description**: Verify client detection via TCP sockets works correctly
**Preconditions**: 
- Ollama server running
- Client connections established
**Steps**:
1. Establish client connections to Ollama
2. Execute monitor script
3. Observe connected clients section
**Expected Results**:
- Client IP addresses are detected
- Connection counts are accurate
- Verbose mode shows port information

### Test Case 7: Available Models Display
**Description**: Verify available models are listed correctly
**Preconditions**: 
- Ollama server with installed models
**Steps**:
1. Execute monitor script
2. Observe available models section
**Expected Results**:
- All available models are listed
- Active models are marked appropriately
- Model sizes are displayed

## Test Suite: Event Logging

### Test Case 8: Persistent Event Log
**Description**: Verify event log persistence works correctly
**Preconditions**: 
- Ollama server running
**Steps**:
1. Execute monitor script
2. Generate some activity (load/unload models)
3. Exit script
4. Re-execute script
**Expected Results**:
- Event log file is created
- Events persist between script runs
- Event log is properly formatted JSON

### Test Case 9: Event History Management
**Description**: Verify event history is managed correctly
**Preconditions**: 
- Ollama server running
**Steps**:
1. Generate more than MaxHistory events
2. Execute monitor script
3. Check event log size
**Expected Results**:
- Event log is trimmed to MaxHistory limit
- Oldest events are removed
- Newest events are preserved

## Test Suite: Prompt Monitoring

### Test Case 10: Prompt Capture
**Description**: Verify prompt capture from Ollama logs works correctly
**Preconditions**: 
- Ollama server running as systemd service
- journalctl access available
**Steps**:
1. Execute monitor script with -VerbosePrompt
2. Generate model requests
3. Observe prompt display in event log
**Expected Results**:
- Prompts are captured from logs
- Prompts are displayed in event log
- Prompt length is truncated appropriately

## Test Suite: Generation Status

### Test Case 11: Generation Status Monitoring
**Description**: Verify generation status monitoring works correctly
**Preconditions**: 
- Ollama server running
- Active generation in progress
**Steps**:
1. Execute monitor script with -ShowGenerationDetails
2. Start a generation process
3. Observe generation status section
**Expected Results**:
- Generation status is displayed
- Model information is shown
- Generation progress details are available

## Test Suite: Error Handling

### Test Case 12: Graceful Exit Handling
**Description**: Verify script exits gracefully on Ctrl+C
**Preconditions**: 
- Script running
**Steps**:
1. Execute monitor script
2. Press Ctrl+C
3. Check exit behavior
**Expected Results**:
- Script exits cleanly
- Event log is saved
- Proper exit message is displayed

### Test Case 13: Network Timeout Handling
**Description**: Verify script handles network timeouts gracefully
**Preconditions**: 
- Ollama server temporarily unavailable
**Steps**:
1. Stop Ollama server
2. Execute monitor script
3. Wait for timeout
4. Restart Ollama server
**Expected Results**:
- Script handles timeout gracefully
- Error messages are displayed
- Script recovers when server is available

## Test Suite: Cross-Platform Compatibility

### Test Case 14: Linux System Requirements
**Description**: Verify Linux-specific requirements are met
**Preconditions**: 
- Linux system with PowerShell 7+
- Ollama server installed
- ss command available
- journalctl access available
**Steps**:
1. Execute monitor script on Linux
2. Verify all features work correctly
**Expected Results**:
- All features function as expected
- System utilities are properly invoked
- No platform-specific errors occur

## Test Suite: Performance

### Test Case 15: Refresh Interval Behavior
**Description**: Verify refresh interval works correctly
**Preconditions**: 
- Ollama server running
**Steps**:
1. Execute script with custom refresh interval
2. Monitor timing between updates
**Expected Results**:
- Updates occur at specified interval
- No excessive resource usage
- Dashboard refreshes smoothly

### Test Case 16: Memory Usage
**Description**: Verify memory usage is reasonable
**Preconditions**: 
- Long-running monitor session
**Steps**:
1. Run monitor script for extended period
2. Monitor memory consumption
**Expected Results**:
- Memory usage remains stable
- Event history is properly managed
- No memory leaks occur
```