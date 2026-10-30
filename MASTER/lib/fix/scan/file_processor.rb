# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "prism"
require "timeout"

require_relative "law_timing"
require_relative "file_lock"
require_relative "unmodelled_tier"
require_relative "finding_cache"
require_relative "source_override"
require_relative "../check_focus"
require_relative "../../review/scan/semantic_fingerprint"
require_relative "../../review/scan/law_health"
require_relative "../../trace/dmesg"

module Master
  module Fix
    module Scan
      class FileProcessor
        RUBY_EXT = %w[.rb .rake .gemspec].freeze
        include FileLock
        include UnmodelledTier

        LOCK_DIR = ".constitutional_locks"
        LOCK_TIMEOUT = 30
        MAX_FILE_BYTES = 10 * 1024 * 1024
        MAX_LINES = 10_000
        STYLE_EXTENSIONS = %w[.css .scss].freeze
        STYLE_MAX_LINES = 12_000
        STRUCTURED_DATA_EXTENSIONS = %w[.json .yml .yaml].freeze
        STRUCTURED_DATA_MAX_LINES = 20_000
        OUTSIDE_SAMPLE = "clean file, outside sample"
        UNCHANGED = "unchanged since its last semantic read"
        DEFERRED = "put off behind the pass's mechanical repairs"
        OVER_BUDGET = "past the pass's semantic budget"
        # Model reads, kept apart from the deterministic findings so each is keyed on its own law set.
        SEMANTIC_DIR = File.join(".master", "semantic_findings")
        PROGRESS_POLL_SECONDS = 1.0
        PROGRESS_IDLE_GRACE_SECONDS = 3.0
        PROGRESS_HEARTBEAT_SECONDS = 5.0

        # The longest file each kind of source may be before a scan refuses it.
        def self.max_lines_for(path)
          extension = File.extname(path.to_s).downcase
          return STYLE_MAX_LINES if STYLE_EXTENSIONS.include?(extension)
          return STRUCTURED_DATA_MAX_LINES if STRUCTURED_DATA_EXTENSIONS.include?(extension)

          MAX_LINES
        end

        def initialize(event_bus: nil, skip_semantic: false, cache_root: Master::ROOT)
          @bus = event_bus
          @skip_semantic = skip_semantic
          @semantic_gap_mutex = Mutex.new
          @semantic_gaps = {}
          @semantic_reads = FindingCache.new(root: cache_root, dir: SEMANTIC_DIR)
          @finding_cache = FindingCache.new(root: cache_root)
          @semantic_gap_notice_emitted = false
          @ast_mutex = Mutex.new
          @ast_assessments = {}
          @deferral = nil
          @semantic_budget = nil

          @progress_path = ENV.fetch("CHECK_PROGRESS_FILE", "").to_s
          @progress_writer_id = "#{Process.pid}-#{object_id}"
          @progress_mutex = Mutex.new
          @active_law_checks = {}
          @progress_previous_callbacks = {}
          @progress_sequence = 0
          @progress_thread = nil
          @progress_idle_since = nil
          @progress_last_check = nil
          @progress_error_reported = false
        end

        def skip_semantic!
          @skip_semantic = true
        end

        def full_semantic!
          @skip_semantic = false
          @semantic_sample_override = 1.0
        end

        def semantic_full? = @semantic_sample_override.to_f >= 1.0

        # Within the block, on this thread, a due model read with no replayable answer is listed in
        # +into+ instead of made, so the cheap findings of a whole corpus reach repair first and the
        # caller reads the list afterwards under a budget (FixLoop::PassRunner::StreamStage). Read
        # inline at a minute and a half a file, twenty files hold the first repair for half an hour.
        # Other threads, a repair verifying its own edit among them, still read inline.
        def deferring_semantic(into, &) = scoped(:@deferral, into, &)

        # Within the block, on this thread, a model read is made only while +budget+ is open, and its
        # wall time is charged to it.
        def budgeting_semantic(budget, &) = scoped(:@semantic_budget, budget, &)

        # Semantic outages are explicit evidence, separate from files that failed
        # mechanical measurement. They prevent DONE without hiding deterministic
        # findings from the same file.
        def semantic_gaps
          @semantic_gap_mutex.synchronize { @semantic_gaps.dup }
        end

        def reset_semantic_gaps!
          @semantic_gap_mutex.synchronize do
            @semantic_gaps.clear
            @semantic_gap_notice_emitted = false
            @unmodelled_notice_emitted = false
          end
          self
        end

        # Per-file parser receipts let the assessment matrix distinguish a real
        # syntax-tree reading from a scanner pass that silently fell back to text.
        def ast_assessments
          @ast_mutex.synchronize { @ast_assessments.dup }
        end

        def reset_ast_assessments!
          @ast_mutex.synchronize { @ast_assessments.clear }
          self
        end

        def record_ast_assessment(path:, code:, ast:)
          status = ast ? "assessed" : "inconclusive"
          row = {
            "status" => status,
            "sha256" => Digest::SHA256.hexdigest(code),
            "reason" => ast ? nil : "Prism did not produce a syntax tree for the current Ruby source",
          }.freeze
          @ast_mutex.synchronize { @ast_assessments[File.expand_path(path)] = row }
          @bus&.publish(
            "scan:ast_assessment",
            path: File.expand_path(path),
            status:,
            sha256: row["sha256"],
            reason: row["reason"],
          )
        end

        # The model tier off for the length of one block, then back as it was.
        # A tree-wide observation is a mechanical reading: 75% of RAILS files
        # carry a finding, so "run the model when the cheap passes found
        # something" put about 5,000 model calls of 50 to 190 seconds each
        # inside one walk. The operator asking for every file to be read
        # (MASTER_SCAN_SEMANTIC_SAMPLE=1, or a mode at 1.0) still wins. A
        # requested /fix's own full_semantic! does not: it is set on the shared
        # scanner for the repair's budgeted passes, and leaking into the
        # re-observe it sent all 2,049 MASTER files to the model inline.
        def mechanical_only
          previous = @skip_semantic
          @skip_semantic = true unless Master::Ground::ModePosture.semantic_sample >= 1.0
          yield
        ensure
          @skip_semantic = previous
        end

        def call(path:, depth:, laws:)
          with_file_lock(path) { measure(path:, depth:, laws:) }
        rescue LockTimeout => e
          unmeasured(path, e)
        rescue StandardError => e
          @bus&.publish("scan:error", path:, error: e.message)
          Result.err("scan failed: #{e.class}: #{e.message} at #{e.backtrace&.first}", category: :infrastructure)
        end

        private

        def measure(path:, depth:, laws:)
          read = read_file(path)
          return read if read.err?

          code = read.value!
          ast = parse_ruby(code, path)
          record_ast_assessment(path:, code:, ast:) if Master.language_for(path) == "ruby"
          fingerprint = Master::Review::Scan::SemanticFingerprint.for(code)
          findings = annotate_findings(apply_laws(code:, ast:, path:, law_set: laws), fingerprint:)
          publish_scan_result(path:, depth:, findings:)
          Result.ok(findings)
        end

        # A path with a SourceOverride is judged by that text, not by the disk.
        def read_file(path)
          read = SourceOverride.read(path, max_bytes: MAX_FILE_BYTES) || read_disk(path)
          return read if read.err?

          code = read.value!.scrub
          line_count = code.count("\n")
          line_count += 1 unless code.empty? || code.end_with?("\n")
          return Result.err("file too long: #{path}", category: :validation) if line_count > self.class.max_lines_for(path)

          @bus&.publish("scan:file_read", path:, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(law_conducted(path, code))
        end

        # A law file necessarily contains the pattern it forbids — detector,
        # fix text, bad fixture. Law.conduct neutralizes those lines (keeping
        # line numbers) before law judges law/; that only covered Law.scan,
        # so every REGISTRY law read law/ raw and NULL_BLINDNESS flagged
        # law/null_blindness.rb's own detector. One read site, so every law
        # sees the same conducted text.
        def law_conducted(path, code)
          return code unless path.to_s.match?(%r{/law/[^/]+\.rb\z})

          require File.join(Master::ROOT, "law", "definition") unless defined?(Law)
          Law.conduct(code)
        end

        def read_disk(path)
          validation = validate_file(path)
          validation.err? ? validation : Result.ok(File.read(path, encoding: "UTF-8"))
        end

        def validate_file(path)
          return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)
          return Result.err("symlink not allowed: #{path}", category: :validation) if File.symlink?(path)
          return Result.err("binary file skipped: #{path}", category: :validation) if Master.binary_file?(path)
          return Result.err("file too large: #{path}", category: :validation) if File.size(path) > MAX_FILE_BYTES

          Result.ok(path)
        rescue StandardError => e
          Result.err("file validation failed: #{e.message}", category: :validation)
        end

        # Recorded where an unanswered semantic read is, so the file blocks DONE as
        # inconclusive while the rest of the walk goes on.
        def unmeasured(path, error)
          relative = relative_progress_path(path)
          @semantic_gap_mutex.synchronize { @semantic_gaps[relative] ||= "INCONCLUSIVE: #{error.message}"[0, 240] }
          @bus&.publish("scan:inconclusive", path: relative, reason: error.message)
          Master::Trace::Dmesg.status("scan0", "inconclusive, #{error.message}"[0, 200])
          Result.ok([])
        end

        def parse_ruby(code, path)
          return unless Master.language_for(path) == "ruby"

          result = Prism.parse(code)
          return result.value if result.success?

          @bus&.publish("scan:syntax_fault", path:, error_count: result.errors.size)
          nil
        rescue StandardError => e
          @bus&.publish("scan:parse_error", path:, error: e.message)
          nil
        end

        def apply_laws(code:, ast:, path:, law_set:)
          lexical, structural, semantic = partition_laws(law_set, ast)
          findings = deterministic_findings({ lexical:, structural: }, code:, ast:, path:)

          # Keep semantic violations/opportunities independent from lexical
          # findings. A fatal deterministic hit must not suppress meaning-based
          # assessment of the same file; otherwise one early result can hide the
          # other streams.
          read = semantic_findings(findings, Reading.new(path:, code:, ast:, laws: semantic))
          findings + Array(read).map { |finding| from_the_model(finding) }
        end
        # Public: the whole of what a scan concludes about a text, with no file read.
        public :apply_laws

        # A model's reading names its findings freely, often after a registered law, and two
        # readings of one file need not agree. Marked, so a repair's gates can tell it from a
        # detector's: unmarked, NO_CHANGELOG_COMMENT and WHY_NOT_WHAT on lines a repair never
        # touched refused it as new violations.
        def from_the_model(finding)
          row = finding.is_a?(Hash) ? finding : finding.to_h
          row.merge(stream: :semantic)
        end

        # One file's due model read, as semantic_findings replays, puts off, refuses or makes it.
        Reading = Data.define(:path, :code, :ast, :laws) do
          def subject(relative) = FindingCache::Subject.new(relative, code, laws, ast)
        end

        # A replay costs nothing and is always taken; a fresh read waits while the pass defers, and is
        # refused once the pass's budget is spent.
        def semantic_findings(found, reading)
          return skipped(reading, OUTSIDE_SAMPLE) unless semantic_due?(found, reading.path)
          return [] if (reading = modelled(reading)).laws.empty?

          replayed = @semantic_reads.replay(reading.subject(relative_progress_path(reading.path)))
          return skipped(reading, UNCHANGED) + replayed unless replayed.nil?
          return defer(reading) if on_this_thread(@deferral)
          return skipped(reading, OVER_BUDGET) unless semantic_budget_open?

          budgeted_read(reading)
        end

        def skipped(reading, reason)
          note_skip(path: reading.path, laws: reading.laws, reason:)
          []
        end

        def defer(reading)
          into = on_this_thread(@deferral)
          @semantic_gap_mutex.synchronize { into << reading.path }
          skipped(reading, DEFERRED)
        end

        def semantic_budget_open?
          budget = on_this_thread(@semantic_budget)
          budget.nil? || budget.open?
        end

        def budgeted_read(reading)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          read_semantic(**reading.to_h)
        ensure
          on_this_thread(@semantic_budget)&.charge(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        end

        def scoped(ivar, value)
          previous = instance_variable_get(ivar)
          instance_variable_set(ivar, [Thread.current, value])
          yield
        ensure
          instance_variable_set(ivar, previous)
        end

        def on_this_thread(pair) = pair&.first == Thread.current ? pair.last : nil

        # Laws that read only this file's text replay their findings when the text is unchanged
        # (FindingCache); the rest run every time.
        def deterministic_findings(passes, code:, ast:, path:)
          pure = passes.transform_values { |laws| laws.select { |law| @finding_cache.cacheable?(law) } }
          live = passes.to_h { |pass, laws| [pass, laws - pure[pass]] }
          relative = relative_progress_path(path)

          replayed = @finding_cache.fetch(FindingCache::Subject.new(relative, code, pure.values.flatten, ast)) do
            run_passes(pure, code:, ast:, path:)
          end
          replayed + run_passes(live, code:, ast:, path:)
        end

        def run_passes(passes, code:, ast:, path:)
          passes.flat_map { |pass, laws| run_law_pass(pass:, laws:, code:, ast:, path:) }
        end

        # 74 of the 225 declared rules reach a file only through the semantic
        # pass, and the pass ran only when the cheap passes had already found
        # something. So a file that read as clean was never asked the 74
        # questions — and reported "0 findings", which is a claim about the whole
        # law set rather than about the third of it that ran.
        #
        # The cost check is real: one LLM call per file is not free on a tree this
        # size. Keeping it, but sampling a deterministic slice so clean files are
        # not permanently exempt, and saying so when a file is skipped.
        def semantic_due?(findings, path)
          return false if @skip_semantic || CheckFocus.blockers?
          return true unless findings.empty?
          return false if semantic_sample <= 0

          window = (semantic_sample * 1000).round
          bucket = Digest::SHA256.hexdigest(sample_key(path))[0, 8].to_i(16) % 1000
          (bucket - (rotation_day * window)) % 1000 < window
        end

        # The slice moves by one window a day, so a tenth read per run covers the tree in ten days,
        # and two scans on the same day still ask the same questions.
        # Julian day is monotonic across New Year; yday would repeat sampling buckets at the year boundary.
        def rotation_day = Date.today.jd

        # Fraction of otherwise-clean files that still get the semantic pass, from
        # Ground::ModePosture. Keyed on the path digest rather than rand, so two scans
        # of the same tree ask the same questions and their reports can be compared.
        def semantic_sample
          return @semantic_sample_override if @semantic_sample_override

          Master::Ground::ModePosture.semantic_sample
        end

        # Relative to the repo, not the absolute path: keyed on the latter, two
        # checkouts of the same tree sample different files and a scan is not
        # reproducible off the machine that ran it. Relative also holds still
        # while the file is edited, so a law does not switch on and off under
        # someone's keystrokes.
        def sample_key(path)
          path.to_s.delete_prefix("#{Master::ROOT}/")
        end

        # A read is kept, clean or not, only when every semantic law answered: an inconclusive read leaves a
        # gap and is asked again. Asking about unchanged text again re-rolls the answer and buys nothing,
        # at 50 to 190 seconds a call; the next edit to the file, its laws or the scanner asks afresh.
        def read_semantic(path:, code:, ast:, laws:)
          semantic = run_law_pass(pass: :semantic, laws:, code:, ast:, path:)
          relative = relative_progress_path(path)
          answered = !@semantic_gap_mutex.synchronize { @semantic_gaps.key?(relative) }
          return semantic unless answered && !relative.start_with?("/")

          @semantic_reads.record(FindingCache::Subject.new(relative, code, laws, ast), semantic)
          semantic
        end

        def note_skip(path:, laws:, reason:)
          @bus&.publish("scan:semantic_skipped", path:, law_count: laws.size, reason:)
        end

        def partition_laws(law_set, ast)
          semantic = []
          structural = []
          lexical = []
          law_set.each do |law|
            if semantic_law?(law)
              semantic << law
            elsif ast && law.respond_to?(:check_ast)
              structural << law
            else
              lexical << law
            end
          end
          [lexical, structural, semantic]
        end

        def run_law_pass(pass:, laws:, code:, ast:, path:)
          @bus&.publish("scan:pass", path:, pass:, law_count: laws.size)
          laws.each_with_index.flat_map do |law, index|
            token = begin_law_progress(pass:, law:, index: index + 1, total: laws.size, path:)
            begin
              run_law(law:, code:, ast:, path:)
            rescue StandardError => e
              raise unless pass.to_sym == :semantic && semantic_inconclusive?(e)

              record_semantic_inconclusive(path:, law:, error: e)
              []
            ensure
              end_law_progress(token)
            end
          end
        end

        def semantic_inconclusive?(error)
          error.message.to_s.include?("semantic assessment INCONCLUSIVE")
        end

        def record_semantic_inconclusive(path:, law:, error:)
          relative = relative_progress_path(path)
          law_id = law.respond_to?(:id) ? law.id.to_s : law.class.name.to_s
          detail = "#{law_id}: #{error.message.to_s[0, 220]}"
          first_file, announce = @semantic_gap_mutex.synchronize do
            next [false, false] if @semantic_gaps.key?(relative)

            @semantic_gaps[relative] = detail
            first_notice = !@semantic_gap_notice_emitted
            @semantic_gap_notice_emitted = true
            [true, first_notice]
          end
          return unless first_file

          @bus&.publish("scan:semantic_inconclusive", path: relative, law: law_id, message: detail)
          Master::Trace::Dmesg.status("law0", "semantic assessment inconclusive; details recorded for #{relative}"[0, 200]) if announce
        end

        # The monitor reports the law that's actually in flight, not merely the
        # outer scan stage. One small watcher samples this in-memory state once a
        # second; worker threads never contend on progress-file I/O.
        def begin_law_progress(pass:, law:, index:, total:, path:)
          return unless ENV["MASTER_SCAN_PROGRESS"] != "0"

          previous_callback = Thread.current.thread_variable_get(:master_scan_progress_callback)
          # Object identity keeps simultaneous worker threads from collapsing
          # into one hash key when they enter the scanner at the same time.
          token = Object.new
          callback = lambda do |inner_pass:, inner_law:, index:, total:, path:|
            @progress_mutex.synchronize do
              active = @active_law_checks[token]
              next unless active

              @progress_sequence += 1
              active.merge!(
                "pass" => inner_pass.to_s,
                "law" => inner_law.to_s,
                "file" => relative_progress_path(path),
                "n" => index,
                "total" => total,
                "name" => "#{inner_pass} #{inner_law}",
                "at" => Time.now.to_f,
                "updated_at" => Time.now.to_f,
                "checks" => @progress_sequence,
              )
              @progress_last_check = active
            end
          end
          Thread.current.thread_variable_set(:master_scan_progress_callback, callback)

          law_id = law.respond_to?(:id) ? law.id.to_s : law.class.name.to_s
          relative = relative_progress_path(path)
          row = {
            "kind" => "scan",
            "state" => "running",
            "pass" => pass.to_s,
            "law" => law_id,
            "file" => relative,
            "n" => index,
            "total" => total,
            "name" => "#{pass} #{law_id}",
            "at" => Time.now.to_f,
            "updated_at" => Time.now.to_f,
          }

          @progress_mutex.synchronize do
            @progress_sequence += 1
            row["checks"] = @progress_sequence
            @progress_previous_callbacks[token] = previous_callback
            @active_law_checks[token] = row
            @progress_idle_since = nil
            @progress_last_check = row
            start_progress_monitor_locked
          end
          token
        end

        def end_law_progress(token)
          return unless token

          previous_callback = nil
          @progress_mutex.synchronize do
            previous_callback = @progress_previous_callbacks.delete(token)
            finished = @active_law_checks.delete(token)
            if finished && @active_law_checks.empty?
              @progress_idle_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              @progress_last_check = finished.merge(
                "state" => "idle",
                "active" => 0,
                "updated_at" => Time.now.to_f,
              )
            end
          end
          Thread.current.thread_variable_set(:master_scan_progress_callback, previous_callback)
        end

        def start_progress_monitor_locked
          return if @progress_thread&.alive?

          @progress_thread = Thread.new { run_progress_monitor }
          @progress_thread.name = "master-scan-progress" if @progress_thread.respond_to?(:name=)
        end

        def run_progress_monitor
          last_console_beat = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          loop do
            sleep PROGRESS_POLL_SECONDS
            snapshot = nil
            stop = false
            @progress_mutex.synchronize do
              now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              if @active_law_checks.empty?
                @progress_idle_since ||= now
                if now - @progress_idle_since >= PROGRESS_IDLE_GRACE_SECONDS
                  @progress_thread = nil if @progress_thread == Thread.current
                  stop = true
                elsif @progress_last_check
                  snapshot = @progress_last_check.merge(
                    "state" => "idle",
                    "active" => 0,
                    "monitor_at" => Time.now.to_f,
                  )
                end
              else
                current = @active_law_checks.values.max_by { |row| row.fetch("checks") }
                snapshot = current.merge(
                  "state" => "running",
                  "active" => @active_law_checks.size,
                  "monitor_at" => Time.now.to_f,
                )
              end
            end
            break if stop
            next unless snapshot

            if @progress_path.empty?
              now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              if snapshot["state"] == "running" && now - last_console_beat >= PROGRESS_HEARTBEAT_SECONDS
                Master::Trace::Dmesg.status("scan0", progress_line(snapshot))
                last_console_beat = now
              end
            else
              write_progress_snapshot(snapshot)
            end
          end
        rescue StandardError => e
          Master::Trace::Dmesg.status("scan0", "progress monitor failed, #{e.class}: #{e.message.to_s[0, 140]}")
        ensure
          @progress_mutex.synchronize do
            @progress_thread = nil if @progress_thread == Thread.current
          end
        end

        def write_progress_snapshot(row)
          temporary = "#{@progress_path}.scan-#{@progress_writer_id}"
          File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |io|
            io.write(JSON.generate(row))
            io.flush
          end
          File.rename(temporary, @progress_path)
        rescue SystemCallError, IOError => e
          should_report = @progress_mutex.synchronize do
            next false if @progress_error_reported

            @progress_error_reported = true
          end
          Master::Trace::Dmesg.status("scan0", "progress file unavailable, #{e.class}: #{e.message}") if should_report
        ensure
          begin
            File.delete(temporary) if temporary && File.exist?(temporary)
          rescue SystemCallError
            nil
          end
        end

        def relative_progress_path(path)
          expanded = File.expand_path(path.to_s)
          [Master::REPO_ROOT, Master::ROOT].compact.each do |root|
            base = File.expand_path(root)
            return expanded.delete_prefix("#{base}/") if expanded.start_with?("#{base}/")
          end
          path.to_s
        end

        def progress_line(row)
          format(
            "active pass=%s law=%s file=%s checks=%s law=%s/%s workers=%s for %ds",
            row.fetch("pass"), row.fetch("law"), row.fetch("file"), row.fetch("checks"),
            row.fetch("n"), row.fetch("total"), row.fetch("active", 1),
            [Time.now.to_f - row.fetch("at").to_f, 0].max.round
          )
        end

        # `defined?` rather than a bare constant: this file is reachable from
        # `require "master"` alone, and Laws::SemanticLaw only exists once
        # review/scan/law_tree has loaded law/. Naming it unguarded
        # turned every scan on that path into "scan failed: uninitialized
        # constant", which reads as a broken file rather than a missing require.
        #
        # A law that takes a model (set_agent, as Laws::NeedsModel declares) is
        # a semantic law whatever its class: AdversarialLaw and CommentDriftLaw
        # sat in the lexical pass, so every file, clean ones included, paid a
        # model call and the clean-file sample gated nothing.
        def semantic_law?(law)
          semantic_class = defined?(Master::Review::Scan::Laws::SemanticLaw) &&
                           Master::Review::Scan::Laws::SemanticLaw
          return true if semantic_class && law.is_a?(semantic_class)
          return true if law.respond_to?(:set_agent)

          law.respond_to?(:id) && law.id.to_s == "semantic"
        end

        def annotate_findings(findings, fingerprint:)
          Array(findings).map do |finding|
            Master::Review::Scan::LawHealth.annotate(add_fingerprint(finding, fingerprint:))
          end
        end

        def add_fingerprint(finding, fingerprint:)
          meta = { fingerprint: }
          return finding.merge(meta) if finding.respond_to?(:merge)
          return finding.to_h.merge(meta) if finding.respond_to?(:to_h)

          finding
        end

        def run_law(law:, code:, ast:, path:)
          LawTiming.measure(law) do
            next law.check(code, path:) unless ast && law.respond_to?(:check_ast)

            law.check_ast(ast, code, path:)
          end
        end

        def publish_scan_result(path:, depth:, findings:)
          @bus&.publish("scan:complete", path:, depth:, count: findings.size, top_laws: top_laws(findings))
        end

        def top_laws(findings, limit: 3)
          findings.each_with_object(Hash.new(0)) do |finding, counts|
            law = finding_law(finding)
            counts[law] += 1 if law
          end.sort_by { |law, count| [-count, law] }.first(limit).to_h
        end

        def finding_law(finding)
          law =
            if finding.respond_to?(:[])
              finding[:law] || finding[:law_id] || finding["law"] || finding["law_id"]
            elsif finding.respond_to?(:law)
              finding.law
            elsif finding.respond_to?(:law_id)
              finding.law_id
            end

          law.to_s unless law.nil? || law.to_s.empty?
        end

      end
    end
  end
end
