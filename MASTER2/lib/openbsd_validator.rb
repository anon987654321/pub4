# frozen_string_literal: true

module MASTER
  # Validates OpenBSD config files against known required patterns and anti-patterns.
  module OpenBSDValidator
    CONFIGS = {
      "pf.conf"         => { required: ["set skip on lo"], warn: [["pass all", "Overly permissive rule"]] },
      "nsd.conf"        => { required: ["server:", "zone:"], warn: [["rrl-size", "Missing RRL — DDoS risk", :absent], ["hide-version", "Consider hide-version: yes", :absent]] },
      "httpd.conf"      => { required: ["server"], warn: [] },
      "smtpd.conf"      => { required: ["listen on", "action", "match"], warn: [["match from any", "Open relay risk"]] },
      "relayd.conf"     => { required: ["relay"], warn: [] },
      "acme-client.conf"=> { required: ["authority", "domain"], warn: [] },
      "doas.conf"       => { required: ["permit"], warn: [["nopass", "Allows passwordless escalation"]] },
      "sshd_config"     => { required: [], warn: [["PermitRootLogin yes", "Security risk"], ["PasswordAuthentication yes", "Consider key-only auth"]] },
      "ntpd.conf"       => { required: ["server"], warn: [] },
      "unbound.conf"    => { required: ["server:"], warn: [] },
    }.freeze

    module_function

    def validate(path)
      filename = File.basename(path)
      config = CONFIGS[filename]
      return [] unless config

      content = File.read(path)
      violations = []

      config[:required].each do |pattern|
        unless content.include?(pattern)
          violations << { severity: :high, message: "Missing required: #{pattern}", file: path }
        end
      end

      config[:warn].each do |pattern, message, mode|
        if mode == :absent
          violations << { severity: :medium, message: message, file: path } unless content.include?(pattern)
        else
          violations << { severity: :medium, message: message, file: path } if content.include?(pattern)
        end
      end

      violations
    rescue Errno::ENOENT, Errno::EACCES
      []
    end

    def validate_dir(dir = "/etc")
      CONFIGS.keys.flat_map { |name| validate(File.join(dir, name)) }
    end
  end
end
