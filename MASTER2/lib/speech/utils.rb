# frozen_string_literal: true

module MASTER
  module Speech
    # Utils - helper methods for TTS engines
    module Utils
      module_function

      # Find edge-tts CLI binary (installed by `pip install edge-tts` or `pipx install edge-tts`)
      # Returns the command string or nil.  No Python needed at call time.
      def find_edge_tts
        %w[edge-tts edge_tts].find { |cmd| system("#{cmd} --version > /dev/null 2>&1") }
      end

      # Check if Piper is installed
      def piper_installed?
        system("piper --version > /dev/null 2>&1") ||
          system("piper-tts --version > /dev/null 2>&1")
      end

      # Check if espeak-ng is installed (fallback local TTS)
      def espeak_installed?
        system("espeak-ng --version > /dev/null 2>&1")
      end

      # Check if Edge TTS CLI is available
      def edge_installed?
        !find_edge_tts.nil?
      end

      # Determine best available engine
      def best_engine
        return :piper    if piper_installed?
        return :edge     if edge_installed?
        return :espeak   if espeak_installed?
        return :replicate if ENV["REPLICATE_API_TOKEN"]

        nil
      end

      # Get list of available engines
      def available_engines
        ENGINES.select do |eng|
          case eng
          when :piper     then piper_installed?
          when :edge      then edge_installed?
          when :espeak    then espeak_installed?
          when :replicate then ENV.fetch("REPLICATE_API_TOKEN", nil)
          end
        end
      end

      # Get engine status string
      def engine_status
        engines = available_engines
        return "off" if engines.empty?

        engines.map(&:to_s).join("/")
      end
    end
  end
end
