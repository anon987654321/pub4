# frozen_string_literal: true

require "minitest/autorun"
require_relative "../shared/lib/pub4/css_coverage_lint"

# The register has tracked unused CSS selectors since 2026-08-10 and said in its own
# entry that no committed tool reproduces the number. This is that tool, and it
# measures the direction nobody had: a class the markup asks for that no stylesheet
# defines — a hook the author expected to do something.
class CssCoverageLintTest < Minitest::Test
  L = Pub4::CssCoverageLint

  def test_no_kind_exceeds_its_baseline
    exceeded = L.over_baseline

    assert_empty exceeded, exceeded.join("; ")
  end

  # A baseline beaten and never lowered is a baseline nobody trusts. Both directions,
  # which is the contract MASTER/test/test_ratchets.rb now holds for every ratchet.
  def test_baselines_are_not_stale
    counts = L.counts

    L::BASELINES.each do |kind, baseline|
      assert_equal baseline, counts.fetch(kind),
                   "#{kind} is at #{counts.fetch(kind)} against #{baseline} — lower it in css_coverage_lint.rb"
    end
  end

  # The correction that made this trustworthy. A first pass read only .scss/.css and
  # reported every mail-* class as undefined; email defines its classes in the mailer
  # layout's inline <style>, because email cannot load an asset bundle.
  def test_inline_style_blocks_count_as_definitions
    assert_includes L.defined_names, "mail-shell",
                    "the mailer layout's inline <style> must count, or every email class reads as missing"
    refute_includes L.undefined_classes, "mail-shell"
  end

  # Same correction, second instance: brgen's _site_legal_footer carries a <style>
  # block that styles the three legal pages, which are linked from every page.
  #
  # legal-nav is not in the list. 240a4e746 dropped the class from all three
  # navs because the rule that styles them is `.legal-prose nav` — a class named
  # by a test and by nothing else is the thing this file exists to catch, not a
  # thing for it to require.
  def test_the_legal_pages_are_styled
    %w[legal-eyebrow legal-prose legal-updated].each do |name|
      assert_includes L.defined_names, name, "#{name} is styled by _site_legal_footer's inline block"
      refute_includes L.undefined_classes, name
    end
  end

  # A BEM child whose base is defined is not a missing style — SCSS builds those names
  # with &__child, which no literal scan of the file can see.
  def test_a_bem_child_of_a_defined_base_is_not_missing
    assert L.base_defined?("#{L.defined_names.first}__anything")
  end

  # An interpolated class cannot be resolved statically and must never be reported.
  def test_interpolated_classes_are_ignored
    assert L.interpolated?('card card--#{kind}')
    assert L.interpolated?("")
  end

  # Both lists must be non-empty for the counts to mean anything: an empty scan reads
  # as a clean tree, which is the failure mode every gate here exists to catch.
  def test_it_reads_something
    refute_empty L.defined_names
    refute_empty L.used_names
    assert_operator L.defined_names.size, :>, 500, "the stylesheet glob stopped matching"
  end
end
