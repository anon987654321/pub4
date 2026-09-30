require_relative "../io/exec"
# frozen_string_literal: true

require "digest"
require "yaml"

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

      BOOT_CONFIG = %w[
        MASTER/data/rules.yml
        MASTER/data/soul.yml
        MASTER/data/providers.yml
        MASTER/data/patterns.yml
        MASTER/data/limits.yml
        MASTER/data/scan_coverage.yml
      ].freeze

      RUBY_EXTENSIONS = %w[.rb .rake .ru .gemspec].freeze

      Result = Data.define(:ok, :files, :bytes, :ruby_files, :phases, :failures) do
        def clean?
          ok && failures.empty?
        end

        def summary
          state = clean? ? "clean" : "failed"
          "execution_trace: #{state}, #{files} files, #{bytes} bytes, #{ruby_files} ruby files"
        end
      end

      def initialize(root:, files: nil, digestor: nil, ruby_checker: nil)
        @root = File.expand_path(root)
        @files = files
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

        ruby_files = files.select { |path| RUBY_EXTENSIONS.include?(File.extname(path).downcase) }
        syntax_check(ruby_files, failures)
        phases[:syntax] = "#{ruby_files.size} ruby files"

        verify_boot_surface(failures)
        phases[:boot_surface] = "#{BOOT_CHAIN.size} entry files"

        verify_configuration(failures)
        phases[:configuration] = "#{BOOT_CONFIG.size} files"

        Result.new(ok: failures.empty?, files: files.size, bytes:, ruby_files: ruby_files.size,
                   phases:, failures:)
      rescue StandardError => e
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
          @ruby_checker.call(path)
        rescue StandardError => e
          failures << "#{relative(path)}: syntax failed: #{e.class}: #{e.message}"
        end
      end

      def verify_boot_surface(failures)
        BOOT_CHAIN.each do |path|
          full = File.join(@root, path)
          failures << "#{path}: missing" unless File.file?(full)
        end
      end

      def verify_configuration(failures)
        BOOT_CONFIG.each do |path|
          full = File.join(@root, path)
          unless File.file?(full)
            failures << "#{path}: missing"
            next
          end

          body = Master.load_yaml(full)
          failures << "#{path}: expected a hash" unless body.is_a?(Hash)
        rescue StandardError => e
          failures << "#{path}: unreadable: #{e.class}: #{e.message}"
        end
      end

      def relative(path)
        path.delete_prefix(@root + File::SEPARATOR)
      end
    end
  end
end
