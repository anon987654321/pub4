# PowerShell Dilla Beat Generator
# Direct FFmpeg commands without Ruby

$ErrorActionPreference = "Continue"
$ffmpeg = "C:\cygwin64\bin\ffmpeg.exe"

$KICK = "808_bd_medium_r8_t1a.wav"
$SNARE = "808_sd_jd800_01.wav"
$HIHAT = "808_hh_jd800.wav"
$SAMPLE = "R-Mårdalen R.aif"

$BPM = 95
$BARS = 8
$DURATION = (60.0 / $BPM) * 4 * $BARS

Write-Host "Building Dilla beat: $BPM BPM, $BARS bars, $([math]::Round($DURATION,1))s"

# Step 1: Convert sample
Write-Host "`n1. Converting sample..."
& $ffmpeg -y -i $SAMPLE -t $DURATION -ar 48000 -ac 2 sample.wav *>&1 | Out-Null

# Step 2: SP-1200 effect
Write-Host "2. Applying SP-1200 character..."
& $ffmpeg -y -i sample.wav -af "acrusher=bits=12:mode=lin,volume=1.8,atanh,volume=0.555,lowpass=f=10000" sample_sp.wav *>&1 | Out-Null

# Step 3: Simple kick pattern
Write-Host "3. Creating kick pattern..."
$kickPattern = "0|0:2528|2528:5056|5056:7584|7584:10112|10112:12640|12640:15168|15168:17696|17696"
& $ffmpeg -y -f lavfi -i "anullsrc=duration=${DURATION}:sample_rate=48000:channel_layout=stereo" -i $KICK -filter_complex "[1:a]adelay=$kickPattern[k];[0:a][k]amix" drums.wav *>&1 | Out-Null

# Step 4: Mix
Write-Host "4. Mixing..."
& $ffmpeg -y -i sample_sp.wav -i drums.wav -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest" mix.wav *>&1 | Out-Null

# Step 5: Master
Write-Host "5. Mastering..."
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$final = "DILLA_BEAT_$timestamp.wav"
& $ffmpeg -y -i mix.wav -af "loudnorm=I=-16:TP=-1" $final *>&1 | Out-Null

# Cleanup
Remove-Item sample.wav,sample_sp.wav,drums.wav,mix.wav -ErrorAction SilentlyContinue

Write-Host "`n✅ DONE: $final"
Get-Item $final | Select-Object Name, Length
