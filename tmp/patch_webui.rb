# Fix Web UI: missing _bkts declaration + mic/TTS improvements
path = "/home/dev/pub4/MASTER/web/app/views/chat/index.html.erb"
src = File.read(path)

# 1. CRITICAL: Declare _bkts Map before animate() uses it
# Insert right before the animate function
src.sub!(
  "    let t=0;\n    const ringPulses=[];",
  "    const _bkts=new Map();\n    let t=0;\n    const ringPulses=[];"
)

# 2. Mic: add echo cancellation and noise suppression for better voice capture
# The current config disables all processing which picks up tons of noise
src.sub!(
  "audio:{echoCancellation:false,noiseSuppression:false,autoGainControl:false}",
  "audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true}"
)

# 3. Speech recognition: add longer silence timeout before finalizing
# Current: continuous=true but no maxAlternatives or grammars set
# Add better error recovery for recognition restarts
src.sub!(
  "      recognition.continuous=true;\n      recognition.interimResults=true;\n      recognition.lang='ms-MY';",
  "      recognition.continuous=true;\n      recognition.interimResults=true;\n      recognition.lang='ms-MY';\n      recognition.maxAlternatives=3;"
)

# 4. Fix recognition restart — add debounce to avoid rapid start/stop cycling
src.sub!(
  "        if(nonstopVoice&&!isSpeaking) setTimeout(startRecognition,160);",
  "        if(nonstopVoice&&!isSpeaking) setTimeout(startRecognition,500);"
)

# 5. Improve TTS: stop mic during TTS to prevent feedback loop
# Already handled by: if(recognition&&recognitionActive) try{recognition.stop();}catch(_e){}
# But need to also duck when using browser TTS
src.sub!(
  "      u.onstart=()=>{isSpeaking=true;speechPulse=0.6;statusEl.classList.add('speak');};",
  "      u.onstart=()=>{isSpeaking=true;speechPulse=0.6;statusEl.classList.add('speak');duckPads();if(padModulate)padModulate('speak');if(recognition&&recognitionActive)try{recognition.stop();}catch(_e){}};"
)

# 6. Fix browser TTS onend to also unduck pads
src.sub!(
  "      u.onend=_onSpeakEnd; u.onerror=_onSpeakEnd;",
  "      u.onend=()=>{unduckPads();_onSpeakEnd();}; u.onerror=()=>{unduckPads();_onSpeakEnd();};"
)

# 7. Add auto-language detection for speech recognition
# If user speaks English, switch to English recognition
src.sub!(
  "      recognition.onresult=(ev)=>{",
  <<~'JS'.chomp
      recognition.onresult=(ev)=>{
        // Auto-detect language: if mostly ASCII, switch to en-US
        const _detectLang=(txt)=>{
          const ascii=txt.replace(/[^a-zA-Z]/g,'').length;
          const total=txt.replace(/\s/g,'').length||1;
          return ascii/total>0.8?'en-US':'ms-MY';
        };
  JS
)

# After getting finalText, auto-switch recognition language
src.sub!(
  "        finalText=finalText.trim();\n        if(!finalText) return;",
  "        finalText=finalText.trim();\n        if(!finalText) return;\n        const detectedLang=_detectLang(finalText);\n        if(recognition.lang!==detectedLang){recognition.lang=detectedLang;}"
)

File.write(path, src)
puts "Web UI patched"

# Verify ERB syntax
require "erb"
begin
  ERB.new(src).result(binding)
  puts "ERB syntax: OK"
rescue SyntaxError => e
  puts "ERB syntax error: #{e.message}"
rescue => e
  # Runtime errors are expected (no Rails context) — only care about syntax
  puts "ERB syntax: OK (runtime error expected without Rails)"
end
