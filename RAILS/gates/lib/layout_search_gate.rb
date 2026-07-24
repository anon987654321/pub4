# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  # Bounded design-search: score legal marketplace layout candidates; enforce winner.
  # Axes are finite; hard constraints cannot be traded (MASTER hard floor).
  class LayoutSearchGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    CARD = File.join(RAILS, "brgen/app/views/marketplace/listings/_card.html.erb")
    CARDS_CSS = File.join(RAILS, "brgen/app/assets/stylesheets/_marketplace_cards.scss")
    NAV = File.join(RAILS, "brgen/app/views/marketplace/_nav_bar.html.erb")
    SEARCH = File.join(RAILS, "shared/app/assets/stylesheets/_search_yep.scss")

    # Candidate definitions (structural only — no runtime CSS mutation).
    CANDIDATES = {
      price_first_tile: {
        desc: "Tise/Bol: price before title on product tile",
        hard: true,
        score: lambda { |ctx|
          card = ctx[:card]
          price_i = card.index("deal-price")
          title_i = card.index("deal-card-title")
          return 0 unless price_i && title_i
          price_i < title_i ? 40 : 5
        },
      },
      photo_first: {
        desc: "Photo media before body on tile",
        hard: true,
        score: lambda { |ctx|
          card = ctx[:card]
          img = card.index("deal-card-img") || card.index("deal-card-media")
          body = card.index("deal-card-body")
          return 0 unless img && body
          img < body ? 25 : 5
        },
      },
      amazon_nav_present: {
        desc: "Amazon-style #navBar on marketplace surfaces",
        hard: true,
        score: lambda { |ctx|
          ctx[:nav].include?("navBar") || ctx[:nav].include?("id=\"navBar\"") ? 20 : 0
        },
      },
      yep_search_surface: {
        desc: "Yep.com .search surface for live search",
        hard: true,
        score: lambda { |ctx|
          ctx[:search].include?(".search") && ctx[:search].include?("border-radius: 30px") ? 15 : 0
        },
      },
      whole_card_hit: {
        desc: "Whole-card link (least resistance) vs multi-CTA grid",
        hard: false,
        score: lambda { |ctx|
          card = ctx[:card]
          if card.include?("deal-card-hit") || card.match?(/link_to.*deal-card/)
            15
          elsif card.scan(/button_to|deal-cta/).size > 2
            5 # more resistance
          else
            10
          end
        },
      },
    }.freeze

    TARGET_SCORE = 90
    MAX_RESISTANCE = 30

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      ctx = load_ctx
      return @result if ctx.nil?

      scores = {}
      CANDIDATES.each do |id, spec|
        s = spec[:score].call(ctx)
        scores[id] = s
        if spec[:hard] && s < 15
          @result.fail("layout_search hard fail: #{id} — #{spec[:desc]} (score #{s})")
        end
      end

      total = scores.values.sum
      # Resistance: inverse of soft scores (higher resistance = worse)
      resistance = [100 - total, 0].max
      @result.warn("layout_search: scores=#{scores.inspect} total=#{total} resistance=#{resistance}")

      if total < TARGET_SCORE
        @result.fail("layout_search: total #{total} < target #{TARGET_SCORE} (least-resistance floor)")
      end
      if resistance > MAX_RESISTANCE
        @result.fail("layout_search: resistance #{resistance} > max #{MAX_RESISTANCE}")
      end

      # Prefer price-first over title-first (document winner)
      if scores[:price_first_tile].to_i >= 40
        @result.warn("layout_search winner: price_first_tile + photo_first (Tise/Bol natural catalog)")
      end
      @result
    end

    private

    def load_ctx
      missing = [CARD, CARDS_CSS, NAV, SEARCH].reject { |p| File.file?(p) }
      if missing.any?
        missing.each { |p| @result.fail("layout_search: missing #{p.sub(RAILS + '/', '')}") }
        return nil
      end
      {
        card: File.read(CARD),
        cards_css: File.read(CARDS_CSS),
        nav: File.read(NAV),
        search: File.read(SEARCH),
      }
    end
  end
end
