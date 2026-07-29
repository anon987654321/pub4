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
# lsangeles.com stays separate from brgen.no, which is the point of the
# no-city-switcher design.
Rails.application.config.session_store :cookie_store,
  key: "_app_session",
  domain: :all,
  same_site: :lax,
  httponly: true
