<<<<<<< HEAD
#!/usr/bin/env ruby
# frozen_string_literal: true
# Consolidated TTS: Malaysian voice via Google Translate TTS + Sox effects
# Per master.json v43.0 - Zero sprawl, direct soundcard playback

require "net/http"
require "uri"
require "cgi"
require "fileutils"
require "json"

# Load master.json configuration
MASTER = JSON.parse(File.read("G:/pub/master.json"), symbolize_names: true)
VOICE = MASTER[:voice]
PATHS = MASTER[:paths]

# Constants from master.json
CACHE_DIR = "#{PATHS[:multimedia]}/tts/cache"
SOX = "#{PATHS[:dilla]}/effects/sox/sox.exe"

FileUtils.mkdir_p(CACHE_DIR)

def fetch_tts(text, lang: VOICE[:lang], tld: VOICE[:tld])
  hash = "#{text}#{lang}#{tld}".hash.abs.to_s
  mp3 = "#{CACHE_DIR}/#{hash}.mp3"
  return mp3 if File.exist?(mp3)

  url = "https://translate.google.com/translate_tts?" \
        "ie=UTF-8&client=tw-ob&tl=#{lang}&ttsspeed=0.85&tld=#{tld}&q=#{CGI.escape(text)}"

  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    req["Referer"] = "https://translate.google.com/"

    res = http.request(req)
    if res.code == "200" && res.body.size > 1000
      File.binwrite(mp3, res.body)
      mp3
    else
      warn "TTS API error: #{res.code}"
      nil
    end
  end
rescue => e
  warn "Network error: #{e.message}"
  nil
end

def apply_bomoh_effects(mp3)
  hash = File.basename(mp3, ".mp3")
  wav = "#{CACHE_DIR}/#{hash}_bomoh.wav"
  return wav if File.exist?(wav)

  # Bomoh effects: -12.5 semitones (deep), bass +8, reverb 20
  cmd = %("#{SOX}" "#{mp3}" "#{wav}" pitch -12.5 bass +8 treble -2 reverb 20 compand 0.3,1 6:-70,-60,-20 -5 -90 0.2 norm -1)
  system(cmd) ? wav : mp3
end

def play(file)
  return unless File.exist?(file)

  if file.end_with?(".wav")
    # WAV: Direct soundcard playback via Sox waveaudio
    system(%("#{SOX}" "#{file}" -t waveaudio -d 2>/dev/null))
  else
    # MP3: Use Windows default player (Sox lacks libmad for MP3)
    system(%(start /min "" "#{file.gsub('/', '\\\\')}"))
    sleep((File.size(file) / 10000.0).ceil)
  end
end

def speak(text, effects: true)
  mp3 = fetch_tts(text)
  return false unless mp3

  audio = effects ? apply_bomoh_effects(mp3) : mp3
  play(audio)
  true
end

# CLI
if __FILE__ == $0
  text = ARGV.join(" ")
  speak(text) unless text.empty?
end
=======
#!/usr/bin/env ruby
# frozen_string_literal: true
# Consolidated TTS: Malaysian voice via Google Translate TTS + Sox effects
# Per master.json v43.0 - Zero sprawl, direct soundcard playback

require "net/http"
require "uri"
require "cgi"
require "fileutils"
require "json"

# Load master.json configuration
MASTER = JSON.parse(File.read("G:/pub/master.json"), symbolize_names: true)
VOICE = MASTER[:voice]
PATHS = MASTER[:paths]

# Constants from master.json
CACHE_DIR = "#{PATHS[:multimedia]}/tts/cache"
SOX = "#{PATHS[:dilla]}/effects/sox/sox.exe"

FileUtils.mkdir_p(CACHE_DIR)

def fetch_tts(text, lang: VOICE[:lang], tld: VOICE[:tld])
  hash = "#{text}#{lang}#{tld}".hash.abs.to_s
  mp3 = "#{CACHE_DIR}/#{hash}.mp3"
  return mp3 if File.exist?(mp3)

  url = "https://translate.google.com/translate_tts?" \
        "ie=UTF-8&client=tw-ob&tl=#{lang}&ttsspeed=0.85&tld=#{tld}&q=#{CGI.escape(text)}"

  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    req["Referer"] = "https://translate.google.com/"

    res = http.request(req)
    if res.code == "200" && res.body.size > 1000
      File.binwrite(mp3, res.body)
      mp3
    else
      warn "TTS API error: #{res.code}"
      nil
    end
  end
rescue => e
  warn "Network error: #{e.message}"
  nil
end

def apply_bomoh_effects(mp3)
  hash = File.basename(mp3, ".mp3")
  wav = "#{CACHE_DIR}/#{hash}_bomoh.wav"
  return wav if File.exist?(wav)

  # Bomoh effects: -12.5 semitones (deep), bass +8, reverb 20
  cmd = %("#{SOX}" "#{mp3}" "#{wav}" pitch -12.5 bass +8 treble -2 reverb 20 compand 0.3,1 6:-70,-60,-20 -5 -90 0.2 norm -1)
  system(cmd) ? wav : mp3
end

def play(file)
  return unless File.exist?(file)

  if file.end_with?(".wav")
    # WAV: Direct soundcard playback via Sox waveaudio
    system(%("#{SOX}" "#{file}" -t waveaudio -d 2>/dev/null))
  else
    # MP3: Use Windows default player (Sox lacks libmad for MP3)
    system(%(start /min "" "#{file.gsub('/', '\\\\')}"))
    sleep((File.size(file) / 10000.0).ceil)
  end
end

def speak(text, effects: true)
  mp3 = fetch_tts(text)
  return false unless mp3

  audio = effects ? apply_bomoh_effects(mp3) : mp3
  play(audio)
  true
end

# CLI
if __FILE__ == $0
  text = ARGV.join(" ")
  speak(text) unless text.empty?
end
>>>>>>> origin/audio-layer-v7.2
