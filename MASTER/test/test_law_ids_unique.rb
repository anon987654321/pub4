# frozen_string_literal: true

require_relative "test_helper"
# Loads the detector tree so Law.registry holds every class the scanner builds.
require_relative "../lib/review/scan/law_dsl"

# SINGULARITY, applied to the scanner itself. One id registered by two classes
# counts every matching line twice, and LawRegistryAudit#build_registry_ids folds
# ids into a Set (`.to_set`) before anyone looks, so a duplicate vanishes there.
#
# The built scanner does NOT dedup: `scanner.laws` holds one instance per registered
# class, so two classes claiming one id appear as two entries with the same #id. That
# is the honest place to assert uniqueness, because it is the exact list the scanner
# walks on every file.
class TestLawIdsUnique < Minitest::Test
  def test_scanner_registry_uses_law_as_the_canonical_concept
    %i[Law LawDSL LawFactory LawRegistryAudit].each do |name|
      assert Master::Review::Scan.const_get(name, false), "Master::Review::Scan::#{name} is the scanner's Law vocabulary"
    end
  end

  def scanner
    @scanner ||= Master::Builder.build_scanner(root: Master::ROOT)
  end

  def test_every_registered_law_id_is_unique
    ids = scanner.laws.map { |rule| rule.id.to_s }
    dupes = ids.tally.select { |_id, count| count > 1 }

    assert_empty dupes,
                 "two law classes share an id, so their matches double-count " \
                 "(SINGULARITY): #{dupes.map { |id, n| "#{id}×#{n}" }.join(", ")}. " \
                 "Give one a distinct id or delete the duplicate registration."
  end

  # The audit folds ids into a Set. Pin that the pre-fold count equals the
  # post-fold count, so the audit cannot mask a collision.
  def test_the_registry_audit_does_not_mask_a_collision
    audit = Master::Review::Scan::LawRegistryAudit.new(root: Master::ROOT)
    built = Master::Review::Scan::Law.registry
      .select { |klass| audit.shipped?(klass) }
      .map { |klass| Master::Review::Scan::LawFactory.build(klass, root: Master::ROOT).id.to_s.downcase }

    assert_equal built.size, built.uniq.size,
                 "the scanner registry has a duplicate id that LawRegistryAudit's " \
                 ".to_set would silently swallow: " \
                 "#{built.tally.select { |_, n| n > 1 }.keys.join(", ")}"
  end
end
