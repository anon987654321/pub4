# frozen_string_literal: true

require "test_helper"
require_relative "../source_reader"

# The player posts a timestamped comment through this reflex with the comment
# as the reflex argument; the element is the player, whose dataset has no
# track id. Reading the dataset meant no comment was ever saved.
class PlaylistTimestampedCommentsReflexTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(
      email_address: "tsc_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "tsc_#{SecureRandom.hex(3)}", guest: false, city: @city
    )
    @track = Playlist::Track.create!(title: "Regnvær", artist: "", user: @user, source_type: "direct",
                                     source_url: "https://example.com/regn.mp3", privacy: "public")
    Current.user = @user
  end

  teardown do
    Current.reset
    ActsAsTenant.current_tenant = nil
  end

  def reflex_on_player_element
    reflex = PlaylistTimestampedCommentsReflex.allocate
    player = StimulusReflex::Element.new("dataset" => { "dataset" => { "data-controller" => "playlist-player" } })
    reflex.define_singleton_method(:element) { player }
    reflex.define_singleton_method(:morph) { |*| nil }
    reflex
  end

  test "the comment the player sends as the reflex argument is saved at its time" do
    assert_difference -> { @track.timestamped_comments.count }, 1 do
      reflex_on_player_element.create("track_id" => @track.id.to_s, "body" => " Fin bro ", "timestamp" => 42.5)
    end
    comment = @track.timestamped_comments.last
    assert_equal "Fin bro", comment.body
    assert_in_delta 42.5, comment.timestamp_seconds
  end

  test "a private track of someone else takes no comment" do
    other = Playlist::Track.create!(title: "Skjult", artist: "", user: nil, source_type: "direct",
                                    source_url: "https://example.com/skjult.mp3", privacy: "private")
    assert_no_difference -> { Playlist::TimestampedComment.count } do
      reflex_on_player_element.create("track_id" => other.id.to_s, "body" => "Hei", "timestamp" => 1)
    end
  end

  test "the player registers with StimulusReflex before it can stimulate" do
    path = "brgen_radio/playlist/app/javascript/controllers/playlist_player_controller.js"
    source = File.read(File.join(SourceReader::ROOT, path))
    assert_match(/StimulusReflex\.register\(this\)/, source)
  end
end
