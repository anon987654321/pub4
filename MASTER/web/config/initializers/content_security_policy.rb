# frozen_string_literal: true

# Restart server after editing.
Rails.application.configure do
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  embed_hosts = ENV.fetch(
    "MASTER_FRAME_ANCESTORS",
    "https://brgen.no https://www.brgen.no https://amber.brgen.no",
  ).split

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, :data
    policy.img_src :self, :data, "https://i.ytimg.com"
    policy.object_src :none
    policy.script_src :self, :blob, "https://www.youtube.com", "https://s.ytimg.com"
    policy.style_src :self, :unsafe_inline
    policy.connect_src :self, "https://www.youtube.com", "https://youtu.be"
    policy.media_src :self, :blob
    policy.frame_src "https://www.youtube.com", "https://www.youtube-nocookie.com"
    policy.frame_ancestors :self, *embed_hosts
  end

  enforce = ENV["PUB4_CSP_ENFORCE"] == "1"
  config.content_security_policy_report_only = !enforce
end
