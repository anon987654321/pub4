# frozen_string_literal: true

require_relative "../io/exec"
require "timeout"
require "tempfile"
require "prism"
require_relative "scan/ast_fixer"
require_relative "execution_snapshot"
require_relative "../boot/paths"

module Master
  module Fix
    # Deterministic preflight for /fix. It rereads the working repository before
    # mutation so the run begins from the same observed state it is about to
    # repair. Every tracked and non-ignored untracked file is hashed; Ruby files
    # are parsed without executing them; the boot surface and its configuration
    # are checked explicitly.
    class ExecutionTrace
      include ExecutionSnapshot
      BOOT_CHAIN = %w[
        MASTER/bin/ruby
        MASTER/bin/master
        MASTER/lib/boot/entrypoint.rb
        MASTER/lib/boot/dependency_manager.rb
        MASTER/lib/master.rb
        MASTER/lib/boot/master_boot.rb
        MASTER/lib/builder.rb
        MASTER/lib/builder/boot_phases.rb
        MASTER/lib/builder/ai_boot.rb
        MASTER/lib/cli/turn_router.rb
        MASTER/lib/cli/pipeline.rb
        MASTER/lib/cli/session.rb
        MASTER/lib/cli/command_registry/review.rb
        MASTER/lib/cli/routing/model_router.rb
        MASTER/lib/cli/routing/model_router/route_policy.rb
        MASTER/lib/cli/routing/model_router/selection.rb
        MASTER/lib/io/lane_state.rb
        MASTER/lib/fix/fix_loop.rb
        MASTER/lib/fix/outcome_policy.rb
        MASTER/lib/fix/fix_loop/completion.rb
        MASTER/lib/fix/fix_loop/lifecycle.rb
        MASTER/lib/fix/fix_loop/pass_execution.rb
        MASTER/lib/trace/event_bus.rb
        MASTER/lib/trace/logging.rb
        MASTER/lib/ground/redactor.rb
        MASTER/lib/ground/swallow.rb
      ].freeze

      BOOT_CONFIG = {
        "MASTER/data/laws.yml" => %w[transformation_policy CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS],
        "MASTER/data/soul.yml" => %w[absolute],
        "MASTER/data/providers.yml" => [],
        "MASTER/data/patterns.yml" => [],
        "MASTER/data/console.yml" => [], "MASTER/data/scan.yml" => [], "MASTER/data/budgets.yml" => [],
        "MASTER/data/scan_coverage.yml" => [],
      }.freeze

      Result = Data.define(:ok, :files, :bytes, :ruby_files, :phases, :failures) do
        def clean?
          ok && failures.empty?
        end

        def summary
          state = clean? ? "clean" : "failed"
          "execution_trace: #{state}, #{files} files, #{bytes} bytes, #{ruby_files} ruby files"
        end
      end

      def initialize(root:, files: nil, scope: nil, digestor: nil, ruby_checker: nil, dependencies: {})
        @root = File.expand_path(root)
        @files = files
        @scope = scope
        @dependencies = dependencies
        @digestor = digestor || ->(path) { Digest::SHA256.file(path) }
        @ruby_checker = ruby_checker
        @fingerprints = {}
      end

      def run
        @fingerprints = {}
        phases = {}
        failures = []
        files = file_list
        observed_files = observation_paths(files)
        phases[:inventory] = "#{files.size} scoped files"

        bytes = reread(observed_files, failures)
        phases[:read] = "#{bytes} bytes across #{observed_files.size} observed files"

        ruby_files = files.select { |path| !File.symlink?(path) && Master.language_for(path) == "ruby" }
        syntax_check(ruby_files, failures)
        phases[:syntax] = "#{ruby_files.size} ruby files"

        verify_boot_surface(failures)
        phases[:boot_surface] = "#{BOOT_CHAIN.size} entry files"

        verify_configuration(failures)
        phases[:configuration] = "#{BOOT_CONFIG.size} files"

        verify_live_graph(failures)
        phases[:live_graph] = "scanner/fix_loop/council/bus"

        verify_snapshot(@fingerprints.keys, failures)
        verify_inventory(files, failures)
        phases[:snapshot] = "#{@fingerprints.size} files checked"

        Result.new(
          ok: failures.empty?,
          files: files.size,
          bytes:,
          ruby_files: ruby_files.size,
          phases:,
          failures:,
        )
      rescue SyntaxError, StandardError => e
        Result.new(ok: false, files: 0, bytes: 0, ruby_files: 0,
                   phases:, failures: ["execution trace crashed: #{e.class}: #{e.message}"])
      end

      private

      # ExecutionTrace always inventories from the pub4 repository root. Scope
      # names are git pathspecs, while an empty scope means the whole checkout.
      def scope_paths
        scopes = Array(@scope).compact.flat_map { |scope| scope.to_s.split(/[\s,]+/) }.reject(&:empty?)
        return [] if scopes.empty?
        return [] if scopes.uniq.sort == MasterPaths::TREES.sort

        repo = File.expand_path(@root)
        scopes.map do |scope|
          full = File.expand_path(scope, repo)
          next if full == repo
          unless full.start_with?("#{repo}#{File::SEPARATOR}")
            raise ArgumentError, "execution trace scope outside repository: #{scope.inspect}"
          end
          unless File.exist?(full)
            raise ArgumentError, "execution trace scope does not exist: #{scope.inspect}"
          end
          full.delete_prefix("#{repo}#{File::SEPARATOR}")
        end.compact.uniq
      end

      # Scan scope stays narrow, but the governing boot chain and config are
      # fingerprinted at the same starting point as the selected target.
      def observation_paths(files)
        required = (BOOT_CHAIN + BOOT_CONFIG.keys).map { |path| File.join(@root, path) }
        (files + required).uniq
      end

      def file_list
        return Array(@files).map { |path| File.expand_path(path, @root) } if @files

        args = ["git", "-C", @root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        scopes = scope_paths
        args.concat(["--", *scopes]) unless scopes.empty?
        output, status = Master::Io::Exec.capture2e(*args)
        raise "cannot inventory repository: #{output.to_s.lines.last.to_s.strip}" unless status.success?

        paths = output.split("\x00").reject(&:empty?).map { |path| File.join(@root, path) }
        paths = paths.select { |path| File.file?(path) || File.symlink?(path) || !File.exist?(path) }
        if scopes.any? && paths.empty?
          raise ArgumentError, "execution trace scope contains no inventoried files: #{scopes.join(", ")}"
        end
        paths
      end

      # The scoped inventory remains separate from mandatory boot inputs:
      # a scope may fingerprint more files without silently scanning more trees.
      def verify_inventory(files, failures)
        current = file_list
        return if current.sort == files.sort

        added = (current - files).map { |path| relative(path) }.first(5)
        removed = (files - current).map { |path| relative(path) }.first(5)
        changes = []
        changes << "added: #{added.join(", ")}" unless added.empty?
        changes << "removed: #{removed.join(", ")}" unless removed.empty?
        failures << "file inventory changed during preflight (#{changes.join("; ")})"
      rescue StandardError => e
        failures << "file inventory verification failed: #{e.class}: #{e.message}"
      end

      def syntax_check(files, failures)
        files.each do |path|
          resolve_inside_root(path)
          source = File.read(path, encoding: "UTF-8")
          next unless content_matches_snapshot?(path, source, failures, phase: "syntax validation")

          content = safe_transport_unwrap(source)
          check_ruby_source(path, content)
        # SyntaxError descends from ScriptError, not StandardError — without
        # naming it here the unparseable file kills the whole check instead of
        # becoming the finding this preflight exists to report.
        rescue SyntaxError, StandardError => e
          failures << "#{relative(path)}: syntax failed: #{e.class}: #{e.message}"
        end
      end

      # Parse the exact bytes already fingerprinted, not a second read of the
      # live path. Test-injected checkers receive an isolated temporary file;
      # the production path compiles the captured source with its real filename.
      def check_ruby_source(path, content)
        if @ruby_checker
          Tempfile.create(["execution-trace-", ".rb"], binmode: true) do |tmp|
            tmp.write(content)
            tmp.flush
            @ruby_checker.call(tmp.path)
          end
        else
          RubyVM::InstructionSequence.compile(content, path, path, 1)
        end
      end

      # Never let AstFixer repair the tree merely so preflight can call it
      # parseable. Preflight measures the bytes on disk; the sole exception is
      # accidental transport markup, which may be stripped only when the
      # resulting Ruby parses. A malformed program therefore remains a failed
      # preflight even if a fixer could invent a valid candidate.
      def safe_transport_unwrap(source)
        return source if source.empty? || Prism.parse(source).success?

        candidate = source.dup
        changed = false
        if candidate.start_with?("<sub>")
          candidate.delete_prefix!("<sub>")
          changed = true
        end
        if candidate.sub!(%r{</sub>\s*\z}, "")
          changed = true
        end

        changed && Prism.parse(candidate).success? ? candidate : source
      end

      def verify_boot_surface(failures)
        BOOT_CHAIN.each do |path|
          full = File.join(@root, path)
          unless File.file?(full)
            failures << "#{path}: missing"
            next
          end

          resolve_inside_root(full)
          @fingerprints[full] ||= fingerprint(full)
        rescue StandardError => e
          failures << "#{path}: boot surface unreadable: #{e.class}: #{e.message}"
        end
      end

      def verify_configuration(failures)
        BOOT_CONFIG.each do |path, required_sections|
          full = File.join(@root, path)
          unless File.file?(full)
            failures << "#{path}: missing"
            next
          end

          body = configuration_body(path, full, failures)
          next if body.nil?
          unless body.is_a?(Hash)
            failures << "#{path}: expected a hash"
            next
          end

          required_sections.each do |section|
            failures << "#{path}: missing #{section}: section" unless body.key?(section)
          end
        end
      end

      def configuration_body(path, full, failures)
        resolve_inside_root(full)
        @fingerprints[full] ||= fingerprint(full)
        content = Master.read_yaml_content(full)

        return unless content_matches_snapshot?(full, content, failures, phase: "configuration validation")
        parsed = Timeout.timeout(Master::YAML_LOAD_TIMEOUT_S) do
          Master.parse_yaml_content(content, source: full)
        end
        parsed.nil? ? {} : parsed
      rescue StandardError => e
        failures << "#{path}: unreadable: #{e.class}: #{e.message}"
        nil
      end

      def verify_live_graph(failures)
        required = {
          scanner: [:scan, :scan_dir],
          fix_loop: [:run, :preview],
          deliberation: [:review_convergent],
          bus: [:publish, :subscribe],
        }

        required.each do |name, methods|
          object = @dependencies[name]
          failures << "live_graph: #{name} missing" unless object
          next unless object

          methods.each do |method|
            failures << "live_graph: #{name} missing ##{method}" unless object.respond_to?(method)
          end
        end
      end

      def relative(path)
        path.delete_prefix(@root + File::SEPARATOR)
      end
    end
  end
end
