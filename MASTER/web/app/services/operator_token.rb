# frozen_string_literal: true

require "yaml"

# The operator token for the web face: read from .master/config.yml (seeded by
# AuthTier) and matched against the bearer header, X-Token or the
# master_session cookie. IngressToken is the other one, an env bearer
# for webhook and cron POSTs to /ingress.
class OperatorToken
  MIN_LENGTH = 43

  def self.config_path
    ENV.fetch(
      "MASTER_AUTH_CONFIG",
      Rails.root.join("..", ".master", "config.yml").to_s,
    )
  end

  def self.read
    cfg = if File.exist?(config_path)
      YAML.safe_load_file(config_path, permitted_classes: [Symbol], aliases: true)
    else
      {}
    end

    candidate = if cfg.is_a?(Hash)
      cfg["web_token"] || cfg[:web_token]
    end

    token = candidate.to_s.strip
    token.length >= MIN_LENGTH ? token : ""
  rescue StandardError
    ""
  end
end
