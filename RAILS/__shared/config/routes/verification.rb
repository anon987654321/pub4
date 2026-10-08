# frozen_string_literal: true

# Site-ownership proof, for every app in the fleet.
#
# instance_eval'd into each host's routes.rb like auth.rb and social.rb, so
# brgen, amber and bsdports all answer the same URLs without three copies.
#
# Routed rather than a file in public/, and that is the whole reason this is
# code at all. brgen serves ~20 city domains from one app and every network
# issues a token per domain, so a static public/tdverify.html would answer with
# brgen.no's token on oshlo.no -- worse than no proof, because it is proof of
# the wrong thing. SiteVerification resolves the token per request host.
#
# Written after Tradedoubler denied brgen.no on 2026-08-01: "Need of
# proof/confirmation of site ownership". The app had no surface to offer any.
get ".well-known/:network-site-verification" => "site_verifications#well_known",
    as: :site_verification,
    constraints: { network: /[a-z0-9_-]{2,32}/ }

# The other convention, still used by Google Search Console and several
# affiliate networks: <network><token>.html at the document root. Constrained
# tightly so it cannot shadow real routes -- it only matches when the path ends
# in .html, which nothing else in these apps serves.
get ":network:token.html" => "site_verifications#file",
    as: :site_verification_file,
    constraints: { network: /[a-z0-9_-]{2,32}/, token: /[A-Za-z0-9_.:-]{4,128}/ }
