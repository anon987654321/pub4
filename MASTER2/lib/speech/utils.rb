# frozen_string_literal: true

module MASTER
  module Speech
    # Utils - helper methods for TTS engines
    module Utils
      module_function

      # Find Python executable
      def find_python
        %w[py python3 python].find { |p| system("#{p} --version > /dev/null 2>&1") } || "python"
      end

      # Check if Piper is installed
      def piper_installed?
        system("piper --version > /dev/null 2>&1") ||
          system("py -m piper --version > nul 2>&1")
      end

      # Check if Edge TTS is installed
      def edge_installed?
        python = find_python
        return false unless python
        system("#{python} -c \"import edge_tts\" 2>/dev/null")
      end

      # Install Edge TTS
      def install_edge!
        python = find_python
        system("#{python} -m pip install edge-tts --quiet") if python
      end

      # Determine best available engine
      def best_engine
        return :piper if piper_installed?
        return :edge if edge_installed?
        return :replicate if ENV["REPLICATE_API_TOKEN"]
        nil
      end

      # Get list of available engines
      def available_engines
        ENGINES.select do |e|
          case e
          when :piper then piper_installed?
          when :edge then edge_installed?
          when :replicate then ENV["REPLICATE_API_TOKEN"]
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
