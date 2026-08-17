# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/geometry_probe"

module Deploy
  # Relations between two renders of the same thing. No baseline, no fixture.
  #
  # Every one of these finds a class of bug that a single-load assertion cannot
  # see, and none of them needs anything committed to compare against:
  #
  #   idempotence  — the same URL twice must lay out identically. A surface that
  #                  fails here makes every other visual assertion flaky, so this
  #                  runs first and its failure explains the others.
  #   back_button  — Turbo-navigate away and back must equal a fresh load. The
  #                  existing system test only asserts a meta tag is absent.
  #   no_js_parity — the landmark set must survive with JavaScript disabled.
  #                  That is the stimulus_progressive principle, currently
  #                  enforced by grepping views for the string "jquery".
  class JourneyInvariantGate
    ROOT = File.expand_path("../../../..", __dir__)

    # Ignore boxes that legitimately differ between two loads of a live feed.
    VOLATILE = /feed-card|feed-post|deal-card|live-item|comment_item|carousel|swiper/

    def self.run = new.run

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.inconclusive!("journey_invariant: no Chrome/Chromium — invariants not checked")
        return @result
      end

      surfaces = pick_surfaces
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.skipped_live("journey_invariant: #{app} port closed — skipped")
      end
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("journey_invariant: no app reachable")
        return @result
      end

      GeometryProbe.with_browser do |cdp|
        live.each do |surface|
          first = GeometryProbe.walk(cdp, surface)
          unless GeometryProbe.ok?(first)
            @result.fail("journey_invariant: #{surface.id} unreachable (#{first["error"] || "HTTP #{first["status"]}"})")
            next
          end

          check_idempotence(cdp, surface, first)
          check_back_button(cdp, surface, first, live)
        end
      end

      check_no_js_parity(live)
      # Counted per surface, so one surface that could not be measured does not
      # make the ones that were count for nothing.
      @result.checked!(live.size)
      # A gate that reports nothing must be distinguishable from a gate that
      # ran nothing, or a silently-empty sweep reads as a pass forever.
      @result.warn("journey_invariant: checked idempotence + back-button on #{live.size} surface(s), " \
                   "no-JS parity on #{live.map(&:app).uniq.size} app(s)")
      @result
    end

    private

    # One representative surface per app per viewport keeps this gate a
    # relation check rather than a second full sweep.
    def pick_surfaces
      GeometryProbe.surfaces
                   .select { |s| s.viewport == "mobile" }
                   .group_by(&:app)
                   .flat_map { |_app, rows| rows.first(2) }
    end

    def check_idempotence(cdp, surface, first)
      second = GeometryProbe.walk(cdp, surface)
      return unless GeometryProbe.ok?(second)

      diffs = structural_diff(first, second)
      return if diffs.empty?

      @result.fail(
        "journey_invariant idempotence: #{surface.id} lays out differently on two consecutive loads — " \
        "#{diffs.first(4).join('; ')}#{diffs.size > 4 ? " (+#{diffs.size - 4})" : ""} " \
        "(nondeterministic render; every visual assertion on this surface is flaky until fixed)",
        severity: :soft
      )
    end

    def check_back_button(cdp, surface, fresh, pool)
      other = pool.find { |s| s.app == surface.app && s.id != surface.id }
      return unless other

      begin
        GeometryProbe.walk(cdp, other)
        cdp.evaluate("history.back()")
        sleep 0.4
        GeometryProbe.wait_for_fonts(cdp)
        restored = cdp.evaluate(GeometryProbe::WALK).merge("status" => 200)
      rescue CdpSession::Error => e
        @result.warn("journey_invariant back_button: #{surface.id} #{e.class.name.split("::").last}: #{e.message}")
        return
      end

      if restored["title"].to_s != fresh["title"].to_s
        @result.fail(
          "journey_invariant back_button: #{surface.id} restored #{restored["title"].inspect} " \
          "but a fresh load is #{fresh["title"].inspect} — history navigation does not return the same page"
        )
        return
      end

      diffs = structural_diff(fresh, restored)
      return if diffs.empty?

      @result.fail(
        "journey_invariant back_button: #{surface.id} after back() differs from a fresh load — " \
        "#{diffs.first(4).join('; ')} (Turbo cache restored a stale or partial view)",
        severity: :soft
      )
    end

    # With JS off, the server-rendered HTML must still carry the landmarks. If
    # it does not, the page is a client-side app wearing progressive-enhancement
    # clothes and every no-JS visitor gets nothing.
    def check_no_js_parity(surfaces)
      surfaces.group_by(&:app).each do |app, rows|
        surface = rows.first
        html = begin
          fetch_raw(surface)
        rescue StandardError => e
          @result.warn("journey_invariant no_js: #{app} fetch failed — #{e.class}")
          next
        end

        {
          "main" => /<main\b|id=["']main-content["']|role=["']main["']/i,
          "nav" => /<nav\b|role=["']navigation["']/i,
          "skip" => /skip-link|href=["']#main-content["']/i,
        }.each do |mark, pattern|
          next if pattern.match?(html)

          @result.fail(
            "journey_invariant no_js: #{app} server HTML has no #{mark} landmark at #{surface.path} — " \
            "present only after JavaScript runs (principle=progressive_enhancement)"
          )
        end
      end
    end

    def fetch_raw(surface)
      uri = URI("http://127.0.0.1:#{surface.port}#{surface.path}")
      Net::HTTP.start(uri.host, uri.port, open_timeout: 8, read_timeout: 15) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["Host"] = surface.host if surface.host
        http.request(req).body.to_s
      end
    end

    def structural_diff(a, b)
      diffs = []
      %w[title h1_count scroll_width].each do |field|
        diffs << "#{field} #{a[field].inspect}→#{b[field].inspect}" if a[field] != b[field]
      end
      (a["landmarks"] || {}).each do |mark, was|
        now = b.dig("landmarks", mark)
        diffs << "landmark #{mark} #{was}→#{now}" if was != now
      end

      old = stable(a)
      new = stable(b)
      (old.keys - new.keys).first(3).each { |k| diffs << "vanished: #{k}" }
      (new.keys - old.keys).first(3).each { |k| diffs << "appeared: #{k}" }
      (old.keys & new.keys).each do |key|
        next if diffs.size > 12

        %w[w h].each do |axis|
          was = old[key].dig("rect", axis).to_i
          now = new[key].dig("rect", axis).to_i
          diffs << "#{key} #{axis} #{was}→#{now}" if (was - now).abs > 2
        end
      end
      diffs
    end

    def stable(payload)
      Array(payload["elements"])
        .select { |el| el["visible"] && el["onscreen"] != false }
        .reject { |el| el["key"].to_s.match?(VOLATILE) }
        .to_h { |el| [el["key"], el] }
    end
  end
end
