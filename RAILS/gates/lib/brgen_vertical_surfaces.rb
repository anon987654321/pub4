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
        label: "live",
        host: APEX,
        path: "/live",
        expect_body: [/Live|live-feed|live-compose|ground rules|Hot|New|anon/i],
      },
      {
        label: "dating",
        host: "dating.#{APEX}",
        path: "/",
        expect_body: [/dating|swipe|Oppdag|profile|main|swipe-action/i],
      },
      {
        label: "playlist",
        host: "spilleliste.#{APEX}",
        path: "/",
        expect_body: [/playlist|spilleliste|track|set|main|search/i],
      },
      {
        label: "playlist_en",
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
    ].freeze

    module_function

    def each_surface
      SURFACES.each { |s| yield s }
    end
  end
end
