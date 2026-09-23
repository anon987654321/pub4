# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require_relative "../review/council/critique"

module Master
  module Fix
    # Rendered UI is evidence, not a second scanner. GeometryProbe owns the
    # browser; Council owns visual judgement; RuleLoop owns the edit.
    class VisualPass
      RULE_ID = "RENDERED_VISUAL_REFINEMENT"
      SOURCE_EXTENSIONS = %w[.css .scss .erb .html .htm .js .ts].freeze
      MAX_SURFACES = Integer(ENV.fetch("MASTER_VISUAL_SURFACES_PER_PASS", "8"))
      MAX_FILES = 12
      SELECTOR_RE = /#[A-Za-z][\w-]*|\.[A-Za-z_][\w-]*(?:[-_][\w-]*)*/.freeze
      TEXT_ANCHOR_RE = /\b(?:visible\s+text(?:\s+anchor)?|text\s+anchor)\s*[:=]\s*["“]([^"”\n]+)["”]/i.freeze
      # %r{} delimiters, not /.../ -- the character class needs a literal /
      # (surface ids are paths, e.g. brgen/dating), which /.../ regex literals
      # cannot hold unescaped. This is why the file has never actually
      # parsed since it was written; found while merging, not introduced now.
      SURFACE_RE = %r{\bsurface\s*[:=]\s*([A-Za-z0-9_./-]+)\b}i.freeze
      VIEWPORT_RE = /\bviewport\s*[:=]\s*([A-Za-z0-9_-]+)\b/i.freeze
      Rule = Data.define(:id) do
        def severity = :warning
      end

      attr_reader :dir

      def initialize(agent:, root:, bus: nil)
        @agent = agent
        @root = root
        @bus = bus
        @dir = nil
      end

      def applicable?(target)
        relative = repo_relative(target)
        relative == "RAILS" || relative.start_with?("RAILS/") ||
          relative == "MASTER/web" || relative.start_with?("MASTER/web/")
      end

      def run(target:, files:, pass:)
        return Result.ok(state: :not_applicable) unless applicable?(target)
        raise "visual review has no agent" unless @agent

        require File.expand_path("../../../RAILS/gates/support/geometry_probe", __dir__)

        @dir = Dir.mktmpdir("master-visual")
        surfaces = selected_surfaces(target:, pass:)
        return Result.err("rendered visual review: INCONCLUSIVE — no declared surfaces", category: :inconclusive) if surfaces.empty?

        captures = capture_surfaces(surfaces)
        return Result.err("rendered visual review: INCONCLUSIVE — no surface was measured", category: :inconclusive) if captures.empty?

        sources, anchors = candidate_sources(target:, files:, captures:)
        return Result.err("rendered visual review: INCONCLUSIVE — no frontend source anchor", category: :inconclusive) if sources.empty?

        review_captures(captures, sources, anchors, pass)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_pass", event_bus: @bus)
        Result.err("rendered visual review: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
      end

      def cleanup
        return unless @dir && File.directory?(@dir)

        FileUtils.remove_entry(@dir)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "fix.visual_pass.cleanup", event_bus: @bus)
      ensure
        @dir = nil
      end

      private

      def capture_surfaces(surfaces)
        captures = []
        Deploy::GeometryProbe.with_browser(root: repo_root, warm: surfaces) do |cdp|
          surfaces.each do |surface|
            payload = Deploy::GeometryProbe.walk(cdp, surface)
            next unless Deploy::GeometryProbe.ok?(payload)

            shot = File.join(@dir, "#{safe_slug(surface.id)}.png")
            cdp.screenshot(shot)
            captures << { surface:, payload:, screenshot: shot }
          end
        end
        captures
      end

      def run_critique(captures, sources, anchors)
        representative = captures.max_by { |capture| visual_signal(capture[:payload]) }
        context = build_context(captures, anchors)
        image = { path: representative[:screenshot], name: "rendered-ui.png", mime: "image/png" }
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

      def review_captures(captures, sources, anchors, pass)
        critique, image = run_critique(captures, sources, anchors)
        return Result.err("rendered visual review: INCONCLUSIVE — #{critique.message}", category: :inconclusive) if critique.err?

        picks = Array(critique.value![:cherry_picks]).map(&:to_s).reject(&:empty?)
        findings = picks.filter_map { |pick| finding_for(pick, sources, anchors) }
        @bus&.publish("fix_loop:visual_review", pass:, surfaces: captures.map { |c| c[:surface].id }, findings: findings.size)
        Result.ok(
          state: findings.empty? ? :clean : :findings,
          findings:,
          image:,
          coverage: captures.map { |c| c[:surface].id },
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

        extras = rows.reject { |s| core.include?(s) }.sort_by { |s| [s.app, s.label, s.viewport] }
        return (core + extras).first(MAX_SURFACES) if core.size >= MAX_SURFACES

        offset = ((pass.to_i - 1) * MAX_SURFACES) % [extras.size, 1].max
        (core + extras.rotate(offset)).first(MAX_SURFACES)
      end

      def visual_signal(payload)
        visual = payload["visual"] || {}
        first = visual["first_screen"] || {}
        first["small_text"].to_i * 10 +
          first["centered_long_text"].to_i * 8 +
          [first["interactive"].to_i - 7, 0].max * 4 +
          first["largest_element_area_ratio"].to_f
      end

      def candidate_sources(target:, files:, captures:)
        candidates = Array(files).select { |path| source_file?(path) }.uniq
        tokens = captures.flat_map do |capture|
          Array(capture[:payload]["elements"]).flat_map do |element|
            [element["key"], element["aria"]].compact
          end
        end.map { |token| token.to_s[/#[\w-]+|\.[\w-]+/] }.compact.uniq.first(50)

        anchors = {}
        tokens.each { |token| anchors[token] = grep_source(token) }
        candidates = (candidates + anchors.values).compact.uniq.first(MAX_FILES)
        candidates = fallback_sources(target) if candidates.empty?
        [candidates.first(MAX_FILES), anchors]
      end

      def grep_source(token)
        out, status = Open3.capture2("git", "-C", repo_root, "grep", "-l", "--fixed-strings", token,
                                     "--", "RAILS", "MASTER/web")
        return unless status.success?

        out.lines.map(&:strip).map { |rel| File.join(repo_root, rel) }
           .find { |path| source_file?(path) }
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
          "first-screen text=#{first["text_blocks"]}, interactive=#{first["interactive"]}, ",
          "largest_area=#{first["largest_element_area_ratio"]}, small_text=#{first["small_text"]}, ",
          "centered_long_text=#{first["centered_long_text"]}",
          "type sizes=#{type["distinct_font_sizes"]&.first(8)}, body median=#{type["body_median_px"]}, ",
          "leading=#{type["line_height_min_px"]}-#{type["line_height_max_px"]}",
          "scroll/client=#{payload["scroll_width"]}/#{payload["client_width"]}",
        ].join(" ")
      end

      def build_context(captures, anchors)
        rows = captures.map { |capture| context_row(capture) }
        mapped = anchors.values.compact.uniq.first(12)
        <<~TEXT
          RENDERED EVIDENCE
          The attached screenshot is a real browser capture. The measurements below were
          collected from the same browser session across the listed surfaces.
          Judge the render first. Source is supporting evidence.
          Look for actual opportunities in hierarchy, typography, measure, leading,
          whitespace, alignment, grouping, density, proportion, responsive composition,
          affordance, and decorative noise. Do not stop at "technically valid".
          Every actionable issue must name its surface/viewport and a stable selector or
          visible text anchor.

          #{rows.join("\n")}
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
        return unless surface && viewport && (selector || text_anchor)

        file, line = file_and_line_for(selector, text_anchor, sources, anchors)
        return unless file && line

        {
          rule: RULE_ID,
          file:,
          line:,
          severity: :warning,
          confidence: 1.0,
          message: "Rendered visual refinement: #{pick} — #{surface} / #{viewport}",
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
      def repo_root = File.expand_path("../..", @root)

      def repo_relative(target)
        raw = target.to_s
        absolute = raw.start_with?("/") ? File.expand_path(raw) : File.expand_path(raw, repo_root)
        absolute.delete_prefix("#{repo_root}/")
      end
    end
  end
end
