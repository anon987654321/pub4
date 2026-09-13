# frozen_string_literal: true

require "test_helper"

class Playlist::DillaSketchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(email_address: "sketch@brgen.no", password: "password123", city: @city)
  end

  test "a sketch needs a bounded name, a state and a known render status" do
    sketch = Playlist::DillaSketch.new(user: @user, name: "x" * 101, state: nil, render_status: "exploded")

    assert_not sketch.valid?
    assert sketch.errors.added?(:name, :too_long, count: Playlist::DillaSketch::MAX_NAME)
    assert sketch.errors.added?(:state, :blank)
    assert sketch.errors.added?(:render_status, :inclusion, value: "exploded")
  end

  test "the lab hash reads either spelling of the three sections and fills style, bars and name" do
    underscored = Playlist::DillaSketch.new(name: "Loop",
                                            state: { "pat_" => [ 1 ], "mix_" => { "style" => "soul", "bars" => 8 } })
    plain = Playlist::DillaSketch.new(name: "Loop", state: { "aud" => { "bpm" => 88 } }, style: nil, bars: nil)

    assert_equal({ pat_: [ 1 ], aud_: nil, mix_: { style: "soul", bars: 8 }, style: "dilla", bars: 12, name: "Loop" },
                 underscored.to_lab_hash)
    assert_equal({ pat_: nil, aud_: { bpm: 88 }, mix_: nil, style: "dilla", bars: 12, name: "Loop" }, plain.to_lab_hash)
  end

  test "a state with no sections passes through, and the mix supplies defaults the columns lack" do
    loose = Playlist::DillaSketch.new(name: "Løs", state: { "swing" => 0.6 }, style: nil, bars: nil)
    mixed = Playlist::DillaSketch.new(name: "Mix", state: { "mix_" => { "style" => "jazz", "bars" => 4 } },
                                      style: nil, bars: nil)

    assert_equal({ swing: 0.6, style: "dilla", bars: 12, name: "Løs" }, loose.to_lab_hash)
    assert_equal [ "jazz", 4 ], mixed.to_lab_hash.values_at(:style, :bars)
  end

  test "the lab url names the sketch and its set, and carries the state in the fragment" do
    set = Playlist::Set.create!(user: @user, name: "Skisser")
    sketch = Playlist::DillaSketch.create!(user: @user, set: set, name: "Beat", state: { "pat_" => [ 1, 0 ] })

    url = sketch.lab_url
    path, fragment = url.split("#", 2)

    assert_equal "/dilla/dilla.html?sketch_id=#{sketch.id}&set_id=#{set.id}", path
    assert_equal sketch.to_lab_hash.deep_stringify_keys, JSON.parse(Base64.strict_decode64(fragment))
  end

  test "queueing a render clears the last error and enqueues the job" do
    sketch = Playlist::DillaSketch.create!(user: @user, name: "Render", state: { "swing" => 0.5 },
                                           render_status: "failed", render_error: "timeout")

    assert_enqueued_with(job: DillaRenderJob, args: [ sketch.id, { publish: false } ]) do
      sketch.enqueue_render!(publish: false)
    end
    assert_equal [ "queued", nil ], sketch.reload.values_at(:render_status, :render_error)
  end

  test "a sketch with no render publishes nothing" do
    sketch = Playlist::DillaSketch.create!(user: @user, name: "Tom", state: { "swing" => 0.5 })

    assert_no_difference "Playlist::Track.count" do
      assert_nil sketch.publish_as_track!
    end
  end
end
