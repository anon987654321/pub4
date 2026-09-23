# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "tmpdir"

module Master
  module Fix
    # Bridges the repo's rendered measurement substrate into the same council
    # and RuleLoop already used for source fixes. It never drives Chrome itself:
    # RAILS/gates/visual_evidence.rb owns browser capture and returns evidence.
    class RenderedReview
      RULE = Data.define(:id) do
        def severity = :warning
      end
      RULE_ID = "RENDERED_VISUAL_REFINEMENT"
      MAX_FILES = 12
      SELECTOR_RE = /#[A-Za-z][\w-]*|\.[A-Za-z_][\w-]*(?:[-_][\w-]+)*/.freeze
      SOURCE_EXTENSIONS = %w[.css .scss .js .ts .erb .html .htm .rb].freeze

      attr_reader :dir

      def initialize(agent:, root:, bus: nil)
        @agent = agent
        @root = root
        @bus = bus
        @dir = nil
      end

      def applicable?(target)
        relative = repo_relative(target)
        relative == "MASTER/web" || relative.start_with?("MASTER/web/") ||
          relative == "RAILS" || relative.start_with?("RAILS/")
      end

      def run(target:, files:, pass:)
        return Result.ok(state: :not_applicable) unless applicable?(target)

        @dir = Dir.mktmpdir("master-visual-")
        capture = capture_evidence(target:, pass:)
        unless capture[:ok]
          message = "rendered visual review: INCONCLUSIVE — #{capture[:message]}"
          @bus&.publish("fix_loop:visual_inconclusive", target:, pass:, message:)
          return Result.err(message, category: :inconclusive)
        end

        manifest = capture[:manifest]
        image_path = manifest["sheet"]
        return Result.err(
          "rendered visual review: INCONCLUSIVE — no screenshot evidence",
          category: :inconclusive,
        ) unless image_path && File.file?(image_path)

        image = { path: image_path, name: "visual-contact-sheet.png", mime: "image/png" }

        source_files, anchors = candidate_sources(target:, files:, manifest:)
        return Result.err("rendered visual review: INCONCLUSIVE — screenshot has no source anchor", category: :inconclusive) if source_files.empty?

        context = evidence_context(manifest, anchors)
        critique = Master::Review::Council::Critique.new(
          mode: :ui,
          agent: @agent,
          event_bus: @bus,
          files: source_files,
          visual_image: image,
          visual_context: context,
        ).run
        return Result.err("rendered visual review: INCONCLUSIVE — #{critique.message}", category: :inconclusive) if critique.err?

        picks = Array(critique.value![:cherry_picks]).map(&:to_s).reject(&:empty?)
        findings = picks.filter_map { |pick| finding_for(pick, source_files, anchors, manifest) }
        state = findings.empty? ? :clean : :findings
        @bus&.publish("fix_loop:visual_review", target:, pass:, surfaces: manifest["entries"].size,
                                               findings: findings.size)
        Result.ok(state:, findings:, image:, files: source_files, manifest:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rendered_review", event_bus: @bus)
        Result.err("rendered visual review: INCONCLUSIVE — #{e.class}: #{e.message}", category: :inconclusive)
      end

      def cleanup
        return unless @dir && File.directory?(@dir)

        FileUtils.remove_entry(@dir)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rendered_review.cleanup", event_bus: @bus)
      ensure
        @dir = nil
      end

      private

      def capture_evidence(target:, pass:)
        kind = repo_relative(target).start_with?("MASTER/web") ? "MASTER" : "RAILS"
        command = [
          *ruby_command,
          File.join(repo_root, "RAILS", "gates", "visual_evidence.rb"),
          "--target", kind,
          "--out", @dir,
          "--pass", pass.to_i.to_s,
        ]
        stdout, stderr, status = Open3.capture3(*command, chdir: repo_root)
        manifest_path = File.join(@dir, "manifest.json")
        return { ok: false, message: stderr.strip.lines.last.to_s } unless status.success? && File.file?(manifest_path)

        { ok: true, manifest: JSON.parse(File.read(manifest_path)) }
      end

      def ruby_command
        [RbConfig.ruby]
      end

      def candidate_sources(target:, files:, manifest:)
        candidates = Array(files).select { |path| source_file?(path) }.uniq
        tokens = Array(manifest["entries"]).flat_map do |entry|
          body = File.file?(entry["geometry"]) ? File.read(entry["geometry"], encoding: "UTF-8") : ""
          body.scan(SELECTOR_RE)
        end.uniq.first(60)

        anchors = {}
        tokens.each do |token|
          anchors[token] = grep_sources(token).first
        end

        mapped = anchors.values.compact.uniq
        candidates = (candidates + mapped).uniq.first(MAX_FILES)
        candidates = fallback_sources(target) if candidates.empty?
        [candidates.first(MAX_FILES), anchors]
      end

      def repo_root = File.expand_path("../..", @root)

      def repo_relative(target)
        raw = target.to_s
        absolute = if raw.start_with?("/")
                     File.expand_path(raw)
                   elsif raw.start_with?("MASTER", "RAILS")
                     File.expand_path(raw, repo_root)
                   else
                     File.expand_path(raw, @root)
                   end
        absolute.delete_prefix("#{repo_root}/")
      end

      def source_file?(path)
        File.file?(path) && SOURCE_EXTENSIONS.include?(File.extname(path).downcase)
      end

      def grep_sources(token)
        out, status = Open3.capture2(
          "git", "-C", repo_root, "grep", "-l", "--fixed-strings", token, "--", "RAILS", "web"
        )
        return [] unless status.success?

        out.lines.map { |line| File.join(repo_root, line.strip) }
             .select { |path| source_file?(path) }
             .first(4)
      rescue StandardError
        []
      end

      def fallback_sources(target)
        base = repo_relative(target)
        root = base.start_with?("MASTER/web") ? File.join(repo_root, "MASTER", "web") : File.join(repo_root, "RAILS")
        paths = Dir.glob(File.join(root, "**", "*"))
        paths.select { |path| source_file?(path) }
             .sort_by { |path| [path.include?("stylesheets") ? 0 : 1, path.length, path] }
             .first(MAX_FILES)
      end

      def evidence_context(manifest, anchors)
        entries = Array(manifest["entries"]).map do |entry|
          "surface #{entry["index"]}: #{entry["surface"]}, #{entry["viewport"]}, "             "#{entry["path"]}, #{entry["elements"]} visible measured elements, "             "#{entry["gaps"]} stacked gaps, #{entry["colors"]} text colors, "             "scroll/client width #{entry["scroll_width"]}/#{entry["client_width"]}"
        end
        mapped = anchors.values.compact.uniq.first(12)
        <<~TEXT
          RENDERED EVIDENCE
          The attached image is a real browser capture, not an illustration or mockup.
          Contact-sheet order is the numbered surface order below. Judge what is visibly
          rendered first; source is supporting evidence. Do not invent problems that the
          screenshot or geometry cannot support. Every actionable finding must name the
          surface/viewport and a stable DOM selector or visible text anchor.

          #{entries.join("
")}
          Candidate source anchors: #{mapped.join(", ")}
        TEXT
      end

      def finding_for(pick, source_files, anchors, manifest)
        selector = pick[SELECTOR_RE, 0]
        file = selector && anchors[selector]
        file ||= source_files.find { |path| pick.downcase.split(/\W+/).any? { |word| word.length > 4 && File.read(path, encoding: "UTF-8").downcase.include?(word) } }
        file ||= source_files.first
        return unless file

        surface = pick[/surface\s+[^,;]+/i, 0]
        selector_line = selector && source_line(file, selector)
        {
          rule: RULE_ID,
          file: file,
          line: selector_line || 1,
          severity: :warning,
          confidence: 1.0,
          message: "Rendered visual finding: #{pick}#{surface ? "" : " — anchor this to the attached rendered evidence"}",
          fix: "Use the attached browser screenshot and geometry evidence as ground truth. "                "Make the smallest source change that improves the cited visual issue without "                "inventing a new design system or regressing accessibility, semantics, or responsiveness.",
        }
      def source_line(path, selector)
        File.foreach(path).with_index(1) { |line, index| return index if line.include?(selector) }
      rescue StandardError
        nil
      end
    end
  end
end
