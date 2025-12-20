#!/usr/bin/env pwsh
# gh-speak-stream.ps1 - Streaming speech for Copilot
# Version: 1.1.0
# Speaks each line as it arrives

param([string[]]$Query)

Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SelectVoice("Microsoft Zira Desktop")
$synth.Rate = 0

$text = ($Query -join ' ').Trim()

if (!$text) {
    Write-Host "Usage: gh-speak-stream.ps1 'question'"
    exit 1
}

Write-Host "Question: $text"

# Replace with: gh copilot suggest $text
"Line one.", "Line two.", "Line three." | ForEach-Object {
    Write-Host $_
    if ($_ -match 'w') { $synth.Speak($_) }
}

Write-Host "Done"
