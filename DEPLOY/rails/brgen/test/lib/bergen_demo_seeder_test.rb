# frozen_string_literal: true

require "test_helper"

class BergenDemoSeederTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "seeds norwegian bergen posts and users without remote media" do
    ActsAsTenant.with_tenant(@city) do
      Brgen::BergenDemoSeeder.new(@city, attach_media: false).seed!
    end

    post = Post.strict_loading(false).includes(:community).where(city: @city).find_by!(title: "Regnværsdag på Bryggen")
    assert_equal "bergen", post.community.slug
    assert_match(/Kaffebrenneriet/, post.content)
    refute post.image.attached?

    user = User.find_by!(username: "henrik_vestland")
    assert_equal "henrik_vestland@brgen.no", user.email_address

    assert Comment.where(commentable: post).count >= 2
    assert Marketplace::Listing.exists?(title: "Brukt sykkel — Bergen sentrum")
    assert Dating::Profile.joins(:user).exists?(users: { username: "emilie_floyen" })
  end

  test "seeds radio bergen playlist from manifest" do
    ActsAsTenant.with_tenant(@city) do
      Brgen::BergenDemoSeeder.new(@city, attach_media: false).seed!
    end

    playlist = Playlist::Playlist.find_by!(city: @city, name: Brgen::BergenDemoSeeder::RADIO_BERGEN_PLAYLIST)
    assert playlist.public_access
    assert_operator playlist.tracks.count, :>=, 20

    akmd = playlist.tracks.find_by(title: "Stailings", artist: "AKMD")
    assert_equal "direct", akmd.source_type
    assert_match(%r{/audio/akmd/akmd-stailings\.mp3}, akmd.source_url)

    dilla = playlist.tracks.find_by(title: "Microphone Master", artist: "J Dilla")
    assert_equal "youtube", dilla.source_type
    assert_match(/9EGHwkDix78/, dilla.source_url)
  end

  test "seeds credible dating profiles and mutual matches" do
    ActsAsTenant.with_tenant(@city) do
      Brgen::BergenDemoSeeder.new(@city, attach_media: false).seed!
    end

    assert_operator Dating::Profile.joins(:user).where(users: { city_id: @city.id }).count, :>=, 12

    emilie = Dating::Profile.strict_loading(false).joins(:user).find_by!(users: { username: "emilie_floyen" })
    assert_equal "woman", emilie.gender
    assert_equal "man", emilie.looking_for
    assert_match(/Fløyen/, emilie.bio)

    magnus = User.find_by!(username: "magnus_student")
    assert Dating::Like.exists?(liker: emilie.user, likee: magnus)
    assert Dating::Like.exists?(liker: magnus, likee: emilie.user)
    assert Dating::Match.where(status: "matched").exists?(
      ["(initiator_id = ? AND receiver_id = ?) OR (initiator_id = ? AND receiver_id = ?)",
       emilie.user_id, magnus.id, magnus.id, emilie.user_id]
    )
  end

  test "surfaces bergen frontpage threads with vote weight" do
    ActsAsTenant.with_tenant(@city) do
      Brgen::BergenDemoSeeder.new(@city, attach_media: false).seed!
    end

    hot_titles = Post.hot.where(city: @city).limit(5).pluck(:title)
    assert_includes hot_titles, "Hva skjer i Bergen i helgen?"
    assert_includes hot_titles, "Radio Bergen-playlisten er oppe — hvem lager neste?"
  end

  test "is idempotent on re-run" do
    seeder = Brgen::BergenDemoSeeder.new(@city, attach_media: false)

    ActsAsTenant.with_tenant(@city) { seeder.seed! }
    post_count = Post.where(city: @city).count
    playlist_track_count = Playlist::Playlist.find_by!(city: @city, name: Brgen::BergenDemoSeeder::RADIO_BERGEN_PLAYLIST).tracks.count

    ActsAsTenant.with_tenant(@city) { seeder.seed! }
    assert_equal post_count, Post.where(city: @city).count
    assert_equal playlist_track_count,
                 Playlist::Playlist.find_by!(city: @city, name: Brgen::BergenDemoSeeder::RADIO_BERGEN_PLAYLIST).tracks.count
  end
end