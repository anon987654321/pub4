<<<<<<< HEAD
#!/usr/bin/env ruby
# Pure Ruby Google Translate TTS via HTTP API
# No Python, no SAPI, no espeak - Direct HTTP calls only
# Per master.json v337.3.0 - Ruby only, quality voices

require 'net/http'
require 'uri'
require 'cgi'
require 'fileutils'

module GoogleTTS
  CACHE_DIR = "G:/pub/multimedia/tts/cache"
  SOX_PATH = "G:/pub/multimedia/dilla/effects/sox/sox.exe"

  def self.setup
    FileUtils.mkdir_p(CACHE_DIR)
  end

  # Generate speech via Google Translate TTS API
  def self.generate_mp3(text, lang: 'en', tld: 'co.in')
    setup

    text_hash = "#{text}#{lang}#{tld}".hash.abs.to_s
    mp3_file = "#{CACHE_DIR}/gtts_#{text_hash}.mp3"

    return mp3_file if File.exist?(mp3_file)

    # Google Translate TTS API endpoint
    # tld: co.in = Indian English (deep, clear accent)
    url = "https://translate.google.com/translate_tts?" +
          "ie=UTF-8&client=tw-ob&tl=#{lang}&ttsspeed=0.85&tld=#{tld}&q=#{CGI.escape(text)}"

    uri = URI(url)

    begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        request['Referer'] = 'https://translate.google.com/'

        response = http.request(request)

        puts "🌐 Google TTS response: #{response.code}"

        if response.code == '200' && response.body.size > 1000
          File.open(mp3_file, 'wb') { |f| f.write(response.body) }
          puts "✓ Audio saved: #{File.size(mp3_file)} bytes"
          return mp3_file
        else
          warn "❌ Google TTS API error: #{response.code} (#{response.body.size} bytes)"
          return nil
        end
      end
    rescue => e
      warn "❌ Network error: #{e.message}"
      warn e.backtrace.first(3).join("\n")
      return nil
    end
  end

  # Convert Cygwin/Unix path to Windows path for Sox
  def self.to_windows_path(unix_path)
    unix_path.gsub('/home/aiyoo', 'C:/cygwin64/home/aiyoo')
             .gsub('/cygdrive/c', 'C:')
             .gsub('/cygdrive/g', 'G:')
  end

  # Apply Sox effects for Bomoh voice: deep pitch, bass, reverb
  def self.apply_effects(input_mp3, pitch_adjust: -150)
    return input_mp3 unless File.exist?(SOX_PATH)

    text_hash = File.basename(input_mp3, '.mp3')
    output_wav = "#{CACHE_DIR}/#{text_hash}_bomoh.wav"

    return output_wav if File.exist?(output_wav)

    # Convert paths to Windows format for Sox
    win_input = to_windows_path(input_mp3)
    win_output = to_windows_path(output_wav)

    # Bomoh effects: pitch down, bass boost, reverb, compression
    pitch_semitones = (pitch_adjust / 12.0).round(1)
    sox_cmd = "\"#{SOX_PATH}\" \"#{win_input}\" \"#{win_output}\" " +
              "pitch #{pitch_semitones} bass +8 treble -2 " +
              "reverb 20 compand 0.3,1 6:-70,-60,-20 -5 -90 0.2 norm -1"

    if system(sox_cmd)
      return output_wav
    else
      warn "⚠️  Sox processing failed, using raw audio"
      return input_mp3
    end
  end

  # Play audio file
  def self.play(audio_file)
    return unless File.exist?(audio_file)

    # Convert to Windows path
    win_path = to_windows_path(audio_file)

    # Use Windows default player via full path
    cmd = "C:/Windows/System32/cmd.exe /c start /min \"\" \"#{win_path}\""
    system(cmd)

    # Wait for playback to complete (estimate: 1 second per 10KB)
    sleep_time = (File.size(audio_file) / 10000.0).ceil
    sleep(sleep_time)
  end

  # Main speak method
  def self.speak(text, lang: 'en', tld: 'co.in', pitch_adjust: -150)
    mp3 = generate_mp3(text, lang: lang, tld: tld)
    return false unless mp3

    # Apply Bomoh effects if requested
    audio = (pitch_adjust != 0) ? apply_effects(mp3, pitch_adjust: pitch_adjust) : mp3

    play(audio)
    true
  end
end

# CLI
if __FILE__ == $0
  text = ARGV.join(" ")

  unless text.empty?
    # Bomoh Hang Tuah: Indian English accent, deep pitch
    GoogleTTS.speak(text, lang: 'en', tld: 'co.in', pitch_adjust: -150)
  end
