# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../support/geometry_probe"
require_relative "../support/gate_autofix"

module Deploy
  # Structural pixel-perfect: a committed, diffable JSON baseline of what the
  # browser laid out, compared per element.
  #
  # This replaces the PNG path as the *assertion*, for three reasons the
  # existing visual_contract_gate cannot work around:
  #
  #   1. Its baseline is whatever PNG happens to be on disk at the destination
  #      path, and it overwrites that file with the new capture. A regression
  #      is reported once and then becomes the baseline.
  #   2. RAILS/visual_contract/*.png is gitignored, so on a fresh checkout or
  #      any CI machine every cell compares against nothing.
  #   3. Exact pixel equality fires on font antialiasing and GPU differences,
  #      so where it does work it cries wolf.
  #
  # A rect/style snapshot is immune to all three: it is text, it is tracked, it
  # survives a machine change, and a diff reads "the buy bar moved up 3px and
  # lost 4px of height" instead of "8,214 pixels changed".
  #
  # Baselines are accepted only under GATE_SNAPSHOT_UPDATE=1 — deliberately NOT
  # under GATE_AUTOFIX, because "make the failure go away by blessing the new
  # layout" is precisely the self-healing behaviour this gate exists to remove.
  class LayoutSnapshotGate
    ROOT = File.expand_path("../../..", __dir__)
    DIR = File.join(File.expand_path("..", __dir__), "data", "layout_snapshots")

    # A moved box matters; a box that shifted by a sub-pixel rounding does not.
    TOLERANCE_PX = 2
    # Below this many tracked elements a surface is too thin to be a baseline.
    MIN_ELEMENTS = 5

    def self.run = new.run

    def self.update? = %w[1 true yes on].include?(ENV["GATE_SNAPSHOT_UPDATE"].to_s.strip.downcase)

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.inconclusive!("layout_snapshot: no Chrome/Chromium — snapshots not compared")
        return @result
      end

      surfaces = GeometryProbe.surfaces.select(&:snapshot)
      GeometryProbe.unreachable_apps(surfaces).each do |app|
        @result.skipped_live("layout_snapshot: #{app} port closed — snapshots skipped")
      end
      live = GeometryProbe.reachable(surfaces)
      if live.empty?
        @result.inconclusive!("layout_snapshot: no app reachable — nothing compared")
        return @result
      end

      FileUtils.mkdir_p(DIR)
      compared = 0
      written = 0
      GeometryProbe.each_payload(live) do |surface, payload|
        if payload["error"]
          @result.fail("layout_snapshot: #{surface.id} probe failed — #{payload["error"]}")
          next
        end
        status = payload["status"].to_i
        unless status.zero? || status.between?(200, 399)
          @result.fail("layout_snapshot: #{surface.id} served HTTP #{status} — not snapshotting an error page")
          next
        end

        current = distill(payload)
        if current["elements"].size < MIN_ELEMENTS
          @result.fail("layout_snapshot: #{surface.id} only #{current["elements"].size} stable elements — too thin to baseline",
                       severity: :soft)
          next
        end

        path = baseline_path(surface)
        if !File.file?(path)
          if self.class.update?
            write(path, current)
            written += 1
            @result.warn("layout_snapshot: #{surface.id} baseline created (#{current["elements"].size} elements)")
          else
            @result.fail("layout_snapshot: #{surface.id} has no committed baseline — " \
                         "run with GATE_SNAPSHOT_UPDATE=1 to record #{rel(path)}", severity: :soft)
          end
          next
        end

        compared += 1
        baseline = JSON.parse(File.read(path))
        diffs = compare(baseline, current)
        if diffs.empty?
          next
        elsif self.class.update?
          write(path, current)
          written += 1
          @result.warn("layout_snapshot: #{surface.id} baseline updated (#{diffs.size} change(s) accepted)")
        else
          report(surface, diffs, path)
        end
      end
      # What was actually measured, so a gate that compared some surfaces and
      # skipped others is not reported as having measured nothing.
      @result.checked!(compared + written)

      @result.warn("layout_snapshot: compared #{compared} surface(s), wrote #{written}") if compared.positive? || written.positive?
      @result
    end

    private

    def rel(path) = path.sub(ROOT + "/", "")

    def baseline_path(surface)
      File.join(DIR, "#{surface.app}-#{surface.label}-#{surface.viewport}.json")
    end

    # Keep only what is structural. Feed items, timestamps and seeded records
    # move for reasons that are not design changes; including them would make
    # the baseline as flaky as the PNG it replaces.
    #
    # The list named `live-item` and `post-meta`, which the live surface has
    # never rendered -- its markup is `live-card-meta` / `live-card-actions`
    # under a `#post_<id>` anchor. So 100 of that baseline's 114 elements were
    # seeded post IDs and the filter caught none of them: the surface drifted on
    # every reseed, and the only available fix was to re-record it, which is the
    # habit this filter exists to prevent. Match the record anchor itself
    # (`#post_2206`, `#comment_88`) rather than trying to enumerate the class
    # names hung off it, since that is the part that is actually a database id.
    # A generated id is the same problem as a database id and worse: Swiper mints
    # `#swiper-wrapper-89838f8a227d649d` fresh on every page load, so the key of
    # every element beneath a carousel changed between two runs of this gate with
    # nothing touched in between. Re-recording could never converge, because the
    # next run invents new ids again. Matched by shape — a hex run of eight or
    # more — rather than by library name, so the next widget that does this is
    # already covered. No real id in this tree looks like that (#main-content,
    # #email_address, #app-tab-bar, #nav_sections).
    VOLATILE_KEY = /
      \#(?:post|comment|listing|item|message|conversation)_\d+ |
      \#[\w-]*[-_][0-9a-f]{8,}\b |
      feed-card|feed-post|deal-card|live-card|live-item|comment_item|post-meta |
      nearby-chat-widget-tab |
      \[\d+\]
    /x

    # nearby-chat-widget-tab is in that list for a reason worth stating, because
    # it is chrome rather than a feed row. Its label is the room the visitor will
    # land in — Shared::UiHelper#ambient_chat_room_label returns "nearby" when
    # Current.user has coordinates and the lobby channel when it does not — so
    # the tab is 94px or 104px wide depending on visitor state, and the two
    # alternate between runs of this gate. The partial's own comment records an
    # earlier fix for the same symptom: the label used to be rewritten by
    # nearby_chat_controller after the frame arrived, and moving it server-side
    # stopped the visible relabel without making the width one value.
    # Excluded rather than re-recorded, because re-recording could not converge.
    # The design question underneath — whether a tab whose width depends on
    # whether GPS is on is the intended behaviour — is the operator's, not this
    # gate's.
    STRUCTURAL_TAG = %w[header nav main footer aside form h1 h2 button a input select textarea].freeze

    def distill(payload)
      rows = Array(payload["elements"]).select do |el|
        next false unless el["visible"] && el["onscreen"] != false
        next false if el["key"].to_s.match?(VOLATILE_KEY)

        STRUCTURAL_TAG.include?(el["tag"]) || el["role"]
      end

      {
        "title" => payload["title"],
        "viewport" => [payload["vw"], payload["vh"]],
        "scroll_width" => payload["scroll_width"],
        "h1_count" => payload["h1_count"],
        "landmarks" => payload["landmarks"],
        "elements" => rows.map do |el|
          {
            "key" => el["key"],
            "tag" => el["tag"],
            "rect" => el["rect"],
            "color" => el["color"],
            "bg" => el["bg"],
            "font_size" => el["font_size"],
            "line_height" => el["line_height"],
            "display" => el["display"],
            "position" => el["position"],
          }
        end.sort_by { |el| el["key"].to_s },
      }
    end

    def compare(baseline, current)
      diffs = []
      %w[title h1_count scroll_width].each do |field|
        next if baseline[field] == current[field]

        diffs << "#{field}: #{baseline[field].inspect} → #{current[field].inspect}"
      end
      (baseline["landmarks"] || {}).each do |mark, was|
        now = current.dig("landmarks", mark)
        diffs << "landmark #{mark}: #{was} → #{now}" if was != now
      end

      old_by_key = (baseline["elements"] || {}).to_h { |el| [el["key"], el] }
      new_by_key = (current["elements"] || {}).to_h { |el| [el["key"], el] }

      (old_by_key.keys - new_by_key.keys).first(6).each { |k| diffs << "removed: #{k}" }
      (new_by_key.keys - old_by_key.keys).first(6).each { |k| diffs << "added: #{k}" }

      (old_by_key.keys & new_by_key.keys).each do |key|
        was = old_by_key[key]
        now = new_by_key[key]
        moved = %w[x y w h].select do |axis|
          (was.dig("rect", axis).to_i - now.dig("rect", axis).to_i).abs > TOLERANCE_PX
        end
        unless moved.empty?
          detail = moved.map { |a| "#{a} #{was.dig("rect", a)}→#{now.dig("rect", a)}" }.join(", ")
          diffs << "#{key}: #{detail}"
        end
        %w[color bg font_size line_height display position].each do |field|
          next if was[field] == now[field]

          diffs << "#{key}: #{field} #{was[field].inspect} → #{now[field].inspect}"
        end
      end
      diffs
    end

    def report(surface, diffs, path)
      shown = diffs.first(8)
      more = diffs.size > shown.size ? " (+#{diffs.size - shown.size} more)" : ""
      @result.fail(
        "layout_snapshot: #{surface.id} drifted from #{rel(path)} — #{shown.join("; ")}#{more}"
      )
    end

    def write(path, data)
      File.write(path, JSON.pretty_generate(data) + "\n")
    end
  end
end
