# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "yaml"

# --explain is the answer to "what does --all do and what changes its verdict",
# asked without spending the run. It is only worth having if it names every
# registered gate and every switch that decides a verdict out of sight — the
# auditor's warning half is advisory unless GATE_AUDITOR_STRICT is set, and
# before --explain that was written only inside frontend_auditor.rb.
class RunnerExplainTest < Minitest::Test
  RUNNER = File.expand_path("../../../MASTER/gates/runner.rb", __dir__)
  REGISTRY = YAML.safe_load_file(File.expand_path("../../../MASTER/gates/gates.yml", __dir__))

  def explain
    @explain ||= begin
      out, status = Open3.capture2e({ "GATE_LEDGER" => File::NULL }, RbConfig.ruby, RUNNER, "--explain")
      assert status.success?, out
      out
    end
  end

  def test_every_registered_gate_is_explained_with_its_pass_line
    REGISTRY.each do |name, row|
      assert_match(/^  #{Regexp.escape(name)}\s/, explain, "#{name} missing from --explain")
      assert_includes explain, "pass: #{row['pass']}", "#{name} pass line missing" if row["pass"]
    end
  end

  def test_it_documents_the_auditor_strict_switch_and_the_strict_family
    %w[GATE_AUDITOR_STRICT GATE_STRICT_INCONCLUSIVE GATE_STRICT_ERRORS GATE_STRICT_SOFT].each do |var|
      assert_match(/^  #{var}\s+\S/, explain, "#{var} undocumented in --explain")
    end
    assert_match(/GATE_AUDITOR_STRICT.*advisory/, explain)
  end

  def test_it_runs_no_gate
    refute_includes explain, "gates0 at"
  end

  # A switch named in --explain that no file reads is documentation of nothing.
  def test_every_documented_switch_has_a_reader
    sources = Dir.glob(File.expand_path("../../../MASTER/gates/**/*.{rb,yml}", __dir__)) +
              Dir.glob(File.expand_path("../../../OPENBSD/lib/**/*.rb", __dir__))
    body = sources.map { |path| File.read(path) }.join("\n")
    documented = explain.scan(/^  (GATES?_[A-Z_]+|VISUAL_CAPTURE)\s/).flatten
    assert_operator documented.size, :>=, 8, "the switch list was not parsed"
    unread = documented.reject do |var|
      body.match?(/(?:ENV|env)(?:\[|\.fetch\()"#{var}"|flag\?\("#{var}"|^\s+#{var}: \w/)
    end
    assert_empty unread, "documented in --explain but read by nothing"
  end
end
