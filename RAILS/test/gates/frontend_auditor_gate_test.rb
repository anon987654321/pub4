# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/frontend_auditor"
# The gate `load`s this at run time, so a test that calls the auditor directly
# has to name it or depend on which test minitest shuffles first.
require_relative "../../shared/app/services/shared/frontend_auditor"

# The one finding that blocks, and the rule that decides what else does.
#
# Shared::FrontendAuditor files three severities and only :error stops the
# layout suite. Exactly one rule raises one: a shell script that writes a
# tracked app file, which is how generated views and stylesheets get into this
# tree without ever appearing in a diff. Everything else is a warning, and
# whether warnings block is GATE_AUDITOR_STRICT's decision.
#
# The auditor takes a root, so the defect is planted in a temporary app. The
# gate itself resolves its app list from constants fixed at load time, so those
# are rewritten to point the fleet walk at the fixture — the shared engine stays
# real, because the gate loads the auditor out of it.
class FrontendAuditorGateTest < Minitest::Test
  include GateFixture

  GATE = Deploy::FrontendAuditorGate
  EMBEDDING_SCRIPT = "#!/usr/bin/env zsh\ncat <<EOF > app/views/posts/index.html.erb\n<h1>hi</h1>\nEOF\n"
  HONEST_SCRIPT = "#!/usr/bin/env zsh\nbin/rails db:migrate\n"

  def audit(script_body)
    Dir.mktmpdir do |dir|
      plant(dir, "bin/generate.sh", script_body)
      Shared::FrontendAuditor.call(root: Pathname.new(dir))
    end
  end

  def gate_over(script_body)
    Dir.mktmpdir do |dir|
      plant(dir, "RAILS/demo/bin/generate.sh", script_body)
      with_constants(GATE, ROOT: dir, APPS: %w[demo]) { GATE.run }
    end
  end

  def test_a_script_writing_a_tracked_view_is_an_error
    findings = audit(EMBEDDING_SCRIPT)
    errors = findings.select { |finding| finding.severity == :error }

    assert_equal [:embedded_app_file], errors.map(&:rule)
    assert_match(/extract embedded content/, errors.first.message)
  end

  def test_a_script_that_writes_nothing_tracked_is_not_an_error
    assert_empty audit(HONEST_SCRIPT).select { |finding| finding.severity == :error }
  end

  def test_the_gate_fails_on_the_planted_script
    result = gate_over(EMBEDDING_SCRIPT)

    refute result.ok?, "a shell script writing app/views passed the gate"
    assert(result.failures.any? { |line| line.match?(/embedded_app_file/) }, result.failures.join(", "))
    assert(result.failures.any? { |line| line.match?(/1 error\(s\) across apps/) }, result.failures.join(", "))
  end

  def test_the_gate_passes_once_the_script_stops_writing_app_files
    result = gate_over(HONEST_SCRIPT)

    assert result.ok?, result.failures.join(", ")
    assert_equal 2, result.checks_ran, "the fixture app and the shared engine are both roots"
  end

  # Warnings are the auditor's bulk output and they are advisory by default. The
  # flag is the only thing between "reported" and "blocking", so it is worth an
  # assertion of its own: read from the environment it is handed, not from the
  # process, so a test cannot be changed by whoever ran it.
  def test_warnings_block_only_under_the_strict_flag
    assert GATE.strict_warnings?({ "GATE_AUDITOR_STRICT" => "1" })
    assert GATE.strict_warnings?({ "GATE_AUDITOR_STRICT" => "true" })
    refute GATE.strict_warnings?({})
    refute GATE.strict_warnings?({ "GATE_AUDITOR_STRICT" => "0" })
  end

  def test_an_inline_style_block_is_a_warning_not_an_error
    findings = Dir.mktmpdir do |dir|
      plant(dir, "app/views/posts/show.html.erb", "<style>h1 { color: red; }</style>\n")
      Shared::FrontendAuditor.call(root: Pathname.new(dir))
    end

    assert_equal [:warning], findings.select { |f| f.rule == :inline_css }.map(&:severity)
    assert_empty findings.select { |finding| finding.severity == :error }
  end
end
