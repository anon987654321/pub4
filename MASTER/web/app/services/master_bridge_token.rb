# frozen_string_literal: true

# Bearer token for OpenClaw (or other gateways) calling POST /bridge/turn.
# Prefer MASTER_BRIDGE_TOKEN in env; falls back to web_token for local dev only.
class MasterBridgeToken
  MIN_TOKEN_LENGTH = 16

  def self.read
    env = ENV["MASTER_BRIDGE_TOKEN"].to_s
    return env if env.length >= MIN_TOKEN_LENGTH

    web = MasterWebToken.read
    return web if web.length >= MIN_TOKEN_LENGTH

    ""
  end

  def self.valid?(candidate)
    token = read
    return false if token.empty? || candidate.to_s.empty?

    Rack::Utils.secure_compare(candidate.to_s, token)
  end
end