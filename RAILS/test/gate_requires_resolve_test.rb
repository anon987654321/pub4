# frozen_string_literal: true

require "minitest/autorun"

# Every gate must be able to load itself.
#
# `rails_runtime` required "lib/production" for months after that file moved to
# "lib/host/production" — the gates were sorted into host/live/meta/rendered/
# research/source and this was the one caller the move missed. It failed at
# require time rather than at a check, so the composite reported a red gate that
# named no finding, and a red gate that names no finding is the easiest kind to
# stop reading.
#
# That is the half-landed-move defect this tree keeps producing, and it is worth
# a test rather than a fix because the next reorganisation will do it again.
# Text, not loading: these files run under bare ruby outside any app bundle and
# several of them do real work at require time, so actually requiring them here
# would boot Chrome and hit the network.
class GateRequiresResolveTest < Minitest::Test
  GATES = File.expand_path("../gates", __dir__)

  # `require_relative "x"` resolves against the requiring file's directory, and
  # matches x.rb or a directory named x. Interpolated paths are skipped rather
  # than guessed at — a require built from a variable is not a claim this test
  # can check, and pretending otherwise would make it fail on correct code.
  def each_relative_require
    return to_enum(:each_relative_require) unless block_given?

    Dir.glob(File.join(GATES, "**", "*.rb")).sort.each do |file|
      dir = File.dirname(file)
      File.readlines(file).each_with_index do |line, index|
        next if line.lstrip.start_with?("#")
        next unless (match = line.match(/require_relative\s+["']([^"'#]+)["']/))

        yield(file, index + 1, match[1], dir)
      end
    end
  end

  def test_every_gate_require_relative_resolves
    broken = each_relative_require.reject do |_file, _line, target, dir|
      path = File.expand_path(target, dir)
      File.exist?("#{path}.rb") || File.directory?(path)
    end

    assert_empty broken.map { |file, line, target, _dir|
      "#{file.sub("#{GATES}/", 'gates/')}:#{line} requires #{target.inspect}, which does not exist"
    }, "a gate that cannot load measures nothing, and fails without naming a finding"
  end

  # The runner names each gate's file in gates.yml. A row pointing at a file that
  # is not there is the same failure one level up: the composite goes red and the
  # reason is a missing path rather than a finding.
  def test_every_gate_row_names_a_file_that_exists
    require "yaml"
    rows = YAML.safe_load_file(File.join(GATES, "gates.yml"))
    entries = rows.is_a?(Hash) ? rows.fetch("gates", rows) : rows
    skip "gates.yml is not a mapping of gate rows" unless entries.is_a?(Hash)

    missing = entries.filter_map do |name, row|
      next unless row.is_a?(Hash)

      required = row["require"]
      next if required.nil? || required.to_s.empty?

      path = File.expand_path(required.to_s, GATES)
      next if File.exist?(path) || File.exist?("#{path}.rb")

      "#{name} -> #{required}"
    end

    assert_empty missing, "gates.yml rows naming a file that is not on disk"
  end
end
