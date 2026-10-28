# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "layout_score_tokens"
require_relative "transaction"
require_relative "write_guard"

module Master
  module Fix
    # A deterministic pass that runs before any model sees a stylesheet: it
    # proposes rewrites of off-scale margin, padding, gap, font-size and
    # border-radius lengths to the nearest declared design token. It reads the
    # tokens from LayoutScoreTokens and invents none; it never touches colours
    # or font families; it leaves a value alone when two tokens are equally
    # near, when the distance exceeds the tolerance, or when the length sits in
    # calc()/clamp()/min()/max(), a media or container query, a multi-line
    # declaration, or a line marked `scale: ok`.
    #
    # Findings are advisory (law SCALE_SNAP) and carry the exact before/after
    # line. propose writes nothing but a dry-run report; apply writes only
    # through WriteGuard inside a Transaction, and keeps a file's rewrite only
    # when the re-render hook says no layout score dropped.
    module ScaleSnap
      LAW_ID = "SCALE_SNAP"
      TOLERANCE_PX = { space: 2.0, font: 1.0, radius: 2.0 }.freeze
      PROPERTY = {
        /\A(margin|padding)(-(top|right|bottom|left|inline|block)(-(start|end))?)?\z/ => :space,
        /\A(row-|column-)?gap\z/ => :space,
        "font-size" => :font,
        /\Aborder(-(top|bottom|start|end)-(left|right|start|end))?-radius\z/ => :radius,
      }.freeze
      DECLARATION = /\A(\s*)([a-z-]+)(\s*:\s*)([^;{}]+?)(\s*;.*)\z/.freeze
      LENGTH = /(?<![\w$#.-])(-?\d*\.?\d+)(px|rem)(?![\w%])/.freeze
      CONTEXT_FUNCTIONS = /\b(calc|clamp|min|max)\(|\$|#\{/.freeze
      OPT_OUT = %r{(scale|snap):\s*ok}.freeze
      AT_CONTEXT = /@(media|container|supports)\b/.freeze
      EXTENSIONS = %w[.css .scss].freeze

      module_function

      def dir(root) = File.join(root, "MASTER", ".master", "scale_snap")

      def tolerance(kind)
        override = ENV["MASTER_SCALE_SNAP_TOLERANCE_PX"]
        override ? Float(override) : TOLERANCE_PX.fetch(kind)
      end

      def stylesheets(root)
        Dir[File.join(root, "RAILS", "**", "app", "assets", "stylesheets", "**", "*")]
          .select { |path| EXTENSIONS.include?(File.extname(path)) && File.file?(path) && !path.include?("/vendor/") }.sort
      end

      # Findings for the given stylesheets (default: every RAILS stylesheet).
      def propose(root:, files: nil, tokens: LayoutScoreTokens.load(root), media: false)
        Array(files || stylesheets(root)).flat_map { |path| scan(path, tokens:, media:, root:) }
      end

      def scan(path, tokens:, media: false, root: nil)
        findings = []
        context = []
        File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
          track(line, context)
          next if (!media && context.any? { |c| c == :query }) || line.match?(OPT_OUT) || line.match?(CONTEXT_FUNCTIONS)

          finding = snap_line(line, tokens) or next
          findings << finding.merge(law: LAW_ID, file: path, line: number, severity: :info, advisory: true,
                                    message: "off-scale #{finding[:kind]}: #{finding[:before].strip} -> #{finding[:after].strip}",
                                    fix: "Replace with the nearest design token.")
        end
        findings
      rescue Errno::ENOENT, ArgumentError
        []
      end

      # Brace stack: :query for a media/container/supports block, :block otherwise.
      def track(line, context)
        opens = line.count("{")
        opens.times { context << (line.match?(AT_CONTEXT) ? :query : :block) }
        line.count("}").times { context.pop }
      end

      def snap_line(line, tokens)
        m = line.chomp.match(DECLARATION) or return
        kind = PROPERTY.find { |pattern, _| pattern === m[2] }&.last or return
        changed = false
        value = m[4].gsub(LENGTH) do
          match = Regexp.last_match
          replaced = snap_length(match, kind, tokens) unless nested?(match.pre_match)
          changed ||= !replaced.nil?
          replaced || match[0]
        end
        return unless changed

        { kind: kind.to_s, before: line.rstrip, after: "#{m[1]}#{m[2]}#{m[3]}#{value}#{m[5]}".rstrip }
      end

      # A length inside var(), env() or any function is a fallback or an input
      # to something else, not a declared value.
      def nested?(before) = before.count("(") > before.count(")")

      def snap_length(match, kind, tokens)
        amount = match[1].to_f
        px = match[2] == "rem" ? amount * LayoutScoreTokens::REM_PX : amount
        return if px.abs.zero?

        list = { space: tokens.space, font: tokens.font, radius: tokens.radius }.fetch(kind)
        target = unambiguous(list, px.abs, tolerance(kind)) or return
        signed = px.negative? ? -target.px : target.px
        literal = literal(signed, match[2])
        target.name && !px.negative? ? "var(#{target.name}, #{literal})" : literal
      end

      # The single nearest token strictly off the value and inside the
      # tolerance; nil when on-scale, out of range, or tied between two.
      def unambiguous(list, px, tolerance)
        ranked = list.map(&:px).uniq.sort_by { |v| (v - px).abs }
        best = ranked.first
        return if best.nil? || (best - px).abs < 0.01 || (best - px).abs > tolerance
        return if ranked[1] && ((ranked[1] - px).abs - (best - px).abs).abs < 0.01

        list.select { |t| t.px == best }.min_by { |t| t.name ? 0 : 1 }
      end

      def literal(px, unit)
        number = unit == "rem" ? px / LayoutScoreTokens::REM_PX : px
        "#{number.round(4).to_s.sub(/\.0\z/, "")}#{unit}"
      end

      # Dry-run report beside the other MASTER state; returns its path.
      def report(findings, root:)
        FileUtils.mkdir_p(dir(root))
        path = File.join(dir(root), "report.json")
        rows = findings.map { |f| f.slice(:file, :line, :kind, :before, :after).merge(file: f[:file].delete_prefix("#{root}/")) }
        File.write(path, JSON.pretty_generate("at" => Time.now.utc.iso8601, "count" => rows.size, "findings" => rows))
        path
      end

      # Applies findings file by file. `rescore` is the re-render hook: called
      # with the changed path, it returns true when no layout score dropped.
      # Without one nothing is written, since an unchecked rewrite is a guess.
      def apply(findings, root:, rescore: nil, guard: WriteGuard.default)
        return { applied: 0, refused: findings.size, reason: "no re-render hook" } unless rescore

        outcome = Hash.new(0)
        findings.group_by { |f| f[:file] }.each do |path, rows|
          outcome[apply_file(path, rows, root:, rescore:, guard:)] += 1
        end
        outcome
      end

      def apply_file(path, rows, root:, rescore:, guard:)
        old = File.read(path, encoding: "UTF-8")
        lines = old.lines
        rows.each { |f| lines[f[:line] - 1] = f[:after] + "\n" if lines[f[:line] - 1]&.rstrip == f[:before] }
        updated = lines.join
        return :stale if updated == old
        return :guard_refused if guard.verdict(path:, content: updated).blocked?

        transaction = Transaction.new(root:, paths: [path]).begin!
        begin
          File.write(path, updated)
          transaction.observe!
          kept = rescore.call(path)
        rescue StandardError
          transaction.rollback!
          raise
        end
        # finalize! answers a Result either way; an err one is not a kept rewrite.
        return(transaction.finalize!.ok? ? :applied : :finalize_failed) if kept

        transaction.rollback!
        :score_dropped
      end
    end
  end
end
