# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "yaml"

module Master
  module CLI
    module WebSecret
      # Minimum accepted length (chars) for an existing key -- looser than
      # SECRET_BYTES since SecureRandom.hex(n) produces 2n hex chars, so a
      # freshly generated secret is 128 chars while 64 remains acceptable
      # for one supplied some other way.
      MIN_SECRET_LENGTH = 64
      SECRET_BYTES = 64

      module_function

      def stable(config)
        return config["web_secret_key_base"] if config["web_secret_key_base"].to_s.length >= MIN_SECRET_LENGTH

        secret = SecureRandom.hex(SECRET_BYTES)
        config["web_secret_key_base"] = secret
        persist(secret)
        secret
      rescue StandardError
        SecureRandom.hex(SECRET_BYTES)
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
