# frozen_string_literal: true

# One identity across a city's verticals.
#
# Every vertical is a subdomain of the same apex -- markedsplass., dating.,
# tv., playlist., takeaway., maps., messenger. -- but the session cookie was
# host-only (no Domain attribute), so a browser never sent it across that
# boundary. A visitor who signed in on brgen.no arrived at markedsplass.brgen.no
# as a brand-new guest: different cart, different dating profile, different chat
# handle, and the sign-in they had just completed was invisible.
#
# domain: :all scopes the cookie to the request's registrable domain, so it
# spans one city's subdomains and still never reaches another city's apex --
# lsangeles.com stays separate from brgen.no, even when a reader follows the
# city network link between them.
#
# secure: is set in production only, and only there. TLS terminates at relayd,
# so Rails never installs ActionDispatch::SSL and force_ssl cannot add the
# flag for us (assume_ssl redirects but does not flag cookies). Without it the
# _app_session cookie would replay over plain HTTP. Development and test stay
# off it: the local fleet and system tests serve plain http://localhost, where
# a Secure cookie is dropped and every sign-in silently fails.
Rails.application.config.session_store :cookie_store,
  key: "_app_session",
  domain: :all,
  same_site: :lax,
  httponly: true,
  secure: Rails.env.production?
