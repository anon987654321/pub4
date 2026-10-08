# frozen_string_literal: true

# Nonce-based CSP with a report-only escape hatch.
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
    # Not :https. It admits every HTTPS host there is, which makes the nonce
    # generator above decorative: the point of a nonce is that an injected
    # <script> without one cannot run, and :https let all of them run.
    #
    # link.tradedoubler.com is named because shared/_link_converter falls back to
    # the remote copy when no sync job has written a first-party one, and that is
    # the affiliate attribution path.
    policy.script_src :self, "https://link.tradedoubler.com"
    policy.style_src :self, :https, :unsafe_inline
    policy.connect_src :self, :https, "wss:"
    policy.frame_src :self, :https
    policy.worker_src :self, :blob
    policy.manifest_src :self
    policy.form_action :self
    # Report-only with nowhere to report is neither blocking nor recording — the
    # same as no policy, with extra bytes on every response. Shared::CspReportsController
    # is the reader.
    policy.report_uri "/csp-reports"
  end

  # Report-only stays the default: flipping enforcement on three live apps is an
  # operator call, and PUB4_CSP_ENFORCE=1 is how it is made.
  config.content_security_policy_report_only = ENV["PUB4_CSP_ENFORCE"] != "1"
end
