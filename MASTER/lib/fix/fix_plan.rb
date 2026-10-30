# frozen_string_literal: true

require "digest"
require "json"
require "rbconfig"
require "time"

module Master
  module Fix
    # Immutable pre-mutation scope and provenance receipt for one /fix run.
    # File contents remain owned by Git and Transaction; this object only pins
    # what was observed, which Laws governed it and which adapters were present.
    class FixPlan
      VERSION = 1
      AUTHORITY_FILES = %w[data/soul.yml data/laws.yml].freeze
      RUNTIME_FILES = %w[
        law/definition.rb
        lib/review/scan/law.rb
        lib/review/scan/law_tree.rb
        lib/fix/scanner.rb
        lib/fix/scan/file_processor.rb
        lib/fix/opportunity_pass.rb
        lib/fix/visual_pass.rb
        lib/fix/four_stream_assessment.rb
        lib/fix/fix_plan.rb
        lib/fix/kernel.rb
        lib/fix/kernel/convergence_adapter.rb
        lib/fix/kernel/lifecycle.rb
        lib/fix/kernel/lifecycle_journal.rb
        lib/fix/kernel/repair_adapter.rb
        lib/fix/run_journal.rb
        lib/fix/repair_loop.rb
        lib/fix/fix_loop.rb
        lib/fix/outcome_policy.rb
        lib/execution/contract.rb
        lib/io/atomic_write.rb
      ].freeze
      # A plan binds the executable Law catalogue and the complete /fix
      # engine that interprets, persists and terminalizes its evidence. Adding
      # or changing an adapter invalidates the same provenance fingerprint.
      RUNTIME_GLOBS = %w[law/**/*.rb lib/fix/**/*.rb].freeze
      TOOLCHAIN_FILES = %w[.ruby-version Gemfile.lock].freeze
      MAX_EXCLUSION_SAMPLE = 20

      Source = Data.define(:path, :sha256, :bytes)

      attr_reader :root, :target, :sources, :source_signatures, :excluded, :law_ids, :adapters,
                  :max_passes, :budget_seconds, :created_at, :deadline_at,
                  :scope_digest, :source_digest, :law_digest, :authority_digest,
                  :law_source_digest, :toolchain_digest, :exclusion_digest,
                  :adapter_digest, :identity_digest, :digest

      def self.capture(root:, target:, files:, laws:, excluded: {}, adapters: {}, max_passes:, budget_seconds:)
        new(root:, target:, files:, laws:, excluded:, adapters:, max_passes:, budget_seconds:)
      end

      def initialize(root:, target:, files:, laws:, excluded:, adapters:, max_passes:, budget_seconds:)
        @root = File.expand_path(root).freeze
        @target = expand(target).freeze
        raise ArgumentError, "fix target escapes repository root" unless inside?(@target, @root)

        @created_at = Time.now.utc.iso8601.freeze
        @max_passes = positive_integer(max_passes, "max_passes")
        @budget_seconds = positive_integer(budget_seconds, "budget_seconds")
        @deadline_at = (Time.now.utc + @budget_seconds).iso8601.freeze

        @source_signatures = {}
        @sources = snapshot_sources(files).freeze
        @source_signatures = @source_signatures.freeze
        @scope_digest = digest_json(@sources.map(&:path)).freeze
        @source_digest = digest_json(@sources.map { |source| [source.path, source.sha256, source.bytes] }).freeze

        @excluded = deep_freeze(normalize_exclusions(excluded))
        @exclusion_digest = digest_json(@excluded).freeze
        @law_ids = Array(laws).map { |law| identifier(law) }.uniq.sort.freeze
        raise ArgumentError, "fix plan has no law identifiers" if @law_ids.empty?

        @adapters = normalize_json(adapters)
        @adapter_digest = digest_json(@adapters).freeze
        @authority = deep_freeze(authority_snapshot)
        @authority_digest = digest_json(@authority).freeze
        @law_sources = deep_freeze(law_source_snapshot)
        @law_source_digest = digest_json(@law_sources).freeze
        @law_digest = digest_json([@authority_digest, @law_source_digest, @law_ids]).freeze
        @toolchain = deep_freeze(toolchain_snapshot)
        @toolchain_digest = digest_json(@toolchain).freeze
        @identity_digest = digest_json(
          version: VERSION, target: relative(@target), scope_digest: @scope_digest,
          law_digest: @law_digest, authority_digest: @authority_digest,
          toolchain_digest: @toolchain_digest, adapter_digest: @adapter_digest,
          exclusion_digest: @exclusion_digest, max_passes: @max_passes,
          budget_seconds: @budget_seconds
        ).freeze
        @digest = digest_json(to_h(include_digest: false)).freeze
        freeze
      end

      # The journal receipt is compact; its separate run.files list retains the
      # exact eligible paths, while this digest pins every file's source bytes.
      def to_h(include_digest: true)
        value = {
          "version" => VERSION,
          "target" => relative(target),
          "eligible_files" => sources.size,
          "scope_digest" => scope_digest,
          "source_digest" => source_digest,
          "law_ids" => law_ids,
          "law_digest" => law_digest,
          "law_source_digest" => law_source_digest,
          "authority_digest" => authority_digest,
          "toolchain_digest" => toolchain_digest,
          "exclusion_digest" => exclusion_digest,
          "adapter_digest" => adapter_digest,
          "adapters" => adapters,
          "excluded" => excluded,
          "max_passes" => max_passes,
          "budget_seconds" => budget_seconds,
          "created_at" => created_at,
          "deadline_at" => deadline_at,
          "identity_digest" => identity_digest,
        }
        value["digest"] = digest if include_digest
        deep_freeze(value)
      end

      def source_hashes
        sources.to_h { |source| [source.path, source.sha256] }.freeze
      end

      private

      def expand(path) = File.expand_path(path.to_s, root)

      def inside?(path, base)
        path == base || path.start_with?(base + File::SEPARATOR)
      end

      def relative(path)
        return "." if path == root
        raise ArgumentError, "path escapes fix plan root: #{path}" unless inside?(path, root)

        path.delete_prefix(root + File::SEPARATOR)
      end

      def positive_integer(value, name)
        number = Integer(value)
        raise ArgumentError, "#{name} must be positive" unless number.positive?

        number
      end

      def identifier(law)
        value = law.respond_to?(:id) ? law.id : law
        id = value.to_s.strip
        raise ArgumentError, "fix plan law id is blank" if id.empty?

        id
      end

      def snapshot_sources(files)
        Array(files).map { |path| expand(path) }.uniq.sort.map do |path|
          raise ArgumentError, "fix source escapes repository root: #{path}" unless inside?(path, root)
          raise ArgumentError, "fix source is not a regular non-symlink file: #{relative(path)}" unless File.file?(path) && !File.symlink?(path)

          before = File.stat(path)
          sha256 = Digest::SHA256.file(path).hexdigest
          after = File.stat(path)
          signature = ->(stat) { [stat.dev, stat.ino, stat.size, stat.mtime.to_r, stat.ctime.to_r] }
          unless signature.call(before) == signature.call(after)
            raise ArgumentError, "fix source changed while the plan was being captured: #{relative(path)}"
          end

          relative_path = relative(path).freeze
          @source_signatures[relative_path] = signature.call(after).freeze
          Source.new(path: relative_path, sha256: sha256.freeze, bytes: after.size)
        end
      end

      def authority_snapshot
        AUTHORITY_FILES.to_h do |name|
          path = File.join(master_root, name)
          raise "governing authority unreadable: #{path}" unless File.file?(path) && !File.symlink?(path)

          [name, Digest::SHA256.file(path).hexdigest]
        end.sort.to_h
      end

      def law_source_snapshot
        required = RUNTIME_FILES.map { |path| File.join(master_root, path) }
        missing = required.reject { |path| File.file?(path) && !File.symlink?(path) }
        raise "Law runtime source unreadable: #{missing.map { |path| path.delete_prefix("#{master_root}/") }.join(", ")}" if missing.any?

        paths = required + RUNTIME_GLOBS.flat_map { |pattern| Dir.glob(File.join(master_root, pattern)) }
        paths.uniq.sort.to_h do |path|
          raise "Law runtime source is not a regular file: #{path}" unless File.file?(path) && !File.symlink?(path)

          [law_source_label(path), Digest::SHA256.file(path).hexdigest]
        end
      end

      def law_source_label(path)
        prefix = File.expand_path(master_root)
        if inside?(prefix, root)
          relative(path)
        else
          "external_master/#{path.delete_prefix(prefix + File::SEPARATOR)}"
        end
      end

      def toolchain_snapshot
        paths = TOOLCHAIN_FILES.filter_map do |name|
          path = File.join(root, name)
          [relative(path), Digest::SHA256.file(path).hexdigest] if File.file?(path) && !File.symlink?(path)
        end
        if File.directory?(target)
          discovered = TOOLCHAIN_FILES.flat_map { |name| Dir.glob(File.join(target, "**", name)) }
          discovered = discovered.uniq.reject do |path|
            path.split(File::SEPARATOR).any? { |part| %w[.git .master vendor node_modules tmp log storage].include?(part) }
          end
          discovered.each do |path|
            paths << [relative(path), Digest::SHA256.file(path).hexdigest] if File.file?(path) && !File.symlink?(path)
          end
        end
        {
          "ruby_engine" => (defined?(RUBY_ENGINE) ? RUBY_ENGINE : "ruby"),
          "ruby_version" => RUBY_VERSION,
          "ruby_platform" => RUBY_PLATFORM,
          "ruby_executable" => File.expand_path(RbConfig.ruby),
          "runtime_files" => paths.uniq.sort.to_h,
        }
      end

      def master_root
        local = File.join(root, "MASTER")
        candidate = if File.directory?(local)
                      local
                    elsif File.basename(root) == "MASTER"
                      root
                    elsif defined?(Master::ROOT) && File.directory?(Master::ROOT)
                      Master::ROOT
                    else
                      local
                    end
        expanded = File.expand_path(candidate)
        raise "MASTER law authority unavailable: #{expanded}" unless File.directory?(expanded)

        expanded
      end

      def normalize_exclusions(value)
        source = value.is_a?(Hash) ? value : {}
        counts = source.fetch(:counts, source.fetch("counts", source))
        path_reasons = source.fetch(:paths, source.fetch("paths", {}))
        sample_source = source[:sample] || source["sample"]
        sample_source ||= path_reasons.keys.sort.first(MAX_EXCLUSION_SAMPLE)
        sample = Array(sample_source).first(MAX_EXCLUSION_SAMPLE).map(&:to_s).sort
        rows = counts.respond_to?(:each_pair) ? counts.each_pair.to_a : []
        normalized_counts = rows.sort_by { |reason, _count| reason.to_s }.to_h do |reason, count|
          [reason.to_s, Integer(count)]
        rescue ArgumentError, TypeError
          [reason.to_s, 0]
        end
        supplied_digest = source[:paths_digest] || source["paths_digest"]
        paths_digest = supplied_digest || digest_json(
          path_reasons.respond_to?(:each_pair) ? path_reasons.sort.to_h : {},
        )
        { "counts" => normalized_counts, "sample" => sample, "paths_digest" => paths_digest.to_s }
      end

      def normalize_json(value)
        normalized = case value
                     when Hash
                       value.each_with_object({}) { |(key, child), out| out[key.to_s] = normalize_json(child) }.sort.to_h
                     when Array
                       value.map { |child| normalize_json(child) }
                     when Symbol
                       value.to_s
                     when String, Integer, Float, TrueClass, FalseClass, NilClass
                       value
                     else
                       value.to_s
                     end
        deep_freeze(normalized)
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, child| deep_freeze(key); deep_freeze(child) }
        when Array
          value.each { |child| deep_freeze(child) }
        when String
          value.freeze
        end
        value.freeze
      end

      def digest_json(value)
        Digest::SHA256.hexdigest(JSON.generate(value))
      end
    end
  end
end
