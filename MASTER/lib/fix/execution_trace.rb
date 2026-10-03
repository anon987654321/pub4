# frozen_string_literal: true

require_relative "../io/exec"

require "digest"
require "yaml"
require "tempfile"
require "prism"
require_relative "../review/scan/ast_fixer"

module Master
  module Fix
    # Deterministic preflight for /fix. It rereads the working repository before
    # mutation so the run begins from the same observed state it is about to
    # repair. Every tracked and non-ignored untracked file is hashed; Ruby files
    # are parsed without executing them; the boot surface and its configuration
    # are checked explicitly.
    class ExecutionTrace
      BOOT_CHAIN = %w[
        MASTER/bin/ruby
        MASTER/bin/cli
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
        MASTER/lib/fix/fix_loop.rb
        MASTER/lib/trace/event_bus.rb
        MASTER/lib/trace/logging.rb
        MASTER/lib/ground/redactor.rb
        MASTER/lib/ground/swallow.rb
      ].freeze

      BOOT_CONFIG = {
        "MASTER/data/laws.yml" => %w[zsh preserve_user_intent],
        "MASTER/data/soul.yml" => [],
        "MASTER/data/providers.yml" => [],
        "MASTER/data/patterns.yml" => [],
        "MASTER/data/limits.yml" => [],
        "MASTER/data/scan_coverage.yml" => []
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

      def initialize(root:, files: nil, digestor: nil, ruby_checker: nil, dependencies: {})
        @root = File.expand_path(root)
        @files = files
        @dependencies = dependencies
        @digestor = digestor || ->(path) { Digest::SHA256.file(path) }
        @ruby_checker = ruby_checker || ->(path) { RubyVM::InstructionSequence.compile_file(path) }
      end

      def run
        phases = {}
        failures = []
        files = file_list
        phases[:inventory] = "#{files.size} files"

        bytes = reread(files, failures)
        phases[:read] = "#{bytes} bytes"

        ruby_files = files.select { |path| Master.language_for(path) == "ruby" }
        syntax_check(ruby_files, failures)
        phases[:syntax] = "#{ruby_files.size} ruby files"

        verify_boot_surface(failures)
        phases[:boot_surface] = "#{BOOT_CHAIN.size} entry files"

        verify_configuration(failures)
        phases[:configuration] = "#{BOOT_CONFIG.size} files"

        verify_live_graph(failures)
        phases[:live_graph] = "scanner/fix_loop/council/bus"

        Result.new(
          ok: failures.empty?,
          files: files.size,
          bytes: bytes,
          ruby_files: ruby_files.size,
          phases: phases,
          failures: failures
        )
      rescue SyntaxError, StandardError => e
        Result.new(ok: false, files: 0, bytes: 0, ruby_files: 0,
                   phases:, failures: ["execution trace crashed: #{e.class}: #{e.message}"])
      end

      private

      def file_list
        return Array(@files).map { |path| File.expand_path(path, @root) } if @files

        output, status = Master::Io::Exec.capture2e(
          "git", "-C", @root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"
        )
        raise "cannot inventory repository: #{output.to_s.lines.last.to_s.strip}" unless status.success?

        output.split("\x00").reject(&:empty?).map { |path| File.join(@root, path) }.select { |path| File.file?(path) }
      end

      def reread(files, failures)
        files.sum do |path|
          digest = @digestor.call(path)
          digest.to_s.empty? ? 0 : File.size(path)
        rescue StandardError => e
          failures << "#{relative(path)}: reread failed: #{e.class}: #{e.message}"
          0
        end
      end

      def syntax_check(files, failures)
        files.each do |path|
          source = File.read(path, encoding: "UTF-8")
          content = safe_transport_unwrap(source)

          if content == source
            @ruby_checker.call(path)
          else
            Tempfile.create(["execution-trace-", ".rb"], binmode: true) do |tmp|
              tmp.write(content)
              tmp.flush
              @ruby_checker.call(tmp.path)
            end
          end
        # SyntaxError descends from ScriptError, not StandardError — without
        # naming it here the unparseable file kills the whole check instead of
        # becoming the finding this preflight exists to report.
        rescue SyntaxError, StandardError => e
          failures << "#{relative(path)}: syntax failed: #{e.class}: #{e.message}"
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
          failures << "#{path}: missing" unless File.file?(full)
        end
      end

      def verify_configuration(failures)
        BOOT_CONFIG.each do |path, required_sections|
          full = File.join(@root, path)
          unless File.file?(full)
            failures << "#{path}: missing"
            next
          end

          body = Master.load_yaml(full)
          unless body.is_a?(Hash)
            failures << "#{path}: expected a hash"
            next
          end

          required_sections.each do |section|
            failures << "#{path}: missing #{section}: section" unless body.key?(section)
          end
        rescue StandardError => e
          failures << "#{path}: unreadable: #{e.class}: #{e.message}"
        end
      end

      def verify_live_graph(failures)
        required = {
          scanner: [:scan, :scan_dir],
          fix_loop: [:run, :preview],
          deliberation: [:review_convergent],
          bus: [:publish, :subscribe]
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
