# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "prism"
require "timeout"
require_relative "law_timing"
require_relative "../../review/scan/semantic_fingerprint"
require_relative "../../review/scan/law_health"
require_relative "../../operator/lock_sweep"
require_relative "../../trace/dmesg"

module Master
  module Fix
    module Scan
      class FileProcessor
        RUBY_EXT = %w[.rb .rake .gemspec].freeze
        LOCK_DIR = ".constitutional_locks"
        LOCK_TIMEOUT = 30
        MAX_FILE_BYTES = 10 * 1024 * 1024
        MAX_LINES = 10_000
        STYLE_EXTENSIONS = %w[.css .scss].freeze
        STYLE_MAX_LINES = 12_000
        PROGRESS_POLL_SECONDS = 1.0
        PROGRESS_IDLE_GRACE_SECONDS = 3.0
        PROGRESS_HEARTBEAT_SECONDS = 5.0

        # Fraction of otherwise-clean files that still get the semantic pass.
        # Keyed on the path digest rather than rand, so two scans of the same
        # tree ask the same questions and their reports can be compared.
        SEMANTIC_SAMPLE = ENV.fetch("MASTER_SCAN_SEMANTIC_SAMPLE", "0").to_f

        def self.max_lines_for(path)
          STYLE_EXTENSIONS.include?(File.extname(path.to_s).downcase) ? STYLE_MAX_LINES : MAX_LINES
        end

        def initialize(event_bus: nil, skip_semantic: false)
          @bus = event_bus
          @skip_semantic = skip_semantic
          @progress_path = ENV.fetch("GATE_PROGRESS_FILE", "").to_s
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

        # The model tier off for the length of one block, then back as it was.
        # A tree-wide observation is a mechanical reading: 75% of RAILS files
        # carry a finding, so "run the model when the cheap passes found
        # something" put about 5,000 model calls of 50 to 190 seconds each
        # inside one walk. Asking for full semantic coverage still wins.
        def mechanical_only
          previous = @skip_semantic
          @skip_semantic = true unless semantic_full?
          yield
        ensure
          @skip_semantic = previous
        end

        def call(path:, depth:, laws:)
          with_file_lock(path) do
            code = read_file(path)
            return code if code.err?

            ast = parse_ruby(code.value!, path)
            fingerprint = Master::Review::Scan::SemanticFingerprint.for(code.value!)
            findings = apply_laws(code: code.value!, ast:, path:, law_set: laws)
            findings = annotate_findings(findings, fingerprint:)
            publish_scan_result(path:, depth:, findings:)
            Result.ok(findings)
          end
        rescue StandardError => e
          @bus&.publish("scan:error", path:, error: e.message)
          Result.err("scan failed: #{e.class}: #{e.message} at #{e.backtrace&.first}", category: :infrastructure)
        end

        private

        def read_file(path)
          validation = validate_file(path)
          return validation if validation.err?

          code = File.read(path, encoding: "UTF-8").scrub
          return Result.err("file too long: #{path}", category: :validation) if code.lines.count > self.class.max_lines_for(path)

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

        def validate_file(path)
          return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)
          return Result.err("symlink not allowed: #{path}", category: :validation) if File.symlink?(path)
          return Result.err("binary file skipped: #{path}", category: :validation) if Master.binary_file?(path)
          return Result.err("file too large: #{path}", category: :validation) if File.size(path) > MAX_FILE_BYTES

          Result.ok(path)
        rescue StandardError => e
          Result.err("file validation failed: #{e.message}", category: :validation)
        end

        # flock on a lockfile that is not deleted after use. The kernel drops the lock
        # when its holder exits, so a crashed scan frees the file at once; the files
        # themselves are swept when a day old and not held (::Operator::LockSweep).
        def with_file_lock(path)
          lock_path = lock_path_for(path)
          FileUtils.mkdir_p(File.dirname(lock_path))
          ::Operator::LockSweep.sweep_once(File.dirname(lock_path))
          deadline = Time.now + LOCK_TIMEOUT
          File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |file|
            until file.flock(File::LOCK_EX | File::LOCK_NB)
              raise "lock timeout for #{path}" if Time.now >= deadline

              sleep 0.05
            end
            yield
          end
        end

        def lock_path_for(path)
          digest = Digest::SHA256.hexdigest(File.expand_path(path))
          File.join(Master::ROOT, LOCK_DIR, "#{digest}.lock")
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
          findings = []
          findings.concat(run_law_pass(pass: :lexical, laws: lexical, code:, ast:, path:))
          findings.concat(run_law_pass(pass: :structural, laws: structural, code:, ast:, path:))
          # Keep semantic violations/opportunities independent from lexical
          # findings. A fatal deterministic hit must not suppress meaning-based
          # assessment of the same file; otherwise one early result can hide the
          # other streams.
          return skip_semantic(path:, laws: semantic, findings:) unless semantic_due?(findings, path)

          findings.concat(run_law_pass(pass: :semantic, laws: semantic, code:, ast:, path:))
        end

        # 74 of the 225 declared rules reach a file only through the semantic
        # pass, and the pass ran only when the cheap passes had already found
        # something. So a file that read as clean was never asked the 74
        # questions — and reported "0 findings", which is a claim about the whole
        # law set rather than about the third of it that ran.
        #
        # The cost gate is real: one LLM call per file is not free on a tree this
        # size. Keeping it, but sampling a deterministic slice so clean files are
        # not permanently exempt, and saying so when a file is skipped.
        def semantic_due?(findings, path)
          return false if @skip_semantic
          return true unless findings.empty?
          return false if semantic_sample <= 0

          Digest::SHA256.hexdigest(sample_key(path))[0, 8].to_i(16) % 1000 < (semantic_sample * 1000).round
        end

        def semantic_sample
          return @semantic_sample_override if @semantic_sample_override

          ENV.fetch("MASTER_SCAN_SEMANTIC_SAMPLE", SEMANTIC_SAMPLE.to_s).to_f
        end

        # Relative to the repo, not the absolute path: keyed on the latter, two
        # checkouts of the same tree sample different files and a scan is not
        # reproducible off the machine that ran it. Relative also holds still
        # while the file is edited, so a law does not switch on and off under
        # someone's keystrokes.
        def sample_key(path)
          path.to_s.delete_prefix("#{Master::ROOT}/")
        end

        def skip_semantic(path:, laws:, findings:)
          @bus&.publish("scan:semantic_skipped", path:, law_count: laws.size, reason: "clean file, outside sample")
          findings
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
            ensure
              end_law_progress(token)
            end
          end
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
          temporary = "#{@progress_path}.scan-#{Process.pid}"
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
            [Time.now.to_f - row.fetch("at").to_f, 0].max.round,
          )
        end

        # `defined?` rather than a bare constant: this file is reachable from
        # `require "master"` alone, and Laws::SemanticLaw only exists once
        # review/scan/law_dsl has loaded the registry. Naming it unguarded
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

        def lexical_error?(findings)
          findings.any? do |finding|
            severity = finding.respond_to?(:severity) ? finding.severity : finding[:severity]
            next false if severity.nil?

            %i[error critical].include?(severity.to_sym)
          end
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
