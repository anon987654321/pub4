# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "gate_fixture"
require_relative "../../gates/lib/source/scale_ratchet"

# A corner nothing else in the family has, against a recorded ceiling.
#
# The gate compares Operator::ScaleLint's per-surface counts to the baselines in
# design_tokens.yml: over fails, under warns and asks for the new low to be
# recorded, equal passes. The lint memoises the stylesheet lists it reads, so a
# fixture is installed by setting those and the baselines, and cleared
# afterwards so the next test measures the real tree again.
class ScaleRatchetGateTest < Minitest::Test
  GATE = Deploy::ScaleRatchetGate
  LINT = Operator::ScaleLint
  MEMOS = %i[@app_stylesheets @face_stylesheets @baselines].freeze

  # radius_px declares 8 and not 7, so one of these is on the scale and the
  # other is the defect.
  ON_SCALE = ".card { border-radius: 8px; }\n"
  OFF_SCALE = ".card { border-radius: 7px; }\n"

  def teardown
    MEMOS.each { |name| LINT.instance_variable_set(name, nil) }
  end

  def gate_over(scss, baselines)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cards.scss")
      File.write(path, scss)
      LINT.instance_variable_set(:@app_stylesheets, [path])
      LINT.instance_variable_set(:@face_stylesheets, [])
      LINT.instance_variable_set(:@baselines, baselines)
      GATE.run
    end
  end

  def baselines(apps_radius)
    { "apps" => { "off_scale_radius" => apps_radius }, "face" => { "off_scale_radius" => 0 } }
  end

  def test_a_radius_off_the_scale_fails_against_a_zero_baseline
    result = gate_over(OFF_SCALE, baselines(0))

    refute result.ok?, "an off-scale radius passed a baseline of zero"
    assert_match(/apps\.off_scale_radius: 1 \(baseline 0, \+1\)/, result.failures.first)
  end

  def test_the_nearest_declared_step_is_named_in_the_report
    result = gate_over(OFF_SCALE, baselines(0))

    assert(result.warnings.any? { |line| line.match?(/off_scale_radius 7px — nearest step 8px/) },
           result.warnings.join(", "))
  end

  def test_the_same_rule_on_a_declared_step_passes
    result = gate_over(ON_SCALE, baselines(0))

    assert result.ok?, result.failures.join(", ")
    assert_equal 2, result.checks_ran, "one baseline per surface was compared"
  end

  # A count under its ceiling is a win, and recording it is a deliberate edit to
  # design_tokens.yml. Reporting it as a failure would train people to raise the
  # number instead of lowering it.
  def test_a_count_under_its_baseline_warns_rather_than_fails
    result = gate_over(ON_SCALE, baselines(3))

    assert result.ok?, result.failures.join(", ")
    assert(result.warnings.any? { |line| line.match?(/new low apps\.off_scale_radius: 0 \(baseline 3, -3\)/) },
           result.warnings.join(", "))
  end

  # A surface with no baselines compares nothing, and a lint that read no files
  # reports zero for every kind — which is indistinguishable from clean.
  def test_no_baselines_at_all_is_inconclusive
    result = gate_over(OFF_SCALE, { "apps" => {}, "face" => {} })

    assert_equal :inconclusive, result.outcome
    assert_match(/scale\.baselines is unread/, result.unchecked.first)
  end

  # The ratchet the gate reads is the one the tree ships, so an empty or
  # mistyped baselines block would make every comparison vacuous.
  def test_the_shipped_baselines_cover_every_surface
    LINT.instance_variable_set(:@baselines, nil)

    LINT::SURFACES.each do |surface|
      refute_empty LINT.baselines_for(surface), "#{surface} has no baselines to compare against"
    end
  end
end
