# frozen_string_literal: true

module MASTER
  # PiperTTS: Local neural TTS using Piper - fast, free, no API needed
  # Supports voice manipulation: speed, pitch, emotion via noise_scale
  class PiperTTS
    VOICES_DIR = File.join(Paths.var, 'piper_voices')
    DEFAULT_VOICE = 'en_US-lessac-medium'

    # Voice presets - personality through parameters
    # length_scale: <1.0 = fast/high, >1.0 = slow/deep
    # noise_scale:  <0.3 = flat/robotic, >0.7 = unstable/emotional
    PRESETS = {
      normal:     { length_scale: 1.0,  noise_scale: 0.667 },
      chipmunk:   { length_scale: 0.6,  noise_scale: 0.667 },  # Fast, high pitched
      zombie:     { length_scale: 2.5,  noise_scale: 0.4 },    # Slow, deep, flat
      robot:      { length_scale: 1.0,  noise_scale: 0.1 },    # Monotone GPS voice
      manic:      { length_scale: 0.8,  noise_scale: 0.9 },    # Unstable, drunk
      calm:       { length_scale: 1.2,  noise_scale: 0.3 },    # Slow, steady, soothing
      urgent:     { length_scale: 0.7,  noise_scale: 0.5 },    # Fast, focused, news anchor
      whisper:    { length_scale: 1.3,  noise_scale: 0.2 },    # Soft, flat, ASMR
      excited:    { length_scale: 0.75, noise_scale: 0.8 },    # Fast, variable, hyped
      depressed:  { length_scale: 1.4,  noise_scale: 0.1 },    # Slow, flat, sad
      demon:      { length_scale: 3.0,  noise_scale: 0.3 },    # Very slow, deep
      caffeinated:{ length_scale: 0.5,  noise_scale: 0.7 }     # Hyperfast, jittery
    }.freeze

    # Text effects - manipulate input for glitch/stutter/robotic feel
    TEXT_EFFECTS = {
      stutter:    ->(t) { t.gsub(/\b(\w)/, '\1-\1-\1') },                    # H-H-Hello
      glitch:     ->(t) { t.chars.map { |c| rand < 0.1 ? "#{c}#{c}#{c}" : c }.join },
      spaces:     ->(t) { t.chars.join(' ') },                               # H e l l o
      slow_spell: ->(t) { t.gsub(/(\w)/, '\1... ') },                        # H... e... l...
      robotic:    ->(t) { t.upcase.gsub(/[.,!?]/, '. BEEP. ') },             # HELLO. BEEP.
      whisper:    ->(t) { t.downcase.gsub(/[!]/, '...') },                   # hello...
      dramatic:   ->(t) { t.gsub(/(\w+)/) { |w| "#{w}..." } },               # Hello... world...
      corrupt:    ->(t) { t.chars.map { |c| rand < 0.05 ? %w[# @ $ %].sample : c }.join }
    }.freeze

    attr_reader :voice, :preset

    def initialize(voice: DEFAULT_VOICE, preset: :normal)
      @voice = voice
      @preset = preset
      @params = PRESETS[preset] || PRESETS[:normal]
      @queue = Queue.new
      @playing = false
      @worker = nil
      ensure_voice_installed
    end

    def speak(text, preset: nil, effect: nil)
      return if text.nil? || text.strip.empty?

      @params = PRESETS[preset] if preset && PRESETS[preset]
      text = apply_effect(text, effect) if effect

      chunks = split_sentences(text)
      chunks.each { |c| @queue.push(c) }
      start_worker unless @worker&.alive?
    end

    def speak_sync(text, preset: nil, effect: nil)
      return nil if text.nil? || text.strip.empty?

      @params = PRESETS[preset] if preset && PRESETS[preset]
      text = apply_effect(text, effect) if effect
      generate_and_play(text)
    end

    # Generate audio file without playing - for web streaming
    def generate(text, output: nil, preset: nil, effect: nil)
      return nil if text.nil? || text.strip.empty?

      @params = PRESETS[preset] if preset && PRESETS[preset]
      text = apply_effect(text, effect) if effect
      output ||= temp_wav
      generate_audio(text, output)
      output
    end

    # Generate base64 audio for web embedding
    def generate_base64(text, preset: nil, effect: nil)
      file = generate(text, preset: preset, effect: effect)
      return nil unless file && File.exist?(file)

      require 'base64'
      data = Base64.strict_encode64(File.binread(file))
      File.delete(file) rescue nil
      "data:audio/wav;base64,#{data}"
    end

    # Apply text effect for glitch/stutter/robotic speech
    def apply_effect(text, effect)
      transform = TEXT_EFFECTS[effect.to_sym]
      transform ? transform.call(text) : text
    end

    def speaking?
      @playing || !@queue.empty?
    end

    def stop
      @queue.clear
      @playing = false
    end

    def set_preset(name)
      @preset = name
      @params = PRESETS[name] || PRESETS[:normal]
    end

    private

    def start_worker
      @worker = Thread.new do
        while (chunk = @queue.pop(true) rescue nil)
          generate_and_play(chunk)
        end
      end
    end

    def generate_and_play(text)
      @playing = true
      output = temp_wav
      
      if generate_audio(text, output)
        play_audio(output)
      end
      
      File.delete(output) rescue nil
      @playing = false
    end

    def generate_audio(text, output)
      model = voice_path
      return false unless File.exist?(model)

      cmd = build_command(text, model, output)
      system(cmd)
      File.exist?(output) && File.size(output) > 0
    end

    def build_command(text, model, output)
      escaped = text.gsub('"', '\\"').gsub('`', '\\`')
      length = @params[:length_scale]
      noise = @params[:noise_scale]

      case RUBY_PLATFORM
      when /openbsd|linux|darwin/
        "echo \"#{escaped}\" | piper --model #{model} --output_file #{output} --length_scale #{length} --noise_scale #{noise} 2>/dev/null"
      when /mingw|mswin/
        "echo #{escaped} | py -m piper --model #{model} --output #{output} --length_scale #{length} --noise_scale #{noise}"
      else
        "echo \"#{escaped}\" | piper --model #{model} --output_file #{output}"
      end
    end

    def play_audio(file)
      return unless File.exist?(file)

      case RUBY_PLATFORM
      when /openbsd/
        system("aucat -i #{file} 2>/dev/null")
      when /darwin/
        system("afplay #{file}")
      when /linux/
        system("aplay -q #{file} 2>/dev/null || paplay #{file} 2>/dev/null || mpv --no-video #{file} 2>/dev/null")
      when /mingw|mswin/
        system("powershell -c \"(New-Object Media.SoundPlayer '#{file}').PlaySync()\"")
      end
    end

    def split_sentences(text, max: 300)
      sentences = text.split(/(?<=[.!?])\s+/)
      chunks = []
      current = ""

      sentences.each do |s|
        if (current.length + s.length) > max
          chunks << current.strip unless current.empty?
          current = s
        else
          current = current.empty? ? s : "#{current} #{s}"
        end
      end
      chunks << current.strip unless current.empty?
      chunks
    end

    def voice_path
      File.join(VOICES_DIR, "#{@voice}.onnx")
    end

    def temp_wav
      File.join(Dir.tmpdir, "piper_#{SecureRandom.hex(4)}.wav")
    end

    def ensure_voice_installed
      FileUtils.mkdir_p(VOICES_DIR)
      return if File.exist?(voice_path)

      # Auto-download voice on first use
      Dmesg.log("piper0", message: "downloading #{@voice}...") rescue nil
      download_voice(@voice)
    end

    def download_voice(name)
      base = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium"
      
      %w[.onnx .onnx.json].each do |ext|
        url = "#{base}/en_US-lessac-medium#{ext}"
        out = File.join(VOICES_DIR, "#{name}#{ext}")
        
        case RUBY_PLATFORM
        when /openbsd/
          system("ftp -o #{out} #{url} 2>/dev/null")
        else
          system("curl -sL #{url} -o #{out}")
        end
      end
    end
  end
end
