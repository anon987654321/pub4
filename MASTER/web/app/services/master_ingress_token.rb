# frozen_string_literal: true

# Bearer token for webhook/cron ingress (POST /ingress/*).
class MasterIngressToken
  MIN_TOKEN_LENGTH = 16

  def self.read
    env = ENV["MASTER_INGRESS_TOKEN"].to_s
    env.length >= MIN_TOKEN_LENGTH ? env : ""
  end

  def self.valid?(candidate)
    token = read
    return false if token.empty? || candidate.to_s.empty?

    Rack::Utils.secure_compare(candidate.to_s, token)
  end
end
