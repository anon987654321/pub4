# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "yaml"

module Master
  module CLI
    module WebSecret
      module_function

      def stable(config)
        return config["web_secret_key_base"] if config["web_secret_key_base"].to_s.length >= 64

        secret = SecureRandom.hex(64)
        config["web_secret_key_base"] = secret
        persist(secret)
        secret
      rescue StandardError
        SecureRandom.hex(64)
      end

      def persist(secret)
        config_path = File.join(Master::ROOT, ".master", "config.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        existing = YAML.safe_load_file(config_path, permitted_classes: [Symbol], aliases: true) rescue {}
        tmp_path = "#{config_path}.tmp"
        File.write(tmp_path, existing.merge("web_secret_key_base" => secret).to_yaml)
        File.rename(tmp_path, config_path)
      end
    end
  end
end
