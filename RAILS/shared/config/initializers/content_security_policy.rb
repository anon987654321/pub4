# frozen_string_literal: true

# Airbnb/GitHub pattern: nonce-based CSP with report-only escape hatch.
# Set PUB4_CSP_ENFORCE=1 in production to enforce (default: report-only).
Rails.application.configure do
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.base_uri :self
    policy.font_src :self, :https, :data, "https://fonts.gstatic.com"
    policy.img_src :self, :https, :data, :blob
    policy.object_src :none
    policy.script_src :self, :https
    policy.style_src :self, :https, :unsafe_inline
    policy.connect_src :self, :https, "wss:"
    policy.frame_src :self, :https
    policy.worker_src :self, :blob
    policy.manifest_src :self
    policy.form_action :self
  end

  enforce = ENV["PUB4_CSP_ENFORCE"] == "1"
  config.content_security_policy_report_only = !enforce
end