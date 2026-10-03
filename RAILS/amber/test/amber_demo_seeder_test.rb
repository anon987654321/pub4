# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AmberDemoSeederTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "seeds demo capsule without remote media in test env" do
    Amber::AmberDemoSeeder.new(attach_media: false).seed!

    item = Amber::DemoWardrobe.items.find_by!(title: "Ivory silk slip dress")
    refute item.photos.attached?
    assert_equal "Dresses", item.category
    assert Amber::DemoWardrobe.outfits.exists?(name: "Gallery opening")
  end

  test "seeds feed posts with resolved embeds, asking no provider and queueing nothing" do
    Shared::LinkEmbed.stub(:fetch_oembed, ->(_uri) { flunk "the seeder asked a provider" }) do
      assert_no_enqueued_jobs(only: Shared::LinkEmbedJob) do
        Amber::AmberDemoSeeder.new(attach_media: false).seed!
        Amber::AmberDemoSeeder.new(attach_media: false).seed!
      end
    end

    posts = Amber::DemoWardrobe.user.posts.where.not(link_embed: nil).to_a
    assert_equal Shared::LinkEmbed.demo_posts(:amber).size, posts.size
    assert posts.all? { |post| post.link_embed_record&.ok? }
  end

  test "demo items declare image seeds for postpro pipeline" do
    slugs = Amber::AmberDemoSeeder::ITEMS.map { |row| row[:image] }
    assert_equal Amber::AmberDemoSeeder::ITEMS.size, slugs.compact.size
    assert_includes slugs, "amber-ivory-silk-dress"
  end
end
