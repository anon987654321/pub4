# frozen_string_literal: true

module MASTER
  module Review
    # ToolScanner — scan tool source for threats at registration time
    # Pattern: MASTER3 Constitutional Tool Scanning (gistfile10 §5)
    module ToolScanner
      extend self

      THREAT_PATTERNS = [
        { name: :prompt_injection, pattern: /system\s*prompt|ignore.*instructions/i, severity: :critical },
        { name: :rce,              pattern: /\beval\s*\(|\bexec\s*\(|\bsystem\s*\(|`[^`]{1,200}`/i, severity: :critical },
        { name: :credential_theft, pattern: /ENV\[["']?(?:API_KEY|PASSWORD|SECRET|TOKEN)/i, severity: :high },
        { name: :network_exfil,    pattern: /Net::HTTP\.post|open-uri|Faraday\.post/i, severity: :medium },
        { name: :file_escape,      pattern: /\.\.\//,                                  severity: :high },
      ].freeze

      # Scan a string of source code for threats.
      # @param source [String] Ruby source code
      # @param name [String] name/label for logging
      # @return [Hash] { threats: [], safe: true/false }
      def scan(source, name: "unknown")
        threats = THREAT_PATTERNS.filter_map do |tp|
          next unless source.match?(tp[:pattern])
          { threat: tp[:name], severity: tp[:severity] }
        end

        if threats.any?
          Logging.dmesg_log("scan0", message: "name=#{name} threats=#{threats.map { |t| t[:threat] }.join(',')}")
        end

        { threats: threats, safe: threats.none? { |t| t[:severity] == :critical } }
      end
    end
  end
end
