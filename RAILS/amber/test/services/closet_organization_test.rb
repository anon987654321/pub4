# frozen_string_literal: true

require "test_helper"

class ClosetOrganizationTest < ActiveSupport::TestCase
  def user(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    user.items.destroy_all
    user
  end

  test "every register is represented when the wardrobe triggers it" do
    owner = user("closet-registers@example.com")
    owner.items.create!(title: "Shirt", category: "Tops", lifecycle_state: "clean_needed", material: "cotton")
    owner.items.create!(title: "Jumper", category: "Tops", material: "merino wool", times_worn: 9)
    owner.items.create!(title: "Trousers", category: "Bottoms", material: "linen", color: "navy")
    owner.items.create!(title: "Loafers", category: "Shoes", material: "leather", color: "tan")
    owner.items.create!(title: "Scarf", category: "Accessories", color: "cream")
    owner.items.create!(title: "Coat", category: "Outerwear", color: "black", season: "Winter")

    organization = ClosetOrganization.new(owner)
    registers = organization.tips.map(&:register).uniq

    assert_includes registers, :care
    assert_includes registers, :storage
    assert_includes registers, :zoning
    assert_equal "rules", organization.summary[:source]
  end

  test "a tip with no evidence behind it is not emitted" do
    owner = user("closet-quiet@example.com")
    owner.items.create!(title: "Tee", category: "Tops")

    ids = ClosetOrganization.new(owner).tips.map(&:id)

    assert_not_includes ids, :clean_needed
    assert_not_includes ids, :repair
    assert_not_includes ids, :breathe
  end

  test "care tips count lifecycle states" do
    owner = user("closet-care@example.com")
    2.times { |i| owner.items.create!(title: "Dirty #{i}", category: "Tops", lifecycle_state: "clean_needed") }
    owner.items.create!(title: "Torn", category: "Tops", lifecycle_state: "repair")

    tips = ClosetOrganization.new(owner).care_tips.to_h { |tip| [ tip.id, tip.count ] }

    assert_equal 2, tips[:clean_needed]
    assert_equal 1, tips[:repair]
  end

  test "knits are folded and tailoring is hung" do
    owner = user("closet-storage@example.com")
    owner.items.create!(title: "Cashmere jumper", category: "Tops", material: "cashmere")
    owner.items.create!(title: "Silk blouse", category: "Tops", material: "silk")

    tips = ClosetOrganization.new(owner).storage_tips.to_h { |tip| [ tip.id, tip.count ] }

    assert_equal 1, tips[:fold]
    assert_equal 1, tips[:hang]
  end

  test "crowded categories trigger the density tip and airy ones do not" do
    crowded = user("closet-crowded@example.com")
    25.times { |i| crowded.items.create!(title: "Tee #{i}", category: "Tops") }
    airy = user("closet-airy@example.com")
    4.times { |i| airy.items.create!(title: "Tee #{i}", category: "Tops") }

    assert_includes ClosetOrganization.new(crowded).restraint_tips.map(&:id), :density
    assert_not_includes ClosetOrganization.new(airy).restraint_tips.map(&:id), :density
  end

  test "every tip names the principle it came from" do
    owner = user("closet-principles@example.com")
    owner.items.create!(title: "Wool coat", category: "Outerwear", material: "wool", lifecycle_state: "repair", times_worn: 8)
    owner.items.create!(title: "Silk scarf", category: "Accessories", material: "silk", color: "ivory")
    owner.items.create!(title: "Jeans", category: "Bottoms", material: "denim", color: "indigo")
    owner.items.create!(title: "Boots", category: "Shoes", material: "leather", color: "brown")

    ClosetOrganization.new(owner).tips.each do |tip|
      assert tip.principle.present?, "#{tip.id} has no principle"
      assert tip.body.present?, "#{tip.id} has no body"
      assert_includes ClosetOrganization::REGISTERS, tip.register
    end
  end
end
