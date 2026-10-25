# frozen_string_literal: true

require_relative "test_helper"

# The business case is maintained in the README, not in laws.yml: a proposal
# is documentation, not another constitutional law registry. Keep the actual
# business-direction section structured so the funding route and decision
# horizon remain visible as the idea evolves.
class TestBusinessPlanStructure < Minitest::Test
  README = File.join(Master::ROOT, "README.md")
  EXPECTED = [
    "Competitive landscape",
    "Business hypothesis and strategy",
    "Pilot and funding route",
    "Ask and evidence",
    "Horizon",
  ].freeze

  def readme = File.read(README)

  def business_section
    match = readme.match(/^## External assessment and business direction\s*\n(.*?)(?=^## |\z)/m)
    refute_nil match, "README must retain the business-direction section"
    match[1]
  end

  def test_business_direction_has_the_five_current_sections_in_order
    actual = business_section.lines.grep(/^###\s/).map { |line| line.sub(/^###\s*/, "").strip }
    assert_equal EXPECTED, actual
  end

  def test_funding_route_is_named_without_claiming_eligibility
    section = business_section
    assert_includes section, "innovasjonnorge.no"
    assert_includes section, "does not claim eligibility or approval"
  end
end
