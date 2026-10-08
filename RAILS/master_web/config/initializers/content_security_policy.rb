# frozen_string_literal: true

# Restart server after editing.
Rails.application.configure do
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  embed_hosts = ENV.fetch(
    "MASTER_FRAME_ANCESTORS",
    "https://brgen.no https://www.brgen.no https://amberapp.art",
  ).split

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, :data
    policy.img_src :self, :data
    policy.object_src :none
    policy.script_src :self, :blob
    # unsafe_inline stays: the FOUC guard is an inline style by design, and a nonce there moves
    # colours the operator owns.
    policy.style_src :self, :unsafe_inline
    policy.connect_src :self
    policy.media_src :self, :blob
    policy.frame_src :none
    policy.frame_ancestors :self, *embed_hosts
  end

  enforce = ENV["PUB4_CSP_ENFORCE"] == "1"
  config.content_security_policy_report_only = !enforce
end
