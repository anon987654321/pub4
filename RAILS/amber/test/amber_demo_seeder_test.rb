# frozen_string_literal: true

require "test_helper"

class AmberDemoSeederTest < ActiveSupport::TestCase
  test "seeds demo capsule without remote media in test env" do
    Amber::AmberDemoSeeder.new(attach_media: false).seed!

    item = Amber::DemoWardrobe.items.find_by!(title: "Ivory silk slip dress")
    refute item.photos.attached?
    assert_equal "Dresses", item.category
    assert Amber::DemoWardrobe.outfits.exists?(name: "Gallery opening")
  end

  test "demo items declare image seeds for postpro pipeline" do
    slugs = Amber::AmberDemoSeeder::ITEMS.map { |row| row[:image] }
    assert_equal Amber::AmberDemoSeeder::ITEMS.size, slugs.compact.size
    assert_includes slugs, "amber-ivory-silk-dress"
  end
end
