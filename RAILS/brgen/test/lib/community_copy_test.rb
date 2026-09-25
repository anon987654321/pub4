# frozen_string_literal: true

require "test_helper"
require "rake"

# The seeders wrote "Kultur community for Hoppeton" on brgen.no/communities.
# The copy is Norwegian and names the seeded city now, and the rake task
# rewrites the rows already written, once.
class CommunityCopyTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("lib/tasks/community_copy.rake").to_s unless defined?(BrgenCommunityCopy)
    @city = City.find_by(domain: "brgen.no") || City.create!(name: "Bergen", domain: "brgen.no", slug: "bergen-copy", country_code: "NO", locale: "nb", currency: "NOK")
  end

  def test_every_seeded_slug_has_norwegian_copy_naming_the_city
    Brgen::PlausibleContent::COMMUNITIES.each_key do |slug|
      name, description = Brgen::PlausibleContent.community(slug, "Bergen")
      assert name.present?, slug
      assert_includes description, "Bergen", slug
      refute_match(/community for/i, description, slug)
    end
  end

  def test_the_task_rewrites_seeder_copy_once_and_leaves_hand_copy_alone
    seeded = create_community("kultur", "Kultur", "Kultur community for Hoppeton")
    english = create_community("food", "Food", "Food community for Pfefferton")
    demo = create_community("mat", "Mat", "Bergen — mat")
    hand = create_community("film", "Filmklubben", "Vi ser film på Bergen Kino hver fredag.")

    name, description = BrgenCommunityCopy.rewrite_for(seeded)
    assert_equal "Kultur", name
    assert_includes description, "Kulturfellesskap for Bergen sentrum"

    assert_equal "Mat", BrgenCommunityCopy.rewrite_for(english).first
    assert BrgenCommunityCopy.rewrite_for(demo)
    assert_nil BrgenCommunityCopy.rewrite_for(hand)

    seeded.update!(name: name, description: description)
    assert_nil BrgenCommunityCopy.rewrite_for(seeded.reload), "a second run has nothing to do"
  end

  private

  def create_community(slug, name, description)
    ActsAsTenant.with_tenant(@city) do
      Community.create!(slug: slug, name: name, description: description, city: @city)
    end.then { |c| Community.includes(:city).find(c.id) }
  end
end
