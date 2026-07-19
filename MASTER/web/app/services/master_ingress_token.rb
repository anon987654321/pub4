# frozen_string_literal: true

# Bearer token for webhook/cron ingress (POST /ingress/*).
# Prefer MASTER_INGRESS_TOKEN; falls back to MASTER_BRIDGE_TOKEN for single-token ops.
class MasterIngressToken
  MIN_TOKEN_LENGTH = 16

  def self.read
    env = ENV["MASTER_INGRESS_TOKEN"].to_s
    return env if env.length >= MIN_TOKEN_LENGTH

    bridge = MasterBridgeToken.read
    return bridge if bridge.length >= MIN_TOKEN_LENGTH

    ""
  end

  def self.valid?(candidate)
    token = read
    return false if token.empty? || candidate.to_s.empty?

    Rack::Utils.secure_compare(candidate.to_s, token)
  end
end
