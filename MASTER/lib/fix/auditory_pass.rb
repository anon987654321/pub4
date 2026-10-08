# frozen_string_literal: true

module Master
  module Fix
    # Measures existing audio and writes nothing. ffmpeg, when it is present,
    # decodes to null through MixMetrics. A missing instrument is inconclusive.
    # A take is never re-rendered.
    class AuditoryPass
      AUDIO_EXT = %w[.wav .mp3 .flac .aiff .aif .ogg .m4a].freeze
      MAX_FILES = 4

      def initialize(root:, bus: nil)
        @root = File.expand_path(root.to_s)
        @bus = bus
      end

      def applicable?(target)
        audio_paths(target).any?
      end

      def run(target:, files: nil)
        paths = audio_paths(target).first(MAX_FILES)
        return Result.ok(state: :no_audio, findings: [], note: nil) if paths.empty?
        return inconclusive("ffmpeg is not installed") unless tool?("ffmpeg")

        readings = paths.map { |path| Master::Voice::MixMetrics.from_path(path) }
        note = note_for(readings)
        @bus&.publish("fix_loop:auditory", files: readings.size, note:)
        Result.ok(state: :measured, findings: [], readings:, note:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.auditory_pass", event_bus: @bus)
        inconclusive("#{e.class}: #{e.message}")
      end

      private

      def inconclusive(reason)
        @bus&.publish("fix_loop:auditory", state: :inconclusive, reason:)
        Result.ok(state: :inconclusive, findings: [], note: "Rendered audio inconclusive: #{reason}")
      end

      def tool?(name)
        Master::Voice::MixMetrics.tool?(name)
      end

      def note_for(readings)
        lines = readings.map { |row| reading_line(row) }
        ["Rendered audio measured with ffmpeg to null. Do not re-render or overwrite a take.", *lines].join("\n")
      end

      def reading_line(row)
        name = File.basename(row[:path].to_s)
        return "#{name}: #{row[:error]}" if row[:error]

        "#{name}: peak=#{row[:peak_db]} dBFS rms=#{row[:rms_db]}"
      end

      def audio_paths(target)
        return [] if target.nil? || !File.exist?(target)
        return [target] if audio_file?(target)
        return [] unless File.directory?(target)

        Dir.glob(File.join(target, "**", "*")).select { |path| audio_file?(path) }.sort
      end

      def audio_file?(path)
        File.file?(path) && !File.symlink?(path) && AUDIO_EXT.include?(File.extname(path).downcase)
      end
    end
  end
end
