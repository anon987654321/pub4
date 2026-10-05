#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"
require_relative "../gates/support/gate_result"

module Deploy
  # MASTER/tools is the reasoning and governance utility plane. Media production
  # belongs to STUDIO and is intentionally not enumerated here.
  class ToolsGate
    ROOT = File.expand_path(__dir__)
    VENDORED = %r{/(?:scratch|tmp|node_modules|venv|\.venv|site-packages|vendor|storage|\.cache|coverage)/}
    TREES = [
      { name: "tools", glob: "**/*", entry: nil, owner: "MASTER governance utilities" },
    ].freeze
    PROBE_TIMEOUT = Integer(ENV.fetch("MASTER_TOOLS_PROBE_TIMEOUT", "60"))
    PREDICTED_FINDINGS = {
      "tools parse:" => "a file that does not parse",
      "tools load:" => "an entry point that raises at load",
      "tools inventory:" => "a file belonging to no declared tree",
    }.freeze

    def self.run(...) = new(...).run

    def initialize(root: ROOT, trees: TREES)
      @root = root
      @trees = trees
      @result = GateResult.new
    end

    def run
      files = source_files
      return @result.inconclusive!("no Ruby found under #{@root}") if files.empty?

      check_parse(files)
      check_frozen_literals(files)
      check_inventory(files)
      check_entry_points
      self_check
      @result
    end

    def source_files
      rb = Dir[File.join(@root, "**", "*.rb")]
      scripts = Dir[File.join(@root, "**", "*")].select { |path| ruby_shebang?(path) }
      (rb + scripts).reject { |path| vendored?(path) }.uniq.sort
    end

    def vendored?(path)
      "/#{path.delete_prefix(@root + "/")}" =~ VENDORED
    end

    private

    def relative(path) = path.delete_prefix(@root + "/")

    def check_parse(files)
      files.each do |path|
        RubyVM::AbstractSyntaxTree.parse_file(path)
        @result.checked!
      rescue SyntaxError => e
        @result.fail("tools parse: #{relative(path)} — #{e.message.lines.first.to_s.strip}")
      end
    end

    def check_frozen_literals(files)
      files.each do |path|
        next if File.foreach(path).first(3).any? { |line| line.include?("frozen_string_literal: true") }

        @result.fail("tools frozen: #{relative(path)} has no frozen_string_literal magic comment", severity: :soft)
      end
      @result.checked!
    end

    def check_inventory(files)
      orphans = files.reject { |path| @trees.any? { |tree| tree_matches?(tree, path) } }
      @result.checked!
      return if orphans.empty?

      orphans.each { |path| @result.fail("tools inventory: #{relative(path)} belongs to no declared tree") }
    end

    def check_entry_points
      @trees.each do |tree|
        entry = tree[:entry]
        next unless entry

        path = File.join(@root, entry)
        unless File.file?(path)
          @result.fail("tools load: #{entry} does not exist")
          next
        end

        unless guarded?(path)
          @result.fail("tools load: #{entry} has no PROGRAM_NAME guard", severity: :soft)
          next
        end

        probe_load(tree[:name], path)
      end
    end

    def guarded?(path)
      File.read(path).match?(/__FILE__\s*==\s*(\$PROGRAM_NAME|\$0)/)
    end

    def probe_load(name, path)
      script = "$PROGRAM_NAME = \"tools_gate_probe\"\nload #{path.dump}\n"
      out, status = capture_with_timeout(script)

      unless status
        @result.inconclusive!("tools load: #{name} probe exceeded #{PROBE_TIMEOUT}s")
        return
      end

      @result.checked!
      return if status.success?

      first = out.to_s.lines.grep_v(/^\s*from /).first.to_a.map(&:strip).reject(&:empty?)
      @result.fail("tools load: #{relative(path)} does not boot — #{first.join(' | ')}")
    end

    def capture_with_timeout(script)
      output = +""
      status = nil
      thread = Thread.new do
        output, status = Open3.capture2e(RbConfig.ruby, "-e", script)
      end
      return thread.value && [output, status] if thread.join(PROBE_TIMEOUT)

      thread.kill
      [output, nil]
    rescue StandardError => e
      ["#{e.class}: #{e.message}", nil]
    end

    def self_check
      require "tmpdir"
      require "fileutils"
      Dir.mktmpdir("tools-gate-selfcheck") do |dir|
        FileUtils.mkdir_p(File.join(dir, "nested"))
        File.write(File.join(dir, "good.rb"), "# frozen_string_literal: true\n")
        File.write(File.join(dir, "bad.rb"), "module Broken\n")
        fixture = self.class.new(root: dir, trees: [{ name: "tools", glob: "good.rb", entry: nil }])
        result = fixture.send(:run_without_self_check)
        @result.checked!
        @result.fail("tools self-check: parse fixture did not fail") unless result.failures.any? { |f| f.include?("tools parse: bad.rb") }
        @result.fail("tools self-check: inventory fixture did not fail") unless result.failures.any? { |f| f.include?("tools inventory:") }
      end
    rescue StandardError => e
      @result.inconclusive!("self-check could not run (#{e.class}: #{e.message})")
    end

    def run_without_self_check
      files = source_files
      check_parse(files)
      check_frozen_literals(files)
      check_inventory(files)
      check_entry_points
      @result
    end

    def ruby_shebang?(path)
      return false if File.extname(path) != "" || vendored?(path) || !File.file?(path)

      File.open(path, "rb") { |file| file.readline(256).match?(/\A#!.*\bruby\b/) }
    rescue EOFError
      false
    rescue SystemCallError
      false
    end
  end
end