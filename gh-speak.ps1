#!/usr/bin/env pwsh
# gh-speak.ps1 - GitHub Copilot with speech
# Version: 1.1.0
# Usage: .gh-speak.ps1 "your question"

param([string[]]$Query)

Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SelectVoice("Microsoft Zira Desktop")
$synth.Rate = 0

$text = ($Query -join ' ').Trim()

if (!$text) {
    Write-Host "Usage: gh-speak.ps1 'question'" -ForegroundColor Red
    exit 1
}

Write-Host "Question: $text"
$synth.SpeakAsync("Question: $text") | Out-Null

# Demo response (replace with: gh copilot suggest $text)
$answer = "Speech works. Install GitHub Copilot CLI to connect. Run: gh extension install github slash copilot"

Write-Host $answer
$synth.Speak($answer)
Write-Host "Done"
