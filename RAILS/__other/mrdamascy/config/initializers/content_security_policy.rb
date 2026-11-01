# frozen_string_literal: true

# App-owned, nonce-bearing CSP (the fleet's split contract: the edge owns the
# transport headers, Rails owns the nonce policy — an edge-level CSP would
# overwrite this one). Report-only until MRDAMASCY_CSP_ENFORCE=1 so the fresh
# app can prove its own markup clean before enforcement flips on.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src    :self
    policy.font_src       :self
    policy.img_src        :self, :data
    policy.object_src     :none
    policy.script_src     :self
    policy.style_src      :self
    policy.manifest_src   :self
    policy.frame_ancestors :self
    policy.form_action    :self
    policy.base_uri       :self
  end

  # Session nonces for the importmap's inline bootstrap script.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_report_only = ENV["MRDAMASCY_CSP_ENFORCE"] != "1"
end
