# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/layout_search"

module Deploy
  # Bounded multi-candidate layout search for marketplace.
  # Enumerates legal design axes, scores Fitts/Hick/resistance/catalog,
  # requires observed tree == winner (or top-N) and hard floors.
  class LayoutSearchGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS = File.join(ROOT, "RAILS")
    # Views moved to engines/marketplace in the vertical-as-engine split; the
    # SCSS stayed in the host (engines contribute no stylesheets). See ENGINES.md.
    ENGINE = File.join(RAILS, "brgen/engines/marketplace")
    CARD = File.join(ENGINE, "app/views/marketplace/listings/_card.html.erb")
    CARDS_CSS = File.join(RAILS, "brgen/app/assets/stylesheets/_marketplace_cards.scss")
    NAV = File.join(ENGINE, "app/views/marketplace/_nav_bar.html.erb")
    SEARCH = File.join(RAILS, "shared/app/assets/stylesheets/_search_yep.scss")

    def self.run
      new.run
    end

    def run
      @result = GateResult.new
      ctx = load_ctx
      return @result if ctx.nil?

      search = LayoutSearch.new
      report = search.report(ctx)
      emit_report!(report)
      enforce!(report)
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
        card: card_source,
        cards_css: File.read(CARDS_CSS),
        nav: File.read(NAV),
        search: File.read(SEARCH),
      }
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
        "target=#{report[:target]} max_rank=#{report[:max_rank]}"
      )

      if win
        @result.warn(
          "layout_search winner: score=#{win.score} axes=#{win.axes.inspect} " \
          "breakdown=#{win.breakdown.inspect}"
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
        "score=#{obs_c.score} axes=#{obs.axes.inspect} hard_required=#{report[:hard_required_ok]}"
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
          "(MASTER catalog floor — not tradable)"
        )
      end

      if obs_c.score < report[:target]
        @result.fail(
          "layout_search: observed score #{obs_c.score} < target #{report[:target]} " \
          "(least-resistance / Fitts-Hick floor) breakdown=#{obs_c.breakdown.inspect}"
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
          "principle=least_resistance"
        )
      elsif rank == 1
        @result.warn("layout_search: observed IS winner (design search locked)")
      end
    end

    def report_hard_gaps(axes, report)
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
