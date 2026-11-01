# frozen_string_literal: true

require_relative "../../support/check_result"
require_relative "../../support/layout_search"
require_relative "../../../tools/scss"

module Deploy
  # Bounded multi-candidate layout search for marketplace.
  # Enumerates legal design axes, scores Fitts/Hick/resistance/catalog,
  # requires observed tree == winner (or top-N) and hard floors.
  class LayoutSearchCheck
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")

    # Views live in the brgen_marketplace engine, a sibling of brgen. The
    # marketplace component styles live in the host entrypoint: the 2026-10-28
    # consolidation folded brgen's `_brgen_*.scss` feature partials into
    # application.scss between `// ===== module:` banners, cascade order kept,
    # so the check reads the `brgen_*` module sections out of that one sheet.
    ENGINE = File.join(RAILS, "brgen_marketplace")
    CARD = File.join(ENGINE, "app/views/marketplace/listings/_card.html.erb")
    BRGEN_STYLESHEET = File.join(RAILS, "brgen/app/assets/stylesheets/application.scss")
    MODULE_OPEN = /\A\/\/ ={5,} module: ([a-z0-9_]+)\s*\z/.freeze
    MODULE_CLOSE = /\A\/\/ ={5,} \/module: /.freeze
    # The #navBar markup is the storefront header marketplace shares with takeaway.
    NAV = File.join(RAILS, "brgen/app/views/shared/_storefront_nav_bar.html.erb")
    SEARCH = File.join(RAILS, "__shared/app/assets/stylesheets/_search_yep.scss")

    def self.run
      new.run
    end

    def run
      @result = CheckResult.new
      ctx = load_ctx
      return @result if ctx.nil?

      @result.checked!(ctx.size)
      search = LayoutSearch.new
      report = search.report(ctx)
      emit_report!(report)
      enforce!(report)
      @result
    end

    private

    def load_ctx
      missing = [CARD, NAV, SEARCH].reject { |p| File.file?(p) }
      missing << BRGEN_STYLESHEET unless File.file?(BRGEN_STYLESHEET)
      if missing.any?
        missing.each { |p| @result.fail("layout_search: missing #{p.sub(RAILS + '/', '')}") }

        return
      end
      if cards_css.empty?
        @result.fail("layout_search: brgen_* modules in application.scss have no .deal-card rule")
        return
      end

      {
        card: card_source,
        cards_css:,
        nav: File.read(NAV),
        search: File.read(SEARCH),
      }
    end

    def cards_css
      @cards_css ||= Operator::ScssRules.matching(feature_css_source, /\.deal-card\b/)
                                        .map { |rule| "#{rule.selector} { #{rule.body} }" }.join("\n")
    end

    # The card rules live in the brgen_* module sections of the merged host
    # sheet (operator 2026-10-28): slice them out by banner, cascade order
    # kept, so the detector reads the same cascade the page ships. Modules
    # outside the former `_brgen_*.scss` glob (post_gallery, local_activity,
    # vertical_promo) stay excluded, as before the merge.
    def feature_css_source
      kept = []
      inside = false
      File.foreach(BRGEN_STYLESHEET) do |line|
        if (open_m = line.match(MODULE_OPEN))
          inside = open_m[1].start_with?("brgen_")
        elsif line.match?(MODULE_CLOSE)
          inside = false
        elsif inside
          kept << line
        end
      end
      kept.join
    end

    # The card's media slot lives in marketplace/_card_media.html.erb since the
    # component sitting (2026-08-21). A source-reading detector must follow the
    # render or it measures the refactor as a layout regression — the page
    # still puts the photo first; only the file boundary moved. One level of
    # expansion is enough: the partial holds the deal-card-img marker.
    def card_source
      File.read(CARD).gsub(/render ["']marketplace\/([a-z_]+)["'][^\n]*/) do
        partial = File.join(ENGINE, "app/views/marketplace/_#{Regexp.last_match(1)}.html.erb")

        File.file?(partial) ? File.read(partial) : Regexp.last_match(0)
      end
    end

    def emit_report!(report)
      win = report[:winner]
      obs = report[:observed]
      ranking = report[:ranking]

      @result.warn(
        "layout_search: space=#{report[:space_size]} legal=#{report[:legal_size]} " \
        "target=#{report[:target]} max_rank=#{report[:max_rank]}",
      )

      if win
        @result.warn(
          "layout_search winner: score=#{win.score} axes=#{win.axes.inspect} " \
          "breakdown=#{win.breakdown.inspect}",
        )
      else
        @result.fail("layout_search: no legal candidates in space")
        return
      end

      # Top-5 ranking for design review
      ranking.first(5).each_with_index do |c, i|
        mark = c.id == obs.id ? " ← observed" : ""
        @result.warn("layout_search rank ##{i + 1}: #{c.score} #{short_axes(c.axes)}#{mark}")
      end

      obs_c = report[:observed_candidate]
      @result.warn(
        "layout_search observed: rank=#{report[:observed_rank] || '∉ legal'} " \
        "score=#{obs_c.score} axes=#{obs.axes.inspect} hard_required=#{report[:hard_required_ok]}",
      )
    end

    def enforce!(report)
      win = report[:winner]
      return unless win

      obs = report[:observed]
      obs_c = report[:observed_candidate]
      rank = report[:observed_rank]

      unless report[:hard_required_ok]
        missing = report_hard_gaps(obs.axes, report)
        @result.fail(
          "layout_search hard floor: observed missing required axes #{missing.join(', ')} " \
          "(MASTER catalog floor — not tradable)",
        )
      end

      if obs_c.score < report[:target]
        @result.fail(
          "layout_search: observed score #{obs_c.score} < target #{report[:target]} " \
          "(least-resistance / Fitts-Hick floor) breakdown=#{obs_c.breakdown.inspect}",
        )
      end

      if rank.nil?
        @result.fail("layout_search: observed layout not in legal candidate set")
        return
      end

      if rank > report[:max_rank]
        @result.fail(
          "layout_search: observed rank ##{rank} > max_winner_rank #{report[:max_rank]} — " \
          "winner is #{short_axes(win.axes)} (score #{win.score}); " \
          "observed #{short_axes(obs.axes)} (score #{obs_c.score}). " \
          "principle=least_resistance",
        )
      elsif rank == 1
        @result.warn("layout_search: observed IS winner (design search locked)")
      end
    end

    def report_hard_gaps(axes, _report)
      # re-read hard required from search config via winner path
      search = LayoutSearch.new
      search.hard_required.filter_map do |axis, variant|
        next if axes[axis.to_s] == variant.to_s

        "#{axis}=#{variant} (have #{axes[axis.to_s]})"
      end
    end

    def short_axes(axes)
      axes.map { |k, v| "#{k.split('_').first}=#{v}" }.join(" ")
    end
  end
end
