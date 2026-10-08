# frozen_string_literal: true

require_relative "test_helper"

# SINGULARITY, applied to the scanner itself. On 2026-08-01 the same rule id
# (MAGIC_COLOR) was registered by two classes — js_rules.rb and universal_rules.rb —
# and every matching line was counted twice. Nothing caught it because the one place
# that enumerates the registry, LawRegistryAudit#build_registry_ids, folds ids into
# a Set (`.to_set`) before anyone looks — a duplicate collapses to one and vanishes.
#
# The built scanner does NOT dedup: `scanner.laws` holds one instance per registered
# class, so two classes claiming one id appear as two entries with the same #id. That
# is the honest place to assert uniqueness, because it is the exact list the scanner
# walks on every file.
class TestRuleIdsUnique < Minitest::Test
  def test_scanner_registry_uses_law_as_the_canonical_concept
    assert_same Master::Review::Scan::Law, Master::Review::Scan::Law
    assert_same Master::Review::Scan::LawDSL, Master::Review::Scan::LawDSL
    assert_same Master::Review::Scan::LawFactory, Master::Review::Scan::LawFactory
    assert_same Master::Review::Scan::LawRegistryAudit, Master::Review::Scan::LawRegistryAudit
  end

  def scanner
    @scanner ||= Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
  end

  def test_every_registered_rule_id_is_unique
    ids = scanner.laws.map { |rule| rule.id.to_s }
    dupes = ids.tally.select { |_id, count| count > 1 }

    assert_empty dupes,
                 "two rule classes share an id, so their matches double-count " \
                 "(SINGULARITY): #{dupes.map { |id, n| "#{id}×#{n}" }.join(", ")}. " \
                 "Give one a distinct id or delete the duplicate registration."
  end

  # The audit's Set-folding is where the last dup hid. Pin that the pre-fold count
  # equals the post-fold count, so the audit can never again mask a collision.
  def test_the_registry_audit_does_not_mask_a_collision
    Master::Review::Scan::LawDSL
    built = Master::Review::Scan::Law.registry
      .reject { |klass| Master::Review::Scan::LawFactory.bridge_class?(klass) }
      .map { |klass| Master::Review::Scan::LawFactory.build(klass, root: Master::ROOT).id.to_s.downcase }

    assert_equal built.size, built.uniq.size,
                 "the scanner registry has a duplicate id that LawRegistryAudit's " \
                 ".to_set would silently swallow: " \
                 "#{built.tally.select { |_, n| n > 1 }.keys.join(", ")}"
  end
end
