# frozen_string_literal: true

module Deploy
  # Canonical brgen.no vertical Hosts for live layout/flow probes.
  # Hosts must match DomainRegistry subdomains under the city apex.
  module BrgenVerticalSurfaces
    APEX = "brgen.no"

    # label, host, path, body expectations (any match)
    SURFACES = [
      {
        label: "core",
        host: APEX,
        path: "/",
        expect_body: [/main-content|<main\b/i, /brgen|feed|Home|Skip to main/i],
      },
      {
        label: "marketplace",
        host: "markedsplass.#{APEX}",
        path: "/",
        expect_body: [/navBar|Markedsplass|deal-grid|deal-card|search/i],
      },
      {
        label: "marketplace_cart",
        host: "markedsplass.#{APEX}",
        path: "/cart",
        # Guest-open cart — do not require sign-in chrome
        expect_body: [/Cart|Your Cart|navBar|Markedsplass|empty|offer/i],
      },
      {
        label: "dating",
        host: "dating.#{APEX}",
        path: "/",
        expect_body: [/dating|swipe|Oppdag|profile|main|swipe-action/i],
      },
      # One entry, not two. This was "playlist" on spilleliste.brgen.no and
      # "playlist_en" on playlist.brgen.no, a pair that existed to prove the
      # Norwegian alias and the English name both reached the engine. The alias
      # is gone (see Brgen::DomainRegistry::PLAYLIST_SUBDOMAINS) and, for as long
      # as it had been declared, spilleliste.brgen.no was NXDOMAIN — so the half
      # of the pair that justified the split had never once resolved.
      {
        label: "playlist",
        host: "playlist.#{APEX}",
        path: "/",
        expect_body: [/playlist|track|set|main|search/i],
      },
      {
        label: "tv",
        host: "tv.#{APEX}",
        path: "/",
        expect_body: [/tv|channel|video|show|main|stream/i],
      },
      {
        label: "takeaway",
        host: "takeaway.#{APEX}",
        path: "/",
        expect_body: [/takeaway|restaurant|menu|main|search/i],
      },
      {
        label: "maps",
        host: "maps.#{APEX}",
        path: "/",
        expect_body: [/map|place|nearby|main/i],
      },
      {
        label: "messenger",
        host: "messenger.#{APEX}",
        path: "/",
        # Guest-open messenger — inbox chrome without signup wall
        expect_body: [/conversation|Messages|messenger-compose|message/i],
      },
      # Secondary guest surfaces on the apex (not separate Hosts)
      {
        label: "nearby",
        host: APEX,
        path: "/nearby",
        expect_body: [/nearby|location|share|Live|channel/i],
      },
      {
        label: "communities",
        host: APEX,
        path: "/communities",
        expect_body: [/communit|explore|join|create|main/i],
      },
      {
        label: "search",
        host: APEX,
        path: "/search",
        expect_body: [/search|søk|query|result|main/i],
      },
      {
        label: "channels",
        host: APEX,
        path: "/channels",
        expect_body: [/channel|room|chat|live|nearby|main/i],
      },
      {
        label: "conversations",
        host: APEX,
        path: "/conversations",
        expect_body: [/conversation|Messages|messenger|message|chat/i],
      },
      {
        label: "marketplace_deals",
        host: "markedsplass.#{APEX}",
        path: "/deals",
        expect_body: [/deal|offer|Markedsplass|navBar|main/i],
      },
      {
        label: "marketplace_sell",
        host: "markedsplass.#{APEX}",
        path: "/listings/new",
        expect_body: [/list|sell|title|price|navBar|form|main/i],
      },
      {
        label: "marketplace_shops",
        host: "markedsplass.#{APEX}",
        path: "/shops",
        expect_body: [/shop|store|seller|Markedsplass|navBar|main/i],
      },
      # Dating secondary
      {
        label: "dating_profile_new",
        host: "dating.#{APEX}",
        path: "/profile/new",
        expect_body: [/profile|dating|bio|photo|main|form/i],
      },
      {
        label: "dating_matches",
        host: "dating.#{APEX}",
        path: "/matches",
        # Auth-or-empty OK; must not 500
        expect_body: [/match|Oppdag|dating|sign|logg|empty|main/i],
      },
      # Playlist secondary
      {
        label: "playlist_sets",
        host: "playlist.#{APEX}",
        path: "/sets",
        expect_body: [/set|playlist|track|main|search/i],
      },
      {
        label: "playlist_hosted",
        host: "playlist.#{APEX}",
        path: "/hosted_tracks",
        expect_body: [/track|host|upload|playlist|main/i],
      },
      # TV secondary
      {
        label: "tv_channels",
        host: "tv.#{APEX}",
        path: "/channels",
        expect_body: [/channel|tv|video|main|stream/i],
      },
      {
        label: "tv_live_streams",
        host: "tv.#{APEX}",
        path: "/live_streams",
        expect_body: [/live|stream|channel|tv|main/i],
      },
      # Takeaway secondary
      {
        label: "takeaway_orders",
        host: "takeaway.#{APEX}",
        path: "/orders",
        expect_body: [/order|restaurant|takeaway|sign|logg|main|empty/i],
      },
      {
        label: "takeaway_drivers",
        host: "takeaway.#{APEX}",
        path: "/delivery_drivers",
        expect_body: [/driver|delivery|takeaway|main/i],
      },
      # Maps secondary
      {
        label: "maps_places",
        host: "maps.#{APEX}",
        path: "/places",
        # Controller answers JSON catalogue (not HTML shell) for place list API.
        expect_body: [/"name"\s*:|"lat"\s*:|"kind"\s*:|cafe|park|\[/i],
      },
      # Messenger secondary (host + apex already covered)
      {
        label: "posts_index",
        host: APEX,
        path: "/posts",
        expect_body: [/post|Hot|Fresh|Top|main|search|feed/i],
      },
      {
        label: "session_new",
        host: APEX,
        path: "/session/new",
        expect_body: [/password|sign|logg|session|Vipps|Google/i],
      },
    ].freeze

    module_function

    def each_surface
      SURFACES.each { |s| yield s }
    end
  end
end
