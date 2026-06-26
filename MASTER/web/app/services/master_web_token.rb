# frozen_string_literal: true

require "yaml"

class MasterWebToken
  MIN_LENGTH = 43

  def self.config_path
    ENV.fetch(
      "MASTER_AUTH_CONFIG",
      Rails.root.join("..", ".master", "config.yml").to_s
    )
  end

  def self.read
    cfg = YAML.safe_load_file(config_path, permitted_classes: [Symbol], aliases: true) rescue {}
    candidate = cfg.is_a?(Hash) ? cfg["web_token"].to_s : ""
    candidate.length >= MIN_LENGTH ? candidate : ""
  end
end