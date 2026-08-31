# frozen_string_literal: true

require_relative "test_helper"

# `rules.yml` declares the shape of the pitch; `MASTER/README.md` is the pitch.
# Nothing held the two together, so the declaration was one of the two keys
# data_reach counted as read by no code at all — and a structure nobody checks
# is a structure the next edit silently breaks.
#
# The README is the Innovasjon Norge case, so the movements and their order are
# load-bearing rather than cosmetic: idea, then business, then ask, then
# horizon. Four of the five name themselves in a heading. `proof` is the fifth
# and shows rather than names — it is the console transcript and the loop, under
# a heading that says "Under the hood" — so this asserts the section count
# carries it and leaves its wording alone.
class TestBusinessPlanStructure < Minitest::Test
  README = File.join(Master::ROOT, "README.md")

  def plan = Master.law("business_plan")

  def headings
    File.readlines(README).grep(/\A#{"#" * 3}#?\s/).map { |line| line.sub(/\A#+\s*/, "").strip }
  end

  def test_the_readme_carries_one_section_per_declared_movement
    assert_equal Array(plan["structure"]).size, headings.size,
                 "README sections: #{headings.join(' | ')}"
  end

  def test_the_named_movements_appear_in_the_declared_order
    named = Array(plan["structure"]).map(&:to_s) - ["proof"]
    positions = named.map do |movement|
      index = headings.index { |heading| heading.downcase.include?(movement) }
      refute_nil index, "README has no heading for the #{movement} movement — #{headings.join(' | ')}"
      index
    end

    assert_equal positions.sort, positions,
                 "README movements are out of the order rules.yml declares: #{named.join(' -> ')}"
  end

  def test_the_ask_names_innovasjon_norge
    assert_includes File.read(README), "innovasjonnorge.no",
                    "business_plan.sources names the grant criteria; the ask must reach them"
  end
end
