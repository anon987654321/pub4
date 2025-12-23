#!/usr/bin/env pwsh
# continuous-speak.ps1 - Non-stop speech with voice selection
# Version: 1.0.0
# Press Ctrl+C to stop

Add-Type -AssemblyName System.Speech
$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer

Write-Host "Available voices:" -ForegroundColor Cyan
$voices = $synth.GetInstalledVoices()
$i = 1
foreach ($voice in $voices) {
    $v = $voice.VoiceInfo
    Write-Host "$i. $($v.Name) - $($v.Culture) - $($v.Gender) - Age: $($v.Age)"
    $i++
}

Write-Host "`nSelect voice number (or press Enter for Zira): " -NoNewline
$choice = Read-Host
if ($choice -match '^d+$' -and [int]$choice -le $voices.Count) {
    $selectedVoice = $voices[[int]$choice - 1].VoiceInfo.Name
    $synth.SelectVoice($selectedVoice)
    Write-Host "Using: $selectedVoice" -ForegroundColor Green
} else {
    $synth.SelectVoice("Microsoft Zira Desktop")
    Write-Host "Using: Microsoft Zira Desktop (default)" -ForegroundColor Green
}

$synth.Rate = 0

$phrases = @(
    "Continuous speech mode active.",
    "Speaking without interruption.",
    "Testing voice clarity and rhythm.",
    "Short sentences work best for comprehension.",
    "Pauses help understanding.",
    "Natural cadence matters.",
    "Windows speech synthesis running.",
    "Press control C to stop.",
    "Loop continues indefinitely.",
    "Each phrase speaks clearly.",
    "System maintains steady pace.",
    "Voice quality stable.",
    "Audio output consistent.",
    "Ready for extended operation.",
    "Monitoring for stop signal."
)

Write-Host "`nSpeaking continuously (Ctrl+C to stop)..." -ForegroundColor Yellow
Write-Host ""

$counter = 1
try {
    while ($true) {
        foreach ($phrase in $phrases) {
            Write-Host "[$counter] $phrase"
            $synth.Speak($phrase)
            $counter++
            Start-Sleep -Milliseconds 500
        }
    }
} catch {
    Write-Host "`nStopped." -ForegroundColor Red
}
