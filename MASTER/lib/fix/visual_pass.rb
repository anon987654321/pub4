# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "../review/council/critique"
require_relative "rails_visual_graph"
require_relative "visual_usability"
require_relative "visual_reference"
require_relative "visual_contact_sheet"
require_relative "visual_ghost_stack"
require_relative "visual_evidence_rows"
require_relative "visual_artifact"
require_relative "visual_custody"
require_relative "../design/visual_language"
require_relative "../../gates/support/mobile_journey_probe"
require_relative "../../gates/support/composition_probe"
require_relative "../../gates/support/web_platform_probe"

module Master
  module Fix
    # Rendered UI is evidence, not a second scanner. GeometryProbe owns the
    # browser; Council owns visual judgement; RuleLoop owns the edit.
    # Asked of every visual conclusion before it becomes a finding.
    HOSTILE_VISUAL_AUDIT = <<~TEXT.freeze
      HOSTILE VISUAL AUDIT
      Before proposing a fix, challenge the visual conclusion:
      - What observation would falsify the claimed visual defect?
      - Could font loading, locale, dynamic data, viewport state, or animation explain the apparent drift?
      - What useful interaction or information would a visual cleanup accidentally remove?
      - Which adjacent state is not represented by this screenshot but could expose a regression?
      - Is the proposed improvement actually a deletion, alignment correction, or existing-primitives fix rather than new visual machinery?
      - What would a careless or adversarial user do to reveal a hidden overlap, dead control, misleading affordance, or inaccessible state?
      - Which part of the page should remain deliberately imperfect because it carries product identity or useful information?
      Only promote a hostile observation into a finding when rendered evidence or repository evidence supports it.
    TEXT

    class VisualPass
      include VisualEvidenceRows

      RULE_ID = "RENDERED_VISUAL_REFINEMENT"
      SOURCE_EXTENSIONS = %w[.css .scss .erb .html .htm .js .ts].freeze
      MAX_SURFACES = Integer(ENV.fetch("MASTER_VISUAL_SURFACES_PER_PASS", "0"))
      MAX_COMPOSITION_STATES = Integer(ENV.fetch("MASTER_VISUAL_COMPOSITION_STATES", "12"))
      MAX_FILES = 12
      SELECTOR_RE = /#[A-Za-z][\w-]*|\.[A-Za-z_][\w-]*(?:[-_][\w-]*)*/.freeze
      TEXT_ANCHOR_RE = /\b(?:visible\s+text(?:\s+anchor)?|text\s+anchor)\s*[:=]\s*["“]([^"”\n]+)["”]/i.freeze
      LAW_RE = /\blaws?\s*[:=]\s*([A-Z][A-Z0-9_, -]+)/i.freeze
      # Surface ids are paths, so %r{} keeps the literal slash readable.
      SURFACE_RE = %r{\bsurface\s*[:=]\s*([A-Za-z0-9_./-]+)\b}i.freeze
      VIEWPORT_RE = /\bviewport\s*[:=]\s*([A-Za-z0-9_-]+)\b/i.freeze
      Rule = Data.define(:id) do
        def severity = :warning
      end

      attr_reader :dir, :custody

      def initialize(agent:, root:, bus: nil)
        @agent = agent
        @root = root
        @bus = bus
        @dir = nil
        @custody = nil
      end

      def applicable?(target)
        relative = repo_relative(target)
        relative == "RAILS" || relative.start_with?("RAILS/") ||
          relative == "MASTER/web" || relative.start_with?("MASTER/web/")
      end

      def run(target:, files:, pass:)
        return Result.ok(state: :not_applicable) unless applicable?(target)
        raise "visual review has no agent" unless @agent

        require File.expand_path("../../gates/support/geometry_probe", __dir__)

        @dir = Dir.mktmpdir("master-visual")
        @ghost_stack = VisualGhostStack.new(root: repo_root, dir: @dir)
        graph = RailsVisualGraph.new(root: repo_root).build if rails_target?(target)
        return inconclusive("source graph discovery failed: #{graph.errors.first(4).join("; ")}") if graph&.errors&.any?
        surfaces = selected_surfaces(target:, pass:)
        return inconclusive("no declared surfaces") if surfaces.empty?

        captures = capture_surfaces(surfaces, pass:)
        return inconclusive("no surface was measured") if captures.empty?

        @custody = VisualCustody.new(root: repo_root, surfaces:, bus: @bus)
        custody = @custody.preflight!(captures)
        return inconclusive(custody.message) unless custody.ok?

        decorate_design(captures)
        coverage = graph_coverage(surfaces, captures)
        return inconclusive("missing rendered surfaces: #{coverage[:missing].join(", ")}") if coverage[:missing].any?

        sources, anchors = candidate_sources(target:, files:, captures:, graph:)
        return inconclusive("no frontend source anchor") if sources.empty?

        review_captures(captures, sources, anchors, pass, graph:, coverage:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_pass", event_bus: @bus)
        inconclusive("#{e.class}: #{e.message}")
      end

      def cleanup
        return unless @dir && File.directory?(@dir)

        FileUtils.remove_entry(@dir)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_pass.cleanup", event_bus: @bus)
      ensure
        @dir = nil
        @custody = nil
      end

      private

      def inconclusive(reason) = Result.err("rendered visual review: INCONCLUSIVE — #{reason}", category: :inconclusive)

      def capture_surfaces(surfaces, pass:)
        captures = []
        Deploy::GeometryProbe.with_browser(root: repo_root, warm: surfaces) do |cdp|
          surfaces.each do |surface|
            resting = capture_resting(cdp, surface)
            next unless resting

            captures << resting
            captures.concat(Deploy::CompositionProbe.capture(cdp, surface, dir: @dir, pass:, limit: MAX_COMPOSITION_STATES))
          end

          # All app captures are complete before we navigate this browser to
          # local evidence pages. One CDP session serves the entire sweep.
          captures.each do |capture|
            capture[:visual_evidence] = @ghost_stack.capture(capture, pass:, cdp:)
          end
        end
        captures
      end

      # The surface as it loads, before any composition state is triggered;
      # nil when the geometry walk fails.
      def capture_resting(cdp, surface)
        payload = Deploy::GeometryProbe.walk(cdp, surface)
        return unless Deploy::GeometryProbe.ok?(payload)

        payload["composition"] = { "state" => "resting", "base_surface" => surface.id }
        shot = File.join(@dir, "#{safe_slug(surface.id)}.png")
        cdp.screenshot(shot, capture_beyond_viewport: true)
        journeys = Deploy::MobileJourneyProbe.run(cdp, surface, @dir)
        platform = Deploy::WebPlatformProbe.run(cdp, surface)
        { surface:, payload:, screenshot: shot, journeys:, platform: }
      end

      def run_critique(captures, sources, anchors, graph:)
        context = build_context(captures, anchors, graph:)
        contact_sheet = VisualContactSheet.new(dir: @dir, root: repo_root).render(captures)
        image = { path: contact_sheet, name: "rendered-ui-contact-sheet.png", mime: "image/png" }
        critique = Master::Review::Council::Critique.new(
          mode: :ui,
          agent: @agent,
          event_bus: @bus,
          files: sources,
          visual_image: image,
          visual_context: context,
        ).run
        [critique, image]
      end

      def review_captures(captures, sources, anchors, pass, graph:, coverage:)
        critique, image = run_critique(captures, sources, anchors, graph:)
        return inconclusive("#{critique.message}") if critique.err?

        artifact = keep_artifact(captures, image, pass)
        findings = anchored_findings(critique, sources, anchors)
        return findings if findings.is_a?(Result)

        @bus&.publish("fix_loop:visual_review", pass:, surfaces: captures.map { |c| c[:surface].id }, findings: findings.size, coverage: coverage[:ratio], graph: graph&.context)
        Result.ok(
          state: findings.empty? ? :clean : :findings,
          findings:,
          image:,
          artifact:,
          coverage: coverage.merge(captured: captures.map { |c| c[:surface].id }),
        )
      end

      def keep_artifact(captures, image, pass)
        VisualArtifact.new(root: @root).keep(target: repo_relative(@root), pass:, captures:, image:, bus: @bus)
      end

      # The council's picks that point at source, or an inconclusive Result
      # when it picked something and none of it could be anchored.
      def anchored_findings(critique, sources, anchors)
        picks = Array(critique.value![:cherry_picks]).map(&:to_s).reject(&:empty?)
        findings = picks.filter_map { |pick| finding_for(pick, sources, anchors) }
        return findings unless picks.any? && findings.empty?

        Result.err(
          "rendered visual review: INCONCLUSIVE — Council returned actionable visual picks, but none could be anchored to source evidence",
          category: :inconclusive,
        )
      end

      def selected_surfaces(target:, pass:)
        rows = Deploy::GeometryProbe.surfaces(root: repo_root)
        master = repo_relative(target).start_with?("MASTER/web")
        rows = rows.select { |s| master ? s.app == "master" : s.app != "master" }
        grouped = rows.group_by(&:app)

        core = grouped.keys.sort.flat_map do |app|
          group = grouped.fetch(app)
          mobile = group.find { |s| s.viewport == "mobile" }
          desktop = group.find { |s| s.viewport == "desktop" }
          [mobile || group.first, desktop || group.find { |s| s != mobile }]
        end.compact.uniq

        extras = rows.reject { |s| core.include?(s) }.sort_by { |s| [s.app, s.label, s.viewport == "mobile" ? 0 : 1, s.viewport] }
        return core + extras if MAX_SURFACES <= 0

        return (core + extras).first(MAX_SURFACES) if core.size >= MAX_SURFACES

        offset = ((pass.to_i - 1) * MAX_SURFACES) % [extras.size, 1].max
        (core + extras.rotate(offset)).first(MAX_SURFACES)
      end

      def candidate_sources(target:, files:, captures:, graph:)
        candidates = Array(files).select { |path| source_file?(path) }.uniq
        if graph
          candidates = (candidates + captures.flat_map { |capture| graph.sources_for(capture[:surface]) }).uniq
        end
        tokens = captures.flat_map do |capture|
          Array(capture[:payload]["elements"]).flat_map do |element|
            [element["key"], element["aria"]].compact
          end
        end.map { |token| token.to_s[/#[\w-]+|\.[\w-]+/] }.compact.uniq.first(50)

        anchors = {}
        tokens.each { |token| anchors[token] = grep_source(token, allowed: candidates) }
        candidates = (anchors.values.compact + candidates).uniq.first(MAX_FILES)
        candidates = fallback_sources(target) if candidates.empty?
        [candidates.first(MAX_FILES), anchors]
      end

      # Restricted to files already in this pass's own scope -- an
      # unrestricted repo-wide grep let a common selector/class name in one
      # app misattribute a finding to an unrelated file in another.
      def grep_source(token, allowed:)
        out, status = Open3.capture2("git", "-C", repo_root, "grep", "-l", "--fixed-strings", token,
                                     "--", "RAILS", "MASTER/web")
        return unless status.success?

        out.lines.map(&:strip).map { |rel| File.join(repo_root, rel) }
           .find { |path| source_file?(path) && allowed.include?(path) }
      rescue StandardError
        nil
      end

      def fallback_sources(target)
        base = repo_relative(target)
        root = base.start_with?("MASTER/web") ? File.join(repo_root, "MASTER/web") : File.join(repo_root, "RAILS")
        Dir.glob(File.join(root, "**", "*"))
           .select { |path| source_file?(path) }
           .sort_by { |path| [path.include?("stylesheets") ? 0 : 1, path.length, path] }
           .first(MAX_FILES)
      end

      def context_row(capture)
        surface = capture[:surface]
        payload = capture[:payload]
        visual = payload["visual"] || {}
        first = visual["first_screen"] || {}
        type = visual["typography"] || {}
        [
          "surface #{surface.id}: #{surface.url}",
          "composition=#{capture.dig(:payload, "composition", "state") || "resting"} ",
          "trigger=#{Array(capture.dig(:payload, "composition", "triggers") || capture.dig(:payload, "composition", "trigger")).join(" + ")}",
          "first-screen text=#{first["text_blocks"]}, interactive=#{first["interactive"]}, ",
          "largest_area=#{first["largest_element_area_ratio"]}, small_text=#{first["small_text"]}, ",
          "centered_long_text=#{first["centered_long_text"]}",
          "type sizes=#{type["distinct_font_sizes"]&.first(8)}, body median=#{type["body_median_px"]}, ",
          "leading=#{type["line_height_min_px"]}-#{type["line_height_max_px"]}",
          "scroll/client=#{payload["scroll_width"]}/#{payload["client_width"]}",
          "mobile-states=#{Array(capture[:journeys]).map { |j| "#{j["kind"]}:#{j["label"]}" }.join(", ")}",
          "web-platform=#{capture[:platform].reject { |key, _| key == "viewport" }.map { |key, value| "#{key}=#{value}" }.join(", ")}",
        ].join(" ")
      end

      def decorate_design(captures)
        Array(captures).each do |capture|
          payload = capture[:payload]
          next unless payload.is_a?(Hash)

          payload["design_fingerprint"] = Master::Design::VisualLanguage.fingerprint(payload)
        end
      end

      def build_context(captures, anchors, graph:)
        rows = captures.map { |capture| context_row(capture) }
        drift_rows = captures.filter_map { |capture| drift_row(capture) }
        mapped = anchors.values.compact.uniq.first(12)
        <<~TEXT
          RENDERED EVIDENCE
          The attached image is a contact sheet containing every captured surface and exercised mobile state in this pass. Each surface also has a persistent ghost stack: aligned renders from recent /fix passes are layered at low opacity, with a difference view for the newest two. Use these to spot optical drift and one-to-few-pixel misalignment before proposing a source change. The measurements below were
          collected from the same browser session across the listed surfaces.
          Mobile is the primary composition: every mobile surface is exercised through safe, non-destructive focus, validation, disclosure, and same-origin navigation journeys when those states exist. Navigation journeys include return-path evidence; journey screenshots are evidence, not a score. Treat web-platform probe findings as evidence about layout primitives, not automatic prescriptions; choose the smallest modern primitive that fits the rendered behavior and browser support.
          Judge the render first. Source is supporting evidence.
          Apply the executable MASTER design/usability constitution below. These are laws, not a scoring checklist. Identify only laws supported by rendered evidence.
          #{Master::Fix::VisualUsability.context}
          #{Master::Fix::VisualReference.context}
          Every actionable issue must name the applicable law id(s), surface/viewport, and a stable selector or visible text anchor.
          Use the ghost stack for visual alignment, the difference view for changed pixels, and geometry drift for stable-element movement. A difference image proves change, not that the change is wrong. Look for actual opportunities in hierarchy, typography, measure, leading,
          whitespace, alignment, grouping, density, proportion, responsive composition,
          affordance, and decorative noise. Do not stop at "technically valid".
          Treat one-pixel alignment drift, inconsistent spacing, typography, component vocabulary, optical centering, baseline rhythm, density, and responsive composition as real defects when the rendered evidence supports it.

          #{HOSTILE_VISUAL_AUDIT}

          #{Master::Design::VisualLanguage.context(captures)}

          #{composition_variant_context(captures)}

          #{rows.join("\n")}
          #{drift_rows.join("\n")}
          #{graph&.context}
          Source anchors: #{mapped.join(", ")}
        TEXT
      end

      def file_and_line_for(selector, text_anchor, sources, anchors)
        file = selector && anchors[selector]
        file ||= source_file_for_text(text_anchor, sources)
        return [nil, nil] unless file && sources.include?(file)

        [file, selector ? source_line(file, selector) : source_text_line(file, text_anchor)]
      end

      def finding_for(pick, sources, anchors)
        surface = pick[SURFACE_RE, 1]&.strip
        viewport = pick[VIEWPORT_RE, 1]&.strip
        selector = pick[SELECTOR_RE]
        text_anchor = pick[TEXT_ANCHOR_RE, 1]&.strip
        laws = pick[LAW_RE, 1]&.split(/[,\s]+/).map(&:strip).reject(&:empty?).select { |id| Master::Fix::VisualUsability.ids.include?(id) }
        return unless surface && viewport && (selector || text_anchor) && laws.any?

        file, line = file_and_line_for(selector, text_anchor, sources, anchors)
        return unless file && line

        {
          rule: RULE_ID,
          file:,
          line:,
          severity: :warning,
          confidence: 1.0,
          message: "Rendered visual refinement: #{pick} — #{surface} / #{viewport} — laws: #{laws.join(", ")}",
          fix: "Use the attached rendered evidence as ground truth. Make the smallest source change that materially improves the cited visual issue while preserving accessibility, semantics and responsive behavior.",
        }
      rescue StandardError
        nil
      end

      def source_file_for_text(text, sources)
        return unless text && !text.empty?

        sources.find do |path|
          File.foreach(path, encoding: "UTF-8").any? { |line| line.include?(text) }
        end
      rescue StandardError
        nil
      end

      def source_line(path, selector)
        File.foreach(path, encoding: "UTF-8").with_index(1) do |line, index|
          return index if line.include?(selector)
        end
      rescue StandardError
        nil
      end

      def source_text_line(path, text)
        return unless text && !text.empty?

        File.foreach(path, encoding: "UTF-8").with_index(1) do |line, index|
          return index if line.include?(text)
        end
      rescue StandardError
        nil
      end

      def source_file?(path)
        File.file?(path) && SOURCE_EXTENSIONS.include?(File.extname(path).downcase)
      end

      def safe_slug(value) = value.to_s.gsub(/[^a-zA-Z0-9._-]+/, "_")
      def graph_coverage(surfaces, captures)
        expected = Array(surfaces).map(&:id)
        actual = captures.map { |capture| capture[:surface].id }
        { expected:, captured: actual, missing: expected - actual, ratio: expected.empty? ? 1.0 : actual.uniq.length.to_f / expected.uniq.length }
      end

      def rails_target?(target)
        relative = repo_relative(target)
        relative == "RAILS" || relative.start_with?("RAILS/")
      end

      # /fix passes MASTER's own directory, so the repository is its parent.
      # "../.." climbed out of pub4 altogether: RAILS then read as
      # "pub4/RAILS", applicable? said no, and the visual pass (composition
      # probes, ghost stack, contact sheet) never ran inside /fix.
      def repo_root
        return @root unless File.basename(@root) == "MASTER"

        File.expand_path("..", @root)
      end

      def repo_relative(target)
        raw = target.to_s
        absolute = raw.start_with?("/") ? File.expand_path(raw) : File.expand_path(raw, repo_root)
        absolute.delete_prefix("#{repo_root}/")
      end
    end
  end
end
