# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"

module Deploy
  # Mechanical fixes for rendered-geometry findings.
  #
  # A geometry failure names a *rendered selector*, not a source file, so
  # GateAutofix.extract_path cannot find anything to patch. Rewriting whichever
  # SCSS rule happens to match would be a guess — the cascade, not any single
  # declaration, produced the box. So the fix is additive and quarantined: one
  # generated block at the end of each app's application.scss, between two
  # marker comments, always reviewable as a diff and always revertable by
  # deleting the block. It lives in the one stylesheet because each app has one
  # by the operator's decision; a second generated file would be a second.
  module GeometryAutofix
    RAILS_ROOT = File.expand_path("../..", __dir__)
    OPEN = "// Deploy::GeometryAutofix begin — generated, do not hand-edit"
    CLOSE = "// Deploy::GeometryAutofix end"
    HEADER = <<~SCSS
      // Each rule below corrects a violation measured in a real browser
      // (rendered box under the Fitts floor, or content spilling past the
      // viewport). Regenerated on every autofix round; delete this block to
      // revert.
      //
      // If a rule here is wrong, the fix is to correct the *originating* rule
      // and let this block shrink — not to edit the block.
    SCSS

    module_function

    def entry_path(app)
      File.join(RAILS_ROOT, app, "app", "assets", "stylesheets", "application.scss")
    end

    # findings: [{ app:, selector:, kind: :touch|:overflow, detail: }]
    # Returns the number of files written.
    def apply(findings, dry: false)
      by_app = Array(findings).group_by { |f| f[:app] }
      written = 0
      by_app.each do |app, rows|
        path = entry_path(app)
        next unless File.file?(path)

        source = File.read(path)
        # Merge, do not replace. Each round measures the page with this block
        # already applied, so a rule that WORKS produces no finding and was
        # therefore absent from `rows` — and a plain re-render dropped it.
        # Observed 2026-08-07: a round that found one new overflow rewrote the
        # fixes to that rule alone and deleted a load-bearing 44px touch fix, so
        # the next round measured the touch violation again, re-added it, and
        # dropped the overflow rule. It oscillated until max_rounds, and
        # whichever half was missing at that moment is what shipped.
        block = render(merge_rows(existing_rows(source), rows))

        # Findings repeat per viewport and render() dedupes by selector, so
        # report what actually lands in the block, not the finding count.
        count = block.lines.count { |line| line.include?("{") }
        # A header and a list of comments is not a fix. On 2026-08-24 a run wrote
        # a generated layer containing no rules at all, resurrecting one that had
        # been deliberately retired at 90ef51aa6 ("retire the geometry autofix
        # layer into the stylesheets that own the rules"). An empty block reads
        # as an active fix layer and holds nothing, and a round that found
        # nothing must not empty an existing one.
        next if count.zero?

        body = with_block(source, block)
        next if body == source

        if dry
          Kernel.warn "  [autofix dry] would write #{path.sub(RAILS_ROOT + '/', '')} (#{count} rule(s))"
          written += 1
          next
        end

        File.write(path, body)
        Kernel.warn "  [autofix] wrote #{path.sub(RAILS_ROOT + '/', '')} (#{count} rule(s))"
        written += 1
      end
      rebuild_css(by_app.keys) if written.positive? && !dry
      written
    end

    # The generated block, if the stylesheet carries one.
    def generated_block(source)
      source[/^#{Regexp.escape(OPEN)}\n.*?^#{Regexp.escape(CLOSE)}\n?/m]
    end

    # The stylesheet with its generated block replaced, or appended at the end
    # where it is the last word in the cascade. A @use has to precede every
    # rule, and the block adds no @use, so the end is always a legal place.
    def with_block(source, block)
      wrapped = "#{OPEN}\n#{block}#{CLOSE}\n"
      existing = generated_block(source)
      return source.sub(existing) { wrapped } if existing

      "#{source.rstrip}\n\n#{wrapped}"
    end

    # Rules already in the generated block, read back as rows so a merge is a
    # plain union rather than a text splice. The block only ever holds the two
    # shapes render() emits, so parsing it is reading our own output.
    def existing_rows(source)
      block = generated_block(source)
      return [] unless block

      kind = nil
      detail = nil
      # chomp first: lines keeps the newline and \z is absolute end-of-string,
      # so /\A\/\/ (.+)\z/ silently never matched a detail comment.
      block.lines(chomp: true).filter_map do |line|
        case line
        when /\A\/\/ --- (\w+) ---/ then kind = Regexp.last_match(1).to_sym; next
        when /\A\/\/ Deploy::GeometryAutofix/ then next
        when /\A\/\/ (.+)\z/        then detail = Regexp.last_match(1).strip; next
        when /\A(.+?) \{/
          selector = Regexp.last_match(1).strip
          row = { selector: selector, kind: kind, detail: detail, parsed: true }
          detail = nil
          kind ? row : nil
        else
          detail = nil
          next
        end
      end
    end

    # New findings win on detail (they carry this round's measurement), but a
    # selector present in either source survives.
    def merge_rows(old_rows, new_rows)
      fresh = new_rows.map { |r| [[r[:kind], css_selector(r[:selector])], r] }.to_h
      kept = old_rows.reject { |r| fresh.key?([r[:kind], r[:selector]]) }
      kept + new_rows
    end

    def render(rows)
      out = +HEADER
      rows.group_by { |r| r[:kind] }.each do |kind, group|
        out << "\n// --- #{kind} ---\n"
        group.uniq { |r| r[:selector] }.sort_by { |r| r[:selector] }.each do |row|
          # A row read back from the file already holds a CSS selector.
          # css_selector is not idempotent — it re-splits on ">" and rejoins
          # with " > ", so a second pass turns "a > b" into "a  >  b" and the
          # file churns on every round.
          sel = row[:parsed] ? row[:selector] : css_selector(row[:selector])
          next unless sel

          out << "// #{row[:detail]}\n" if row[:detail]
          out << case kind
                 when :touch
                   "#{sel} { min-height: 44px; min-width: 44px; }\n"
                 when :overflow
                   "#{sel} { max-width: 100%; overflow-wrap: anywhere; }\n"
                 else
                   ""
                 end
        end
      end
      out
    end

    # The probe emits descendant paths like "div.a>ul.b>li.c". Only the last
    # step is needed as a selector, and an id anywhere makes the rest noise.
    def css_selector(raw)
      s = raw.to_s.sub(/\[\d+\]\z/, "").strip
      return nil if s.empty?

      parts = s.split(">")
      idx = parts.rindex { |p| p.start_with?("#") }
      parts = parts[idx..] if idx
      tail = parts.last(2).join(" > ")
      return nil if tail.match?(/\A[a-z]+\z/) # bare `div` is too broad to patch

      tail
    end

    # A CSS patch is invisible to the next measurement until the SCSS is
    # compiled. Say so loudly when we cannot rebuild rather than letting a
    # remeasure "fail" for a reason that has nothing to do with the fix.
    def rebuild_css(apps)
      builder = File.join(RAILS_ROOT, "tools", "build_all_css.rb")
      unless File.file?(builder)
        Kernel.warn "  [autofix] tools/build_all_css.rb missing — CSS patch will not be visible until rebuilt"
        return false
      end

      apps.each do |app|
        # A failed build can still write a truncated stylesheet — observed
        # taking bsdports' application.css from 52KB to 733 bytes, which
        # unstyles the whole app. An autofixer must never leave the app worse
        # than it found it, so keep the previous bytes and put them back if the
        # rebuild collapses the output.
        built = built_css_path(app)
        before = File.file?(built) ? File.binread(built) : nil

        # build_all_css shares a token/font directory across apps and has been
        # observed failing transiently when several rebuilds run back to back.
        # One retry; anything that survives it is reported, never swallowed.
        err = nil
        2.times do |attempt|
          _out, err, status = Open3.capture3(RbConfig.ruby, builder, "--app", app)
          if status.success?
            Kernel.warn "  [autofix] rebuilt #{app} CSS#{attempt.positive? ? " (retry)" : ""}"
            err = nil
            break
          end
          sleep 0.5 if attempt.zero?
        end

        if collapsed?(before, built)
          File.binwrite(built, before)
          Kernel.warn "  [autofix] #{app} CSS rebuild collapsed the stylesheet " \
                      "(#{before.bytesize} → #{File.size(built)} bytes) — restored the previous build"
          next
        end
        if err
          Kernel.warn "  [autofix] CSS rebuild failed for #{app} after retry — remeasure will not see the patch"
          Kernel.warn "            #{err.to_s.lines.last(2).map(&:strip).join(' / ')}"
          next
        end

        warn_if_server_stale(app)
      end
      true
    end

    # Writing SCSS and rebuilding is not enough: a running server can keep
    # serving a previously fingerprinted asset, so the remeasure grades CSS the
    # patch never reached and the gate reports "still failing" for a fix that is
    # actually correct. Detect that and say which it is.
    MARKER = "min-width:44px"

    def warn_if_server_stale(app)
      port = app_port(app)
      return unless port

      served = served_stylesheet(port)
      return if served.nil?
      return if served.include?(MARKER) || served.include?("min-width: 44px")

      Kernel.warn "  [autofix] #{app} is serving a stale stylesheet — the patch is in " \
                  "app/assets/builds/application.css but not in the asset the app returns."
      Kernel.warn "            Restart #{app} (or clear public/assets/.manifest.json) before trusting a remeasure."
    end

    def built_css_path(app)
      File.join(RAILS_ROOT, app, "app", "assets", "builds", "application.css")
    end

    # A legitimate rebuild adds bytes; it never removes most of them. Half the
    # previous size is far outside normal variation for a minified bundle.
    def collapsed?(before, built)
      return false if before.nil? || before.bytesize < 2_000
      return true unless File.file?(built)

      File.size(built) < before.bytesize / 2
    end

    def app_port(app)
      require_relative "../../../OPENBSD/lib/deploy_inventory"
      Inventory.new(root: File.expand_path("..", RAILS_ROOT)).apps.find { |a| a.name == app }&.port
    rescue StandardError # scan: intentional — no inventory means no port; the autofix declines to guess
      nil
    end

    def served_stylesheet(port)
      require "net/http"
      html = Net::HTTP.get(URI("http://127.0.0.1:#{port}/"))
      href = html[%r{/assets/application[^"']*\.css}]
      return nil unless href

      Net::HTTP.get(URI("http://127.0.0.1:#{port}#{href}"))
    rescue StandardError # scan: intentional — an unreachable page yields no geometry; the caller reports it
      nil
    end
  end
end
