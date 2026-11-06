# frozen_string_literal: true

# Nonce-based CSP with a report-only escape hatch.
# Set PUB4_CSP_ENFORCE=1 in production to enforce (default: report-only).
Rails.application.configure do
  embed_frame_hosts = %w[
    https://www.youtube-nocookie.com
    https://www.youtube.com
    https://w.soundcloud.com
    https://player.vimeo.com
    https://open.spotify.com
    https://whyp.it
  ]

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
    # The directives below name the hosts the repo shows a page reaching, not
    # every HTTPS host there is. Kept on purpose:
    #   style-src :unsafe_inline -- Turbo, the editor and the map write style
    #     attributes, which no nonce can cover; dropping it needs a live audit
    #     of the reports first.
    #   connect-src "wss:" -- Action Cable on the page's own host; older Safari
    #     does not count wss: as 'self'.
    #   default-src, font-src and img-src :https -- not narrowed here.
    # cdn.jsdelivr.net is post_gallery's lightgallery stylesheet.
    policy.style_src :self, :unsafe_inline, "https://cdn.jsdelivr.net"
    # tiles.openfreemap.org is the map style, tiles and glyphs (maps, nearby).
    policy.connect_src :self, "wss:", "https://tiles.openfreemap.org"
    # The players Shared::LinkEmbed::PROVIDERS builds, the radio tunnel's
    # www.youtube.com embed, and the MASTER face (_master_embed, MASTER_WEB_URL).
    policy.frame_src :self, *embed_frame_hosts, -> { Rails.application.config.x.master_web_url }
    # This app may be framed only by itself; MASTER has its own explicit embedding allowlist.
    policy.frame_ancestors :self
    policy.worker_src :self, :blob
    policy.manifest_src :self
    policy.form_action :self
    # Report-only with nowhere to report is neither blocking nor recording — the
    # same as no policy, with extra bytes on every response. Shared::CspReportsController
    # is the reader.
    policy.report_uri "/csp-reports"
    # Trusted Types, reported and never enforced: it names the innerHTML sinks
    # (link_preview, offline_page, optimistic_send) a later enforcement would
    # break. Left out of an enforced policy, where it would break them now.
    policy.require_trusted_types_for :script unless ENV["PUB4_CSP_ENFORCE"] == "1"
  end

  # Report-only stays the default: flipping enforcement on three live apps is an
  # operator call, and PUB4_CSP_ENFORCE=1 is how it is made.
  config.content_security_policy_report_only = ENV["PUB4_CSP_ENFORCE"] != "1"
end
