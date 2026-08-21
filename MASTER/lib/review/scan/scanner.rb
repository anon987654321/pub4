# frozen_string_literal: true

require "etc"
require "open3"
require "timeout"
require_relative "cross_file_analysis"
require_relative "file_processor"


# ---- merged from lib/review/scan/scanner/progress_reporter.rb (one-file directory collapse, 2026-08-19) ----
module Master
  module Review
    module Scan
      class Scanner
        # Live scan progress: dmesg-style streaming status lines, checkpoint
        # snapshots, and completion events. Grouped apart from the core
        # scan/parallelism logic to keep Scanner itself under NO_GOD_CLASS's
        # 300-line ceiling -- a real separation (reporting vs scanning), not
        # just metric evasion; mixed-in modules live in their own ModuleNode
        # so this doesn't count against the including class's own span.
        module ProgressReporter
          private

          def reset_scan_progress(total, unit: nil)
            @scan_unit_seq = (@scan_unit_seq || -1) + 1
            name = unit || @through_scan_unit || "scan#{@scan_unit_seq}"
            @scan_progress = {
              total:,
              done: 0,
              violations: 0,
              dirty_files: 0,
              rules: Hash.new(0),
              unit: name,
              started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC),
            }
            $stdout.sync = true
            Master::Trace::Dmesg.attach(name, "mainbus0", "files=#{total} stream=on")
          end

          def emit_scan_progress(dir:, path:, file_result:)
            return unless @scan_progress

            findings = file_result.ok? ? Array(file_result.value!) : []
            count = findings.size
            rel = path.sub(dir, "").delete_prefix("/")
            rule_hits = findings.filter_map { |f| finding_rule_id(f) }

            done, total, viol_total, dirty, top = update_scan_progress_state(count, rule_hits)

            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @scan_progress[:started_at]
            eta_s = done.positive? ? ((elapsed / done) * (total - done)).round : nil
            unit = @scan_progress[:unit] || "scan0"

            log_scan_hit(unit:, done:, total:, rel:, count:, eta_s:)
            log_scan_checkpoint(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
            log_scan_completion(unit:, done:, total:, viol_total:, dirty:, elapsed:) if done == total
            @bus&.publish("scan:progress", done:, total:, path: rel, violations: count, eta_s:, top: top.to_h)
          end

          def update_scan_progress_state(count, rule_hits)
            @mutex.synchronize do
              sp = @scan_progress
              sp[:done] += 1
              sp[:violations] = sp[:violations].to_i + count
              sp[:dirty_files] = sp[:dirty_files].to_i + 1 if count.positive?
              tally_rule_hits(sp, rule_hits)
              [sp[:done], sp[:total], sp[:violations], sp[:dirty_files], sp[:rules].sort_by { |_, n| -n }.first(6)]
            end
          end

          # Canonical RuleDSL ids are uppercase, but some findings arrive with
          # a lowercase label (e.g. principle_map.yml's "detects:" taxonomy)
          # for the same underlying category -- tallying both casings
          # separately split one violation count into two lines in the live
          # "top=" summary (e.g. "long_line=440,LONG_LINE=440"). Normalize so
          # every distinct violation category earns exactly one slot.
          def tally_rule_hits(sp, rule_hits)
            rule_hits.each { |rid| sp[:rules][rid.upcase] += 1 }
          end

          # Per-file: only dirty files (signal), not clean-file spam.
          def log_scan_hit(unit:, done:, total:, rel:, count:, eta_s:)
            return unless count.positive?

            Master::Trace::Dmesg.status(
              unit,
              "hit #{done}/#{total} #{rel} +#{count}" \
              "#{eta_s && eta_s.positive? ? " eta=#{eta_s}s" : ""}",
            )
          end

          # Decision-grade checkpoints: progress + top rules so far.
          def log_scan_checkpoint(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
            step = checkpoint_step(total)
            return unless done == total || (done % step).zero?

            top_s = top.map { |rule, n| "#{rule}=#{n}" }.join(" ")
            Master::Trace::Dmesg.status(
              unit,
              "checkpoint #{done}/#{total} violations=#{viol_total} dirty_files=#{dirty}" \
              "#{eta_s && eta_s.positive? ? " eta=#{eta_s}s" : ""}" \
              " elapsed=#{elapsed.round}s" \
              "#{top_s.empty? ? "" : " top #{top_s}"}",
            )
            write_progress_snapshot(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
          end

          def log_scan_completion(unit:, done:, total:, viol_total:, dirty:, elapsed:)
            Master::Trace::Dmesg.kv(
              unit,
              complete: true, files: total, violations: viol_total,
              dirty_files: dirty, elapsed_s: elapsed.round
            )
          end

          def checkpoint_step(total)
            return 1 if total <= 10
            return 5 if total <= 50
            return 10 if total <= 100

            [25, (total / 10.0).ceil].max
          end

          def finding_rule_id(finding)
            return finding.rule.to_s if finding.respond_to?(:rule)
            return finding[:rule].to_s if finding.respond_to?(:[]) && finding[:rule]

            nil
          end

          def write_progress_snapshot(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
            root = defined?(Master::ROOT) ? Master::ROOT : Dir.pwd
            top_s = top.map { |rule, n| "#{rule}=#{n}" }.join(" ")
            text = [
              "phase: streaming #{unit}",
              "progress: #{done}/#{total} files",
              "violations: #{viol_total} dirty_files=#{dirty}",
              "elapsed_s: #{elapsed.round} eta_s: #{eta_s || "-"}",
              ("top: #{top_s}" unless top_s.empty?),
              "note: partial — full report lands after pass completes",
            ].compact.join("\n")
            # Quiet write — checkpoints already print top rules; avoid spam.
            if defined?(Master::CLI::ScanLive)
              Master::CLI::ScanLive.snapshot!(text, root:, note: "streaming checkpoint", announce: false)
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Scanner.write_progress_snapshot")
          end
        end
      end
    end
  end
end

module Master
  module Review
    module Scan
      class Scanner
        include ProgressReporter
        POOL_SIZE = [Etc.nprocessors, 8].min.freeze
        SCAN_GLOB = "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,json,md}".freeze
        SCAN_SINCE_EXT = /\.(rb|rake|gemspec|erb|yml|yaml|js|css|sh|zsh)\z/.freeze
        # `.cache` and `scratch` (2026-08-11): `cache` was listed and `.cache`
        # was not, which bin/gate already warned about in a comment rather than
        # fixing. `scratch` is the same shape — STUDIO/dilla/scratch holds a
        # demucs virtualenv, so `/scan ../STUDIO/dilla` walked 24,521 files,
        # about 5,000 of them pip's vendored copy of packaging, to reach the 36
        # Ruby files the tool is made of. Skipping both: 793 files in 38s, and
        # the findings are about dilla instead of about torch. Nothing under
        # either segment is git-tracked anywhere in this repo, so nothing under
        # either can be authored or refactored — and /fix descends the same
        # tree, so an autofix pass could rewrite a vendored Python package that
        # the next `pip install` silently reverts.
        SKIP_PATH_SEGMENTS = %w[
          .git vendor node_modules tmp log coverage .bundle storage cache dist build
          knowledge fixtures var .cache scratch
          site-packages venv .venv venv-demucs __pycache__
          # reports/ is generated output. Scanning it meant the top
          # COPY_PASTE_BLOCK findings were JSON manifests from three
          # screenshot-calibration runs, which share keys because they share a
          # schema — and the advice attached to them was "extract a module or
          # template". Nothing in here is authored, so nothing in here can be
          # refactored.
          reports
        ].freeze
        # Spelled relative to MASTER, and matched relative to whatever root the
        # scan was given — which are the same thing only when MASTER scans
        # itself. `bin/gate` and every cross-tree run pass the repo root, where
        # these paths arrive as `MASTER/web/public/face.runtime.js` and matched
        # nothing: the generated face runtime, the two bundles and the three
        # build were scanned, reported, and offered to /fix. face.runtime.js
        # opens with "do not edit by hand" and is rewritten by
        # assets:build_face_runtime, so a fix there survives until the next
        # build and then vanishes — the same loop the db/schema.rb note below
        # describes. Matching the MASTER-prefixed form too makes the list mean
        # the same thing from both roots.
        SKIP_RELATIVE_PATHS = %w[
          .master runtime web/public/assets web/script/three_build web/node_modules web/tmp web/log
          web/public/three.face.module.js web/public/face.runtime.js
          web/public/face.modules.bundle.js web/public/face_vision.bundle.js
        ].flat_map { |path| [path, "MASTER/#{path}"] }.freeze

        # Not authored anywhere: `builds/` is what dartsass compiles the tracked
        # _*.scss into, so every finding in it is a duplicate of one already
        # reported against the source, and fixing the copy is undone by the next
        # `bin/rails css:build`. shared/reference holds the original CodePen
        # sources kept for provenance and shipped by nothing, and lightgallery
        # arrived minified from jsDelivr.
        SKIP_PATH_PREFIXES = %w[
          RAILS/shared/reference
          STUDIO/dilla/archive
        ].freeze
        SKIP_PATH_FRAGMENTS = %w[
          app/assets/builds/
        ].freeze

        # Third-party assets checked in under public/ rather than vendor/, so the
        # `vendor` segment never matched them. lightgallery arrived minified from
        # jsDelivr and swiper is a `.min.css` bundle; both were reported for
        # touch-target size and missing prefers-reduced-motion, neither of which
        # anyone here can fix without forking the library. `.min.*` is the general
        # form of the same claim: minified means generated elsewhere.
        VENDORED_ASSET = %r{
          /public/(?:lightgallery|swiper[\w.-]*|photoswipe[\w.-]*)\.(?:css|js)\z
          | \.min\.(?:css|js)\z
        }x
        # Rails writes these; ActiveRecord::SchemaDumper does not emit a
        # frozen_string_literal magic comment, so FROZEN_STRING_LITERAL
        # (autofix: true) added one and the next `db:migrate` stripped it again.
        # That loop produced a spurious dirty db/schema.rb for whoever migrated
        # next, on a shared git index where a stray modification gets swept into
        # someone else's commit. Matched by suffix rather than prefix because
        # they sit under RAILS/<app>/, and the scan root is the repo.
        SKIP_PATH_SUFFIXES = %w[db/schema.rb db/structure.sql].freeze
        REQUIRED_DEPTH = :deep
        GIT_TIMEOUT_SECONDS = 5
        MAX_VIOLATION_OBJECTS = 100_000
        GC_EVERY_N_ITERATIONS = 5

        attr_reader :rules

        def self.skip_path?(path, root: nil)
          segments = relative_segments(path, root)
          return true if SKIP_PATH_SEGMENTS.any? { |segment| segments.include?(segment) }

          rel = relative_path(path, root)
          return true if SKIP_PATH_SUFFIXES.any? { |suffix| rel == suffix || rel.end_with?("/#{suffix}") }
          return true if SKIP_PATH_PREFIXES.any? { |prefix| rel == prefix || rel.start_with?("#{prefix}/") }
          return true if SKIP_PATH_FRAGMENTS.any? { |fragment| rel.include?(fragment) }
          return true if VENDORED_ASSET.match?(rel)

          SKIP_RELATIVE_PATHS.any? { |prefix| rel == prefix || rel.start_with?("#{prefix}/") }
        end

        def self.relative_segments(path, root)
          relative_path(path, root).split(File::SEPARATOR)
        end

        def self.relative_path(path, root)
          return path.to_s unless root

          expanded = File.expand_path(path)
          base = File.expand_path(root)
          return path.to_s unless expanded == base || expanded.start_with?("#{base}#{File::SEPARATOR}")

          expanded.delete_prefix(base).delete_prefix(File::SEPARATOR)
        end

        def initialize(rules: nil, event_bus: nil, file_sleep_s: 0)
          @rules = Array(rules)
          @bus = event_bus
          @mutex = Mutex.new
          @file_sleep_s = file_sleep_s.to_f
          @file_processor = FileProcessor.new(event_bus:)
        end

        # Preconditions: path must exist and scans must run at depth :deep.
        # MASTER is constitutionally deep-scan-only; callers needing a preview
        # should filter findings after scanning instead of weakening depth.
        def scan(path, depth: :deep, rules: nil)
          validate_depth!(depth)
          @file_processor.call(path:, depth:, rules: rules || active_rules(depth))
        end

        def scan_dir(dir, depth: :deep, glob: SCAN_GLOB, stream: false)
          validate_depth!(depth)
          paths = Dir.glob(File.join(dir, glob)).select { |path| scannable_path?(path, dir) }
          reset_scan_progress(paths.size) if stream
          pairs = parallel_map(paths) { |path, idx| scan_one(dir:, path:, depth:, stream:, index: idx) }
          pairs.concat(cross_file_pairs(dir, paths))
          Result.ok(prune_violation_objects(pairs))
        rescue StandardError => e
          Result.err("scan_dir: #{e.message}", category: :infrastructure)
        end

        def scan_since(ref = "HEAD~1", dir: ".", depth: :deep, stream: false)
          validate_depth!(depth)
          repo_root = git_toplevel(dir)
          return Result.err("git root failed", category: :validation) unless repo_root

          changed = changed_since(ref, repo_root)
          return changed if changed.err?

          paths = scan_since_paths(changed.value!, dir:, repo_root:)
          pairs = parallel_map(paths) { |path, idx| scan_one(dir:, path:, depth:, stream:, index: idx) }
          Result.ok(prune_violation_objects(pairs))
        rescue StandardError => e
          Result.err("scan_since: #{e.message}", category: :infrastructure)
        end

        def add_rule(rule)
          @rules << rule
          self
        end

        def set_agent(agent)
          @rules.each { |r| r.set_agent(agent) if r.respond_to?(:set_agent) }
          self
        end

        private

        def validate_depth!(depth)
          return if depth == REQUIRED_DEPTH

          raise ArgumentError, "forbidden scan depth #{depth.inspect} — deep only (DEEP_SCAN_ONLY)"
        end

        def git_toplevel(dir)
          out, _, status = git_capture("git", "-C", dir, "rev-parse", "--show-toplevel")
          status.success? ? out.strip : nil
        end

        def changed_since(ref, repo_root)
          out, _, status = git_capture("git", "-C", repo_root, "diff", "--name-only", "#{ref}...HEAD")
          return Result.err("git diff failed", category: :validation) unless status.success?

          Result.ok(out.lines.map(&:strip).reject(&:empty?))
        end

        def git_capture(*argv)
          Timeout.timeout(GIT_TIMEOUT_SECONDS) { Master::Io::Exec.capture3(*argv) }
        rescue Timeout::Error
          ["", "git command timed out after #{GIT_TIMEOUT_SECONDS}s", failure_status]
        end

        def failure_status
          Struct.new(:success?).new(false)
        end

        def scan_since_paths(changed, dir:, repo_root:)
          scan_root = File.expand_path(dir)
          master_lib = File.join(repo_root, "MASTER", "lib")
          paths = changed.filter_map do |rel|
            path = File.expand_path(rel, repo_root)
            next unless File.exist?(path) && File.extname(path).match?(SCAN_SINCE_EXT)
            next unless under_path?(path, scan_root) || under_path?(path, master_lib)
            next if self.class.skip_path?(path, root: repo_root)

            path
          end
          paths.uniq
        end

        def scannable_path?(path, root)
          File.file?(path) && !self.class.skip_path?(path, root:)
        end

        def under_path?(path, root)
          expanded_path = File.realpath(path)
          expanded_root = File.realpath(root)
          expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
        rescue StandardError
          expanded_path = File.expand_path(path)
          expanded_root = File.expand_path(root)
          expanded_path == expanded_root || expanded_path.start_with?("#{expanded_root}#{File::SEPARATOR}")
        end

        def parallel_map(items)
          cursor  = Mutex.new
          index   = 0
          results = Array.new(items.size)
          threads = Array.new(POOL_SIZE) do
            Thread.new(results) do |thread_results|
              loop do
                i = cursor.synchronize { (index += 1) - 1 }
                break if i >= items.size
                maybe_gc(i)
                thread_results[i] = yield(items[i], i)
              rescue StandardError => e
                @bus&.publish("scanner:thread_error", path: items[i], index: i, error: e.message)
                thread_results[i] = [items[i], Result.err(e.message, category: :infrastructure)]
              end
            end
          end
          threads.each(&:join)
          results
        end

        def scan_one(dir:, path:, depth:, stream:, index: nil)
          sleep @file_sleep_s if @file_sleep_s > 0
          file_result = scan(path, depth:)
          emit_scan_progress(dir:, path:, file_result:) if stream
          [path, file_result]
        rescue StandardError => e
          @bus&.publish("scanner:thread_error", path:, index:, error: e.message)
          [path, Result.err(e.message, category: :infrastructure)]
        end

        def cross_file_pairs(dir, paths)
          CrossFileAnalysis.new(root: dir).call(paths)
        rescue StandardError => e
          @bus&.publish("scanner:cross_file_error", path: dir, error: e.message)
          []
        end

        def maybe_gc(index)
          GC.start if index.positive? && (index % GC_EVERY_N_ITERATIONS).zero?
        end

        def prune_violation_objects(pairs)
          total = pairs.sum { |_path, result| Result.wrap(result).value_or([]).size }
          return pairs if total <= MAX_VIOLATION_OBJECTS

          remaining = MAX_VIOLATION_OBJECTS
          pruned = total - MAX_VIOLATION_OBJECTS
          pairs.reverse_each do |_path, result|
            findings = Result.wrap(result).value_or([])
            keep = [findings.size, remaining].min
            remaining -= keep
            findings.replace(findings.last(keep))
          end
          @bus&.publish("scanner:violations_pruned", pruned:, kept: MAX_VIOLATION_OBJECTS)
          pairs
        end

        def active_rules(_depth)
          @rules
        end

        # Pure Ruby reader for data/rules.yml prediction_engine.
        # Gates autofix below per-rule confidence threshold.
        def prediction_thresholds
          @prediction_thresholds ||= (Master.load_yaml(Master::RULES_PATH)["prediction_engine"] || {})
        rescue StandardError
          {}
        end

        def should_autofix?(rule_id, observed_conf)
          t = prediction_thresholds[rule_id.to_s] || prediction_thresholds[rule_id]
          return true unless t && t["confidence"]
          observed_conf.to_f >= t["confidence"].to_f
        end

        # HALLUCINATION rule uses lexical and semantic checks for claim_without_reading.
      end
    end
  end
end
