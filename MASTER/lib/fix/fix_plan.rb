# frozen_string_literal: true

require "digest"
require "json"
require "rbconfig"
require "time"

module Master
  module Fix
    # Immutable pre-mutation contract for one /fix attempt. The journal keeps
    # its compact receipt; the running process retains the exact file snapshot.
    # A new generation is captured after a resumed or structurally changed scope.
    class FixPlan
      VERSION = 1
      AUTHORITY_FILES = %w[soul.yml laws.yml].freeze
      TOOLCHAIN_FILES = %w[.ruby-version Gemfile.lock].freeze
      LAW_RUNTIME_FILES = %w[
        lib/review/scan/law.rb
        lib/review/scan/law_dsl.rb
        lib/fix/scanner.rb
        lib/fix/scan/file_processor.rb
        lib/fix/opportunity_pass.rb
        lib/fix/visual_pass.rb
        lib/fix/four_stream_assessment.rb
        lib/fix/fix_loop.rb
        lib/fix/fix_loop/completion.rb
        lib/fix/fix_loop/lifecycle.rb
        lib/fix/fix_loop/pass_execution.rb
        lib/fix/fix_loop/pass_runner.rb
        lib/fix/convergence_discipline.rb
        lib/fix/run_journal.rb
        lib/fix/outcome_policy.rb
        lib/fix/fix_plan.rb
      ].freeze
      LAW_RUNTIME_GLOBS = %w[law/**/*.rb lib/review/scan/laws/**/*.rb].freeze
      MAX_EXCLUSION_REASONS = 40

      Source = Data.define(:path, :sha256, :bytes)

      attr_reader :root, :target, :sources, :excluded, :law_ids, :adapters,
                  :max_passes, :budget_seconds, :created_at, :deadline_at,
                  :scope_digest, :source_digest, :law_digest, :law_source_digest,
                  :authority_digest, :exclusion_digest, :toolchain_digest,
                  :adapter_digest, :identity_digest, :digest

      def self.capture(root:, target:, files:, laws:, excluded: {}, adapters: {}, max_passes:, budget_seconds:,
                       deadline_at: nil)
        new(root:, target:, files:, laws:, excluded:, adapters:, max_passes:, budget_seconds:, deadline_at:)
      end

      def initialize(root:, target:, files:, laws:, excluded:, adapters:, max_passes:, budget_seconds:, deadline_at: nil)
        @root = File.expand_path(root).freeze
        @target = expand(target).freeze
        raise ArgumentError, "fix target escapes repository root" unless inside?(@target, @root)

        @created_at = Time.now.utc.iso8601.freeze
        @max_passes = positive_integer(max_passes, "max_passes")
        @budget_seconds = positive_integer(budget_seconds, "budget_seconds")
        @deadline_at = if deadline_at.to_s.strip.empty?
                         (Time.now.utc + @budget_seconds).iso8601
                       else
                         Time.iso8601(deadline_at.to_s).utc.iso8601
                       end.freeze
        @sources = snapshot_sources(files).freeze
        raise ArgumentError, "fix plan has no eligible source files" if @sources.empty?

        @excluded = deep_freeze(normalize_exclusions(excluded))
        @exclusion_digest = digest_json(@excluded).freeze
        @law_ids = Array(laws).map { |law| identifier(law) }.uniq.sort.freeze
        raise ArgumentError, "fix plan has no law identifiers" if @law_ids.empty?

        @adapters = normalize_json(adapters)
        @adapter_digest = digest_json(@adapters).freeze
        @scope_digest = digest_json(@sources.map(&:path)).freeze
        @source_digest = digest_json(@sources.map { |source| [source.path, source.sha256, source.bytes] }).freeze
        @authority_digests = deep_freeze(authority_digests)
        @authority_digest = digest_json(@authority_digests).freeze
        @law_runtime_digests = deep_freeze(law_runtime_digests)
        @law_source_digest = digest_json(@law_runtime_digests).freeze
        @law_digest = digest_json([@authority_digest, @law_source_digest, @law_ids]).freeze
        @toolchain = deep_freeze(toolchain_snapshot)
        @toolchain_digest = digest_json(@toolchain).freeze
        @identity_digest = digest_json(
          version: VERSION, target: relative(@target), scope_digest: @scope_digest,
          law_digest: @law_digest, law_source_digest: @law_source_digest,
          authority_digest: @authority_digest, exclusion_digest: @exclusion_digest,
          toolchain_digest: @toolchain_digest, adapter_digest: @adapter_digest, adapters: @adapters,
          max_passes: @max_passes, budget_seconds: @budget_seconds
        ).freeze
        @digest = digest_json(to_h(include_digest: false)).freeze
        freeze
      end

      # A plan digest includes the source generation; identity_digest is stable
      # across mutations to those files but not across scope, Law, toolchain or adapter drift.
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
          "exclusion_digest" => exclusion_digest,
          "toolchain_digest" => toolchain_digest,
          "toolchain" => @toolchain,
          "adapters" => adapters,
          "adapter_digest" => @adapter_digest,
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
          signature = ->(stat) { [stat.dev, stat.ino, stat.size, stat.mtime.to_r] }
          raise ArgumentError, "fix source changed while the plan was being captured: #{relative(path)}" unless signature.call(before) == signature.call(after)

          Source.new(path: relative(path).freeze, sha256: sha256.freeze, bytes: after.size)
        end
      end

      def authority_digests
        authority_root = if defined?(Master::ROOT) && File.directory?(Master::ROOT)
                           Master::ROOT
                         else
                           File.join(root, "MASTER")
                         end
        AUTHORITY_FILES.to_h do |name|
          path = File.join(authority_root, "data", name)
          raise "governing authority unreadable: #{path}" unless File.file?(path)

          [name, Digest::SHA256.file(path).hexdigest]
        end.sort.to_h
      end

      def law_runtime_digests
        authority_root = if defined?(Master::ROOT) && File.directory?(Master::ROOT)
                           Master::ROOT
                         else
                           File.join(root, "MASTER")
                         end
        patterns = LAW_RUNTIME_GLOBS.map { |pattern| File.join(authority_root, pattern) }
        paths = LAW_RUNTIME_FILES.map { |path| File.join(authority_root, path) } +
          patterns.flat_map { |pattern| Dir.glob(pattern) }
        paths = paths.uniq.sort
        missing = LAW_RUNTIME_FILES.map { |path| File.join(authority_root, path) }.reject { |path| File.file?(path) }
        raise "Law runtime source unreadable: #{missing.map { |path| relative(path) }.join(", ")}" if missing.any?

        paths.to_h do |path|
          raise "Law runtime source is not a regular file: #{relative(path)}" unless File.file?(path) && !File.symlink?(path)

          [relative(path), Digest::SHA256.file(path).hexdigest]
        end
      end

      def toolchain_snapshot
        paths = TOOLCHAIN_FILES.filter_map do |name|
          path = File.join(root, name)
          [relative(path), Digest::SHA256.file(path).hexdigest] if File.file?(path) && !File.symlink?(path)
        end
        if File.directory?(target)
          patterns = TOOLCHAIN_FILES.map { |name| File.join(target, "**", name) }
          discovered = patterns.flat_map { |pattern| Dir.glob(pattern) }
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

      def normalize_exclusions(value)
        rows = value.respond_to?(:each_pair) ? value.each_pair.to_a : []
        rows.sort_by { |reason, _count| reason.to_s }.first(MAX_EXCLUSION_REASONS).to_h do |reason, count|
          [reason.to_s, Integer(count)]
        rescue ArgumentError, TypeError
          [reason.to_s, 0]
        end
      end

      def normalize_json(value)
        normalized = case value
                     when Hash
                       value.each_with_object({}) { |(key, child), out| out[key.to_s] = normalize_json(child) }
                             .sort.to_h
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
