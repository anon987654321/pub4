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
        File.unlink(audio_path) rescue nil if defined?(audio_path) && audio_path
      end
    end

    def sanitize_for_speech(text)
      plain = text.gsub(/\e\[[0-9;]*m/, "").strip
      plain.gsub(/```.*?```/m, "")[0..TTS_CHAR_LIMIT]
    end
  end
end