end
=======
#!/usr/bin/env ruby
# Pure Ruby Google Translate TTS via HTTP API
# No Python, no SAPI, no espeak - Direct HTTP calls only
# Per master.json v337.3.0 - Ruby only, quality voices

require 'net/http'
require 'uri'
require 'cgi'
require 'fileutils'

module GoogleTTS
  CACHE_DIR = "G:/pub/multimedia/tts/cache"
  SOX_PATH = "G:/pub/multimedia/dilla/effects/sox/sox.exe"

  def self.setup
    FileUtils.mkdir_p(CACHE_DIR)
  end

  # Generate speech via Google Translate TTS API
  def self.generate_mp3(text, lang: 'en', tld: 'co.in')
    setup

    text_hash = "#{text}#{lang}#{tld}".hash.abs.to_s
    mp3_file = "#{CACHE_DIR}/gtts_#{text_hash}.mp3"

    return mp3_file if File.exist?(mp3_file)

    # Google Translate TTS API endpoint
    # tld: co.in = Indian English (deep, clear accent)
    url = "https://translate.google.com/translate_tts?" +
          "ie=UTF-8&client=tw-ob&tl=#{lang}&ttsspeed=0.85&tld=#{tld}&q=#{CGI.escape(text)}"

    uri = URI(url)

    begin
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        request['Referer'] = 'https://translate.google.com/'

        response = http.request(request)

        puts "🌐 Google TTS response: #{response.code}"

        if response.code == '200' && response.body.size > 1000
          File.open(mp3_file, 'wb') { |f| f.write(response.body) }
          puts "✓ Audio saved: #{File.size(mp3_file)} bytes"
          return mp3_file
        else
          warn "❌ Google TTS API error: #{response.code} (#{response.body.size} bytes)"
          return nil
        end
      end
    rescue => e
      warn "❌ Network error: #{e.message}"
      warn e.backtrace.first(3).join("\n")
      return nil
    end
  end

  # Convert Cygwin/Unix path to Windows path for Sox
  def self.to_windows_path(unix_path)
    unix_path.gsub('/home/aiyoo', 'C:/cygwin64/home/aiyoo')
             .gsub('/cygdrive/c', 'C:')
             .gsub('/cygdrive/g', 'G:')
  end

  # Apply Sox effects for Bomoh voice: deep pitch, bass, reverb
  def self.apply_effects(input_mp3, pitch_adjust: -150)
    return input_mp3 unless File.exist?(SOX_PATH)

    text_hash = File.basename(input_mp3, '.mp3')
    output_wav = "#{CACHE_DIR}/#{text_hash}_bomoh.wav"

    return output_wav if File.exist?(output_wav)

    # Convert paths to Windows format for Sox
    win_input = to_windows_path(input_mp3)
    win_output = to_windows_path(output_wav)

    # Bomoh effects: pitch down, bass boost, reverb, compression
    pitch_semitones = (pitch_adjust / 12.0).round(1)
    sox_cmd = "\"#{SOX_PATH}\" \"#{win_input}\" \"#{win_output}\" " +
              "pitch #{pitch_semitones} bass +8 treble -2 " +
              "reverb 20 compand 0.3,1 6:-70,-60,-20 -5 -90 0.2 norm -1"

    if system(sox_cmd)
      return output_wav
    else
      warn "⚠️  Sox processing failed, using raw audio"
      return input_mp3
    end
  end

  # Play audio file
  def self.play(audio_file)
    return unless File.exist?(audio_file)

    # Convert to Windows path
    win_path = to_windows_path(audio_file)

    # Use Windows default player via full path
    cmd = "C:/Windows/System32/cmd.exe /c start /min \"\" \"#{win_path}\""
    system(cmd)

    # Wait for playback to complete (estimate: 1 second per 10KB)
    sleep_time = (File.size(audio_file) / 10000.0).ceil
    sleep(sleep_time)
  end

  # Main speak method
  def self.speak(text, lang: 'en', tld: 'co.in', pitch_adjust: -150)
    mp3 = generate_mp3(text, lang: lang, tld: tld)
    return false unless mp3

    # Apply Bomoh effects if requested
    audio = (pitch_adjust != 0) ? apply_effects(mp3, pitch_adjust: pitch_adjust) : mp3

    play(audio)
    true
  end
end

# CLI
if __FILE__ == $0
  text = ARGV.join(" ")

  unless text.empty?
    # Bomoh Hang Tuah: Indian English accent, deep pitch
    GoogleTTS.speak(text, lang: 'en', tld: 'co.in', pitch_adjust: -150)
  end
end
>>>>>>> origin/audio-layer-v7.2
