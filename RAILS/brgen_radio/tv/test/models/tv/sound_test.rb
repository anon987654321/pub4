# frozen_string_literal: true

require "test_helper"

class Tv::SoundTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_sound_owner@brgen.no", password: "password123", city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a sound needs a title of at most 120 characters" do
    blank = Tv::Sound.new(user: @owner, title: "")
    long = Tv::Sound.new(user: @owner, title: "x" * 121)

    assert_not blank.valid?
    assert blank.errors.added?(:title, :blank)
    assert_not long.valid?
    assert long.errors.added?(:title, :too_long, count: 120)
  end

  test "a clip's original sound is made once, named after the person who posted it" do
    ActsAsTenant.with_tenant(@city) do
      clip = video("Første klipp")

      sound = Tv::Sound.original_for(clip)

      assert_equal I18n.t("tv.original_sound", name: @owner.display_name), sound.title
      assert_equal @owner.id, sound.user_id
      assert_equal sound.id, Tv::Sound.original_for(clip).id
    end
  end

  test "videos by watch time lists only published clips using the sound" do
    ActsAsTenant.with_tenant(@city) do
      sound = Tv::Sound.create!(user: @owner, title: "Refreng")
      shown = video("Ute", sound: sound)
      hidden = video("Klargjøres", sound: sound, status: "processing")
      video("Annen lyd")

      assert_equal [ shown.id ], sound.videos_by_watch_time.ids
      assert_not_includes sound.videos_by_watch_time, hidden
    end
  end

  test "popular lists the sound used by the most clips first" do
    ActsAsTenant.with_tenant(@city) do
      rare = Tv::Sound.create!(user: @owner, title: "Sjelden")
      common = Tv::Sound.create!(user: @owner, title: "Vanlig")
      2.times { |index| video("Vanlig #{index}", sound: common) }
      video("Sjelden", sound: rare)

      assert_equal [ common.id, rare.id ], Tv::Sound.where(id: [ rare.id, common.id ]).popular.ids
    end
  end

  private

  def channel
    @channel ||= Tv::Channel.create!(user: @owner, name: "Lyder #{SecureRandom.hex(2)}")
  end

  def video(title, sound: nil, status: "published")
    Tv::Video.create!(channel: channel, user: @owner, title: title, status: status,
                      published_at: Time.current, duration_seconds: 30, sound: sound)
  end
end
