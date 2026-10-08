# frozen_string_literal: true

require "open3"
require "rbconfig"

module StudioIsolation
  ROOT = File.expand_path(__dir__)
  RUBY = RbConfig.ruby

  Outcome = Struct.new(:name, :file, :alone, :suite, keyword_init: true)

  def self.run(pattern: nil, io: $stdout)
    new(pattern: pattern, io: io).run
  end

  def initialize(pattern: nil, io: $stdout)
    @pattern = pattern
    @io = io
  end

  def files = Dir.glob(File.join(ROOT, "test", "test_dilla_*.rb")).sort

  def test_names(file)
    body = File.read(file)
    body.scan(/^\s*def (test_\w+)/).flatten +
      body.scan(/^\s*test\s+["']([^"']+)["']/).flatten.map { |n| "test_#{n.gsub(/\W+/, "_")}" }
  end

  def run
    rounds = suite_rounds
    suite_failures = rounds.flatten.uniq
    intermittent = suite_failures.reject { |name| rounds.all? { |round| round.include?(name) } }

    names = files.flat_map { |file| test_names(file).map { |name| [name, file] } }
    names = names.select { |name, _| name.include?(@pattern) } if @pattern
    @io.puts "isolation0: #{names.length} tests, #{rounds.length} suite rounds"

    outcomes = names.map do |name, file|
      alone = passes_alone?(file, name)
      Outcome.new(name:, file:, alone:, suite: !suite_failures.include?(name))
    end

    report(outcomes, intermittent, rounds.length)
  end

  private

  def passes_alone?(file, name)
    _out, status = Open3.capture2e(RUBY, "-I#{File.join(ROOT, "test")}", file, "-n", name, chdir: ROOT)
    status.success?
  end

  def suite_rounds
    rounds = Integer(ENV.fetch("SUITE_ROUNDS", "3"))
    rounds.times.map do
      out, = Open3.capture2e(
        RUBY, "-I#{File.join(ROOT, "test")}",
        "-e", files.map { |file| "require #{file.dump}" }.join("\n"),
        chdir: ROOT
      )
      out.scan(/^\s*\w+#(test_\w+)/).flatten.uniq
    end
  end

  def report(outcomes, intermittent, rounds)
    suite_only = outcomes.select { |outcome| outcome.alone && !outcome.suite }
    alone_only = outcomes.select { |outcome| !outcome.alone && outcome.suite }

    unless intermittent.empty?
      @io.puts "isolation0: intermittent failures=#{intermittent.length} across #{rounds} rounds"
    end
    unless suite_only.empty?
      @io.puts "isolation0: passes alone, fails in suite=#{suite_only.map(&:name).join(",")}"
    end
    unless alone_only.empty?
      @io.puts "isolation0: fails alone, passes in suite=#{alone_only.map(&:name).join(",")}"
    end
    return 0 if suite_only.empty? && alone_only.empty? && intermittent.empty?

    suite_only.length + alone_only.length + intermittent.length
  end
end
