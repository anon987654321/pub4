# frozen_string_literal: true

require "etc"
require "open3"
require "timeout"
require_relative "../review/scan/cross_file_analysis"
require_relative "../review/scan/file_processor"
require_relative "../review/scan/engines/path_filter"
require_relative "../review/scan/engines/progress_reporter"
require_relative "../review/scan/engines/transport"
require_relative "../review/scan/mechanical_autofix"

module Master
  module Fix
    class Scanner
              def self.build(root:, agent: nil, bus: nil, ecology: nil)
        agent = nil if ENV["MASTER_SCAN_DETERMINISTIC"] == "1"
        Review::Scan::LawDSL
        wf = Master.load_yaml(Master.limits_path) rescue {}
        sleep_s = ENV["MASTER_AUTOFIX"] == "1" ? wf.dig("autoloop", "scan_file_sleep_s").to_f : 0
        scanner = new(event_bus: bus, file_sleep_s: sleep_s)
        Review::Scan::Law.registry.select(&:auto_build?).each do |klass|
          scanner.add_law(Review::Scan::LawFactory.build(klass, root:, agent:, ecology:))
        end
        %w[
          CoChangeCouplingLaw LawCoverageLaw RubocopLaw ReekLaw InterconnectLaw
          YamlDeclarativeLaw VetoPatternLaw LawBridgeLaw SemanticLaw AdversarialLaw CommentDriftLaw AstOmissionLaw
          LibRootDisciplineLaw FileSprawlLaw PathPurposeLaw
        ].each do |name|
          klass = Review::Scan::Laws.const_get(name)
          scanner.add_law(Review::Scan::LawFactory.build(klass, root:, agent:, ecology:))
        end
        scanner
      end

      include Master::Review::Scan::ProgressReporter
        include Master::Review::Scan::Transport

        
        # is PathFilter's decision, how it walks is Transport's, and what it
        # says while walking is ProgressReporter's; rule application is its own.

        SCAN_GLOB = "**/*".freeze
        REQUIRED_DEPTH = :deep
        MAX_VIOLATION_OBJECTS = 100_000

        attr_reader :laws

        def self.skip_path?(path, root: nil)
          Master::Review::Scan::PathFilter.skip_path?(path, root:)
        end

        def self.scan_candidate?(path, root: nil)
          return false unless File.file?(path)
          return false if File.symlink?(path)
          return false if skip_path?(path, root:)

          Master.language_for(path) || File.basename(path).match?(/\Aface\.part\d+\.txt\z/)
        end

        def initialize(laws: [], event_bus: nil, file_sleep_s: 0)
          @laws = Array(laws)
          @bus = event_bus
          @mutex = Mutex.new
          @file_sleep_s = file_sleep_s.to_f
          @file_processor = Master::Review::Scan::FileProcessor.new(event_bus: @bus)
          @stream_autofixes = []
          @law_dispatch = build_law_dispatch(@laws)
        end

        attr_reader :stream_autofixes

        def scan(path, depth: :deep, laws: nil)
          validate_depth!(depth)
          law_set = laws || active_laws(depth)
          law_set = dispatched_laws(path, law_set) if laws.nil?
          @file_processor.call(path:, depth:, laws: law_set)
        end

        def scan_dir(dir, depth: :deep, glob: SCAN_GLOB, stream: false, autofix: false, autofix_root: nil, laws: nil)
          validate_depth!(depth)
          paths = Dir.glob(File.join(dir, glob)).select { |path| scannable_path?(path, dir) }
          law_set = laws || active_laws(depth)
          reset_scan_progress(paths.size, laws: law_set) if stream
          unit = stream ? @scan_progress[:unit] : Fiber[:master_unit]
          pairs = Master::Trace::Dmesg.under(unit) do
            parallel_map(paths) do |path, idx|
              scan_one(dir:, path:, depth:, stream:, index: idx, autofix:, autofix_root:, laws: law_set)
            end
          end
          pairs.concat(cross_file_pairs(dir, paths))
          raise_batch_errors!(pairs, "scan_dir")
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
          raise_batch_errors!(pairs, "scan_since")
          Result.ok(prune_violation_objects(pairs))
        rescue StandardError => e
          Result.err("scan_since: #{e.message}", category: :infrastructure)
        end

        def add_law(law)
          @laws << law
          @law_dispatch = build_law_dispatch(@laws)
          self
        end

        # Flat findings with :path merged in. scan_dir returns Result wrapping
        # [path, Result] pairs whose inner values are hashes, so f.rule raises
        # and the path is discarded unless the caller knows the unwrap. This is
        # the one documented way to get them out.
        def findings(paths, depth: :deep)
          Array(paths).flat_map { |path| findings_for(path, depth:) }
        end

        def set_agent(agent)
          @laws.each { |law| law.set_agent(agent) if law.respond_to?(:set_agent) }
          self
        end

        def skip_semantic!
          @file_processor.skip_semantic! if @file_processor.respond_to?(:skip_semantic!)
        end

        def full_semantic!
          @file_processor.full_semantic! if @file_processor.respond_to?(:full_semantic!)
          self
        end
        def semantic_full?
          @file_processor.respond_to?(:semantic_full?) && @file_processor.semantic_full?
        end


        private

        def findings_for(path, depth:)
          return file_rows(path, scan(path, depth:)) unless File.directory?(path)

          rows_of(scan_dir(path, depth:)).flat_map { |file, res| file_rows(file, res) }
        end

        # A file the scanner refuses to read (too long, binary, a symlink) is a
        # fact about the file, as FixLoop's scanner treats it, so it adds no rows
        # and the census goes on; a scan that failed still raises.
        def file_rows(path, result)
          return [] if refused?(result)

          rows_of(result).map { |item| item.merge(path:) }
        end

        def refused?(result)
          result.respond_to?(:err?) && result.err? && result.category == :validation &&
            !result.message.to_s.start_with?("file validation failed")
        end

        # scan_dir answers a Result whose value is [path, Result] pairs, so the
        # same unwrap was written three times here — twice byte for byte. It
        # answers the pairs for the outer Result and the rows for an inner one,
        # which is the same question asked at two depths.
        def rows_of(result)
          return result.value! if result.respond_to?(:ok?) && result.ok?
          return result unless result.respond_to?(:ok?)

          raise "scanner result failed: #{result.message}"
        end

        def scannable_path?(path, root)
          self.class.scan_candidate?(path, root:)
        end

        def validate_depth!(depth)
          return if depth == REQUIRED_DEPTH
          raise ArgumentError, "forbidden scan depth #{depth.inspect} — deep only (DEEP_SCAN_ONLY)"
        end

        def git_toplevel(dir)
          out, _, status = git_capture("git", "-C", dir, "rev-parse", "--show-toplevel")
          status.success? ? out.strip : nil
        end

        def scan_one(dir:, path:, depth:, stream:, index: nil, autofix: false, autofix_root: nil, laws: nil)
          sleep @file_sleep_s if @file_sleep_s > 0
          file_result = scan(path, depth:, laws:)
          applied = autofix ? autofix_one(path, file_result, root: autofix_root || dir) : []
          if applied.any?
            file_result = scan(path, depth:, laws:)
            emit_autofixed(dir:, path:, applied:) if stream
          end
          emit_scan_progress(dir:, path:, file_result:) if stream
          [path, file_result]
        rescue StandardError => e
          @bus&.publish("scanner:thread_error", path:, index:, error: e.message)
          [path, Result.err(e.message, category: :infrastructure)]
        end

        def autofix_one(path, file_result, root:)
          applied = Master::Review::Scan::MechanicalAutofix.new(scanner: self, root:, event_bus: @bus).apply([[path, file_result]])
          return [] if applied.empty?

          @mutex.synchronize { @stream_autofixes.concat(applied) }
          applied
        end

        def emit_autofixed(dir:, path:, applied:)
          rel = path.sub(dir, "").delete_prefix("/")
          transforms = applied.flat_map { |row| Array(row.transforms) }.uniq.first(8).join(" ")
          unit = @scan_progress&.dig(:unit) || @through_scan_unit || "scan0"
          Master::Trace::Dmesg.status(unit, "autofixed #{rel} #{transforms}")
        end

        def cross_file_pairs(dir, paths)
          Master::Review::Scan::CrossFileAnalysis.new(root: dir).call(paths)
        rescue StandardError => e
          @bus&.publish("scanner:cross_file_error", path: dir, error: e.message)
          raise "cross-file scan failed for #{dir}: #{e.class}: #{e.message}"
        end

        def raise_batch_errors!(pairs, label)
          failures = pairs.filter_map do |path, result|
            wrapped = Master::Result.wrap(result)
            next unless wrapped.err?
            next if skippable_validation_error?(wrapped)

            "#{path}: #{wrapped.message}"
          end
          return if failures.empty?

          raise "#{label}: #{failures.size} file(s) failed measurement — #{failures.first(5).join("; ")}"
        end

        def skippable_validation_error?(result)
          return false unless result.category == :validation

          result.message.to_s.match?(/\A(?:file not found:|symlink not allowed:|binary file skipped:|file too large:)/)
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

        def active_laws(_depth)
          @laws
        end

        # LawDSL's applies_to scope is already authoritative inside the rule.
        # Use the same declaration one level earlier so a JavaScript file does
        # not traverse every Ruby-only rule, and a Ruby file does not traverse
        # the CSS/HTML population. Laws without an explicit scope remain in every
        # bucket. Explicit law arrays passed by callers keep the old full set.
        def dispatched_laws(path, law_set)
          return law_set unless law_set.equal?(@laws)
          language = Master.language_for(path)
          return law_set if language.to_s.empty?

          @law_dispatch.fetch(language.to_s, law_set)
        end

        def build_law_dispatch(laws)
          entries = []
          languages = Master::FILE_LANGUAGE_MAP.values.compact.map(&:to_s).uniq
          languages << "javascript"
          Array(laws).each do |law|
            declared = if law.class.respond_to?(:dsl_langs)
              Array(law.class.dsl_langs).filter_map { |lang| lang.to_s unless lang.to_s.empty? }
            else
              []
            end
            entries << [law, declared]
            languages.concat(declared)
          end

          languages.uniq.each_with_object({}) do |language, buckets|
            buckets[language] = entries.filter_map do |law, declared|
              law if declared.empty? || declared.include?(language)
            end.freeze
          end.freeze
        end

        def law_prediction_thresholds
          path = Master::LAWS_PATH
          stat = File.stat(path)
          stamp = [stat.size, stat.ino, stat.mtime.to_r]
          return @law_prediction_thresholds if @law_prediction_thresholds_stamp == stamp

          laws = Master.load_yaml(path) || {}
          prediction = laws["prediction_engine"]
          prediction = {} unless prediction.is_a?(Hash)

          # prediction_engine was retired; an absent policy means no additional
          # confidence threshold. The law/autofix policy remains authoritative.
          @law_prediction_thresholds_stamp = stamp
          @law_prediction_thresholds = prediction.freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Scanner.law_prediction_thresholds")
          raise "scanner: prediction policy unreadable: #{e.class}: #{e.message}"
        end

        # An autofix that takes code out is a different risk from one that puts an
        # attribute in, and no confidence score says which. Four rules declare a
        # transform: add_html_lang, add_lazy_loading and add_trailing_commas each
        # add something a reader sees in the diff, and remove_immediate_dead_code
        # deletes, where a wrong call is invisible to anyone who does not already
        # know what stood there.
        #
        # Deletion waits for a person. The word is /fix, and an unattended pass —
        # bin/gate over all four governed trees — adds without deleting.
        #
        # The list is Master::Review::Scan::AstFixer::DELETING_TRANSFORMS rather than a copy here: it
        , and the copy that stood here gated
        # only this path while AstFixer ran the transform unasked on the other.
        def deleting_law?(law_id)
          transform = law_transforms[law_id.to_s]
          Master::Review::Scan::AstFixer::DELETING_TRANSFORMS.include?(transform.to_s)
        end

        def law_transforms
          path = Master::LAWS_PATH
          stat = File.stat(path)
          stamp = [stat.size, stat.ino, stat.mtime.to_r]
          return @law_transforms if @law_transforms_stamp == stamp

          laws = Master.law_entries(root: Master::ROOT)
          @law_transforms_stamp = stamp
          @law_transforms = laws.each_with_object({}) do |law, index|
            transform = law["autofix"]
            index[law["id"].to_s] = transform if transform
          end.freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Scanner.law_transforms")
          raise "scanner: autofix transform policy unreadable: #{e.class}: #{e.message}"
        end

        # Confidence answers "did it find the thing", never "is fixing it safe".
        # A deterministic finding carries no confidence at all and Fix::LawLoop
        # reads the absence as 1.0, so a threshold here would wave through exactly
        # the findings nobody scored.
        def should_autofix?(law_id, observed_conf, allow_deletions: false)
          return false if !allow_deletions && deleting_law?(law_id)

          threshold = law_prediction_thresholds[law_id.to_s] || law_prediction_thresholds[law_id]
          return true unless threshold && threshold["confidence"]

          observed_conf.to_f >= threshold["confidence"].to_f
        end
      end
    end
  end
end
