# frozen_string_literal: true

require "test_helper"

# A video had no audio identity, so there was nothing to browse more of, and no
# way to make a clip that answers another one.
class TvSoundsAndDuetsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @creator = create_user("tv_creator")
    @answerer = create_user("tv_answerer")
    ActsAsTenant.current_tenant = @city
    @channel = Tv::Channel.create!(user: @creator, name: "Kanalen #{SecureRandom.hex(2)}", slug: "kanal-#{SecureRandom.hex(3)}")
    @their_channel = Tv::Channel.create!(user: @answerer, name: "Svar #{SecureRandom.hex(2)}", slug: "svar-#{SecureRandom.hex(3)}")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "tv.brgen.no"
  end

  def upload(channel, title, **video_params)
    post tv.channel_videos_path(channel), params: {
      video: { title: title, video_file: video_upload }.merge(video_params)
    }
    Tv::Video.order(:created_at).last
  end

  def video_upload
    Rack::Test::UploadedFile.new(StringIO.new("fake mp4"), "video/mp4", true, original_filename: "clip.mp4")
  end

  # Every clip introduces a sound, named after whoever posted it, so there is
  # always something to browse more of.
  test "a clip with no sound named becomes the origin of its own" do
    sign_in_as(@creator)
    video = upload(@channel, "Første klipp")

    assert_not_nil video.reload.sound_id
    sound = Tv::Sound.find(video.sound_id)
    assert_equal video.id, sound.source_video_id
    assert_equal 1, sound.videos_count
  end

  test "a second clip can reuse a sound, and the count follows" do
    sign_in_as(@creator)
    first = upload(@channel, "Første")
    sound = Tv::Sound.find(first.reload.sound_id)

    second = upload(@channel, "Andre", sound_id: sound.id)
    assert_equal sound.id, second.reload.sound_id
    assert_equal 2, sound.reload.videos_count
  end

  # A duet inherits the sound, which is what makes it a duet rather than a
  # second clip that happens to mention the first.
  test "a duet names its original and carries its sound" do
    sign_in_as(@creator)
    original = upload(@channel, "Originalen")

    sign_in_as(@answerer)
    answer = upload(@their_channel, "Svaret", duet_of_id: original.id)

    assert_equal original.id, answer.reload.duet_of_id
    assert_equal original.reload.sound_id, answer.sound_id
    assert_includes Tv::Video.find(original.id).duets, answer
  end

  # A creator who does not want their face beside a stranger's has to be able to
  # say so.
  test "a video that refuses answers is not answered" do
    sign_in_as(@creator)
    original = upload(@channel, "Lukket", allow_duets: "0")
    assert_not original.reload.allow_duets?

    sign_in_as(@answerer)
    answer = upload(@their_channel, "Uvedkommende", duet_of_id: original.id)
    assert_nil answer.reload.duet_of_id
  end

  test "the sound page lists its clips and the video page links to it" do
    sign_in_as(@creator)
    video = upload(@channel, "Klippet")
    sound = Tv::Sound.find(video.reload.sound_id)

    get tv.sound_path(sound)
    assert_response :success
    assert_includes response.body, "Klippet"

    get tv.video_path(video)
    assert_includes response.body, tv.sound_path(sound)
  end

  # The sound outlives the clip it came from — the clips that use it are the
  # reason it is still a thing.
  test "deleting the source clip leaves the sound" do
    sign_in_as(@creator)
    video = upload(@channel, "Kilden")
    sound = Tv::Sound.find(video.reload.sound_id)

    Tv::Video.find(video.id).destroy
    assert Tv::Sound.exists?(sound.id)
    assert_nil sound.reload.source_video_id
  end
end
