# frozen_string_literal: true

require "json"
require "optparse"
require_relative "../lib/voice/transcendent"
require_relative "../lib/voice/quality"

module Master
  module Voice
    module QualityHarness
      PROBES = [
        "I am here with you. We can take this one step at a time.",
        "That failed, but the important part is that we know why.",
        "I found it. The change is small, and nothing else needs to move.",
        "Give me a moment. I am checking the whole tree before I touch it.",
        "Yes. That is a good direction. Let us keep the useful parts and remove the noise.",
        "Everything is ready. The system is quiet now.",
      ].freeze

      LIMITS = {
        min_sample_rate: 16_000,
        max_duration_s: 180.0,
        max_probe_duration_s: 30.0,
      }.freeze

      module_function

      def run(synthesize: false)
        report = {
          personality: Transcendent.load_config["personality"].to_s,
          probes: [],
          passed: true,
          synthesized: synthesize,
        }

        PROBES.each do |text|
          row = { text:, quality: nil }
          if synthesize
            path = Transcendent.synthesize(text, style: :auto)
            row[:quality] = Quality.inspect(path)
            File.delete(path) if path && File.file?(path)
            row[:pass] = quality_ok?(row[:quality])
          else
            row[:pass] = true
          end
          report[:probes] << row
          report[:passed] &&= row[:pass]
        rescue StandardError => e
          row[:pass] = false
          row[:error] = "#{e.class}: #{e.message}"
          report[:probes] << row
          report[:passed] = false
        end

        report
      end

      def quality_ok?(quality)
        return false unless quality.is_a?(Hash) && quality[:ok]
        return false if quality[:clipping]
        return false if quality[:sample_rate].to_i < LIMITS[:min_sample_rate]
        return false if quality[:duration_s].to_f > LIMITS[:max_duration_s]
        true
      end

      def print(report)
        puts "voice_quality: #{report[:personality]} / #{report[:synthesized] ? "synthesized" : "config-only"}"
        report[:probes].each_with_index do |row, index|
          if row[:quality]
            q = row[:quality]
            puts "voice_quality: probe=#{index + 1} pass=#{row[:pass]} duration=#{q[:duration_s]}s rate=#{q[:sample_rate]} clipping=#{q[:clipping]}"
          else
            puts "voice_quality: probe=#{index + 1} pass=#{row[:pass]}"
          end
        end
        puts "voice_quality: #{report[:passed] ? "clean" : "FAIL"}"
        report[:passed]
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  synthesize = ARGV.delete("--synthesize")
  ok = Master::Voice::QualityHarness.print(
    Master::Voice::QualityHarness.run(synthesize: !!synthesize),
  )
  exit(ok ? 0 : 1)
end
