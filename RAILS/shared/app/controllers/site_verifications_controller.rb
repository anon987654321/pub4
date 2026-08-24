# frozen_string_literal: true

# Proof of site ownership for networks that ask for it.
#
# Written because Tradedoubler denied brgen.no on 2026-08-01 for "need of
# proof/confirmation of site ownership" and this app had no way to offer any:
# no .well-known, no verification file, no meta tag.
#
# A static file in public/ cannot do this job here. brgen serves roughly twenty
# city domains from one app, and every network issues a token per domain, so a
# file at public/tdverify.html would answer with the same token on oshlo.no as
# on brgen.no -- which is worse than no proof, because it is proof of the wrong
# thing. Brgen::DomainRegistry already resolves host to city, so the token is
# looked up per host.
#
# Tokens come from the environment, never the repo. A verification token is a
# shared secret with the network; committing one lets anyone who can read this
# tree claim the domain.
#
#   SITE_VERIFICATION="brgen.no:tradedoubler=abc123,google=xyz789;oshlo.no:tradedoubler=def456"
#
# Networks ask for the token in one of three shapes and this serves all three,
# because which one is wanted is their choice and not ours:
#
#   GET /.well-known/<network>-site-verification   -> the bare token
#   GET /<network><token>.html                     -> an HTML page containing it
#   <meta name="<network>-site-verification" ...>  -> rendered into the layout
class SiteVerificationsController < ApplicationController
  # Ownership proof has to be reachable by a crawler with no session, and it
  # predates any consent the app asks for.
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, raise: false
  allow_browser versions: :modern, block: -> { } if respond_to?(:allow_browser)

  NETWORK = /\A[a-z0-9_-]{2,32}\z/
  TOKEN   = /\A[A-Za-z0-9_.:-]{4,128}\z/

  # The bare token, no markup. Most networks fetch this and compare bytes, so a
  # layout or a trailing newline can fail the check.
  def well_known
    token = SiteVerification.token_for(request.host, params[:network])
    return head(:not_found) unless token

    render plain: token, content_type: "text/plain"
  end

  # The other convention: <network><token>.html at the document root, which is
  # what Google Search Console and several affiliate networks still use.
  def file
    token = SiteVerification.token_for(request.host, params[:network])
    return head(:not_found) unless token && params[:token] == token

    render plain: "#{params[:network]}-site-verification: #{token}",
           content_type: "text/html"
  end
end
