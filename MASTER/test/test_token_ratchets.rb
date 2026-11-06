# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../checks/lib/source/scale_ratchet"

# The two token-value ratchets: distinct values per property in compiled CSS (Wallace's census)
# and literal colours in colour properties that tokens.yml does not declare
# (stylelint-declaration-strict-value's rule).
class TestTokenRatchets < Minitest::Test
  LINT = Operator::ScaleLint
  CENSUS = Operator::ScaleLint::Census

  def test_the_census_counts_distinct_values_per_property
    css = ".a{font-size:16px;color:#111}.b{font-size: 16px !important;color:#222}/* font-size:99px */" \
          ".c{font-size:18px;background-color:#fff}"

    counts = CENSUS.counts(css)

    assert_equal 2, counts["font-size"]
    assert_equal 2, counts["color"]
    assert_equal 1, counts["background-color"]
  end

  def test_a_compiled_count_over_its_baseline_is_a_soft_ratchet_failure
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "brgen", "app/assets/builds"))
      File.write(File.join(root, "brgen", CENSUS::BUILD), ".a{font-size:13px}.b{font-size:15px}")
      result = Deploy::CheckResult.new

      LINT.stub(:baselines, { "compiled.brgen.font-size" => 1, "compiled.amber.font-size" => 9 }) do
        Deploy::ScaleRatchetCheck.compiled(result, rails_root: root)
      end

      assert_equal ["scale_ratchet: compiled.brgen.font-size: 2 (baseline 1, +1)"], result.soft_failures
      assert_match(/compiled\.amber not measured/, result.warnings.join)
    end
  end

  def test_a_literal_colour_tokens_yml_does_not_declare_is_off_token
    found = LINT.check("x.scss", 3, "border", "1px solid #c0ffee")

    assert_equal [%w[off_token_color #c0ffee]], found.map { |row| [row.kind, row.value] }
  end

  def test_a_declared_colour_a_token_and_a_keyword_are_on_token
    declared = LINT.palette.find { |hex| hex != "#000000" }

    assert_empty LINT.check("x.scss", 3, "color", declared)
    assert_empty LINT.check("x.scss", 3, "color", "var(--ink)")
    assert_empty LINT.check("x.scss", 3, "background", "transparent")
    assert_empty LINT.check("x.scss", 3, "color", "#FFF")
  end

  def test_the_shared_stylesheets_hold_their_colour_baseline
    LINT::SURFACES.each do |surface|
      assert_operator LINT.counts_for(surface)["off_token_color"].to_i, :<=,
                      LINT.baselines_for(surface).fetch("off_token_color"), surface
    end
  end
end
