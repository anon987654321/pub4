# MASTER Snapshot — lib/master/cli/
Generated: 2026-05-04T10:21:42Z

## lib/master/cli/signals.rb
```ruby
# frozen_string_literal: true

module Master
  class CLI
    private

    def setup_signals
      trap("USR1") { on_usr1 }
      trap("INT")  { on_int }
    end

    def on_usr1
      Zeitwerk::Loader.for_gem.reload
      puts "\n#{@renderer.render("reloaded", mode: :success)}"
    rescue StandardError => e
      puts "\n#{@renderer.render("reload failed: #{e.message}", mode: :error)}"
    end

    def on_int
      if Time.now - @interrupt_at < 1
        @scan_thread&.kill
        @session.save!
        exit(0)
      else
        @interrupt_at = Time.now
        puts "\n#{@renderer.render("^C again to quit", mode: :warning)}"
      end
    end
  end
end

```

## lib/master/cli/tts.rb
```ruby
# frozen_string_literal: true

module Master
  class CLI
    TTS_CHAR_LIMIT = 400

    private

    def speak_async(text)
      Thread.new do
        plain = sanitize_for_speech(text)
        next if plain.empty?
        audio_path = Speech.synthesize(plain)
        next unless audio_path
        played = Speech.play(audio_path)
        @bus&.publish("tts:warn", message: "no audio output found") unless played
      rescue StandardError => e
        @bus&.publish("tts:error", message: e.message)
      ensure
        begin; File.unlink(audio_path); rescue StandardError => _e; nil; end if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain.gsub(/```.*?```/m, "")[0..TTS_CHAR_LIMIT]
    end
  end
end

```
