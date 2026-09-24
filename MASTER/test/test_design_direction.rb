<sub><sub><sub># frozen_string_literal: true

require_relative "test_helper"

class DesignDirectionTest < Minitest::Test
  def test_authority_is_first
    contract = Master::Design::Authority.contract
    assert_equal 1, contract.fetch("priority")
    assert_equal %w[purpose agency clarity hierarchy trust consistency craft delight],
                 Master::Design::Authority::ORDER
  end

  def test_all_schools_inherit_authority
    Master::Design::Authority.schools.each do |name, spec|
      assert_equal true, spec.fetch("inherits_authoritative_design"), "#{name} bypasses authority"
    end
  end

  def test_marketplace_pairing_is_shipped_and_single_family
    key, spec = Master::Design::Pairing.for(school: :commerce_editorial, purpose: "marketplace sale")
    assert_equal "marketplace_sale", key
    assert_equal "house_sans", spec.fetch("display")
    assert Master::Design::Pairing.deployable?(spec)
  end

  def test_marketplace_composition_preserves_transaction_priority
    _, spec = Master::Design::Composition.for(school: :commerce_editorial, purpose: "marketplace sale")
    assert_equal %w[product price headline proof action], spec.fetch("focal_order")
  end
end
</sub></sub></sub>