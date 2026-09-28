# frozen_string_literal: true

require "rubygems"
require_relative "dependency_manager"

module Master
  module Boot
    module Entrypoint
      module_function

      def prepare!(root:, env: ENV, out: $stderr, argv: ARGV, program: $PROGRAM_NAME)
        root = File.expand_path(root)
        reexec_pinned_ruby!(root:, env:, out:, argv:, program:)
        result = DependencyManager.ensure!(root:, env:, out:)
        unless result.ok
          out.puts("deps0: #{result.message}")
          detail = result.output.to_s.strip
          out.puts(detail) unless detail.empty?
          exit 78
        end

        activate_bundle!(root)

        true
      end

      def activate_bundle!(root)
        gemfile = File.join(root, "Gemfile")
        return unless File.file?(gemfile)

        ENV["BUNDLE_GEMFILE"] = gemfile
        require "bundler/setup"
      end

      def reexec_pinned_ruby!(root:, env:, out:, argv:, program:)
        return if env["MASTER_ALLOW_UNPINNED_RUBY"] == "1"

        version_file = File.join(root, ".ruby-version")
        return unless File.file?(version_file)

        expected = File.read(version_file).strip
        return if expected.empty? || Gem::Version.new(RUBY_VERSION) == Gem::Version.new(expected)

        wrapper = File.join(root, "bin", "ruby")
        unless File.executable?(wrapper)
          out.puts("ruby0: #{RUBY_VERSION}; #{expected} required; #{wrapper} is unavailable")
          exit 78
        end

        # bin/ruby owns platform-specific Ruby acquisition. Passing the original
        # program and argv through it lets every executable share that logic.
        return if File.expand_path(program) == File.expand_path(wrapper)

        out.puts("ruby0: switching #{RUBY_VERSION} -> #{expected}")
        exec(wrapper, File.expand_path(program), *argv)
      rescue ArgumentError
        out.puts("ruby0: invalid .ruby-version in #{version_file}")
        exit 78
      end
    end
  end
end
