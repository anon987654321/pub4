# frozen_string_literal: true

require "test_helper"
require "rake"

# tv:ingest is how the empty vertical gets content — repligen output or the
# test cards — so it carries the two properties an ingest must have: it is
# idempotent (a re-run adds nothing), and it is tenant-correct, because the
# tv channel tenancy asymmetry has already produced one production 500
# (acts_as_tenant on the parent nils a required belongs_to on the child).
class TvIngestTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    Rails.application.load_tasks unless Rake::Task.task_defined?("tv:ingest")
    @dir = Dir.mktmpdir
    FileUtils.cp(Rails.root.join("test/fixtures/files/tiny.mp4"), @dir)
    FileUtils.cp(Rails.root.join("test/fixtures/files/tiny.png"), @dir)
    File.write(File.join(@dir, "manifest.yml"), {
      "city" => "brgen.no",
      "channel" => { "name" => "Testkanal", "slug" => "testkanal-#{SecureRandom.hex(3)}" },
      "videos" => [
        { "title" => "Klipp én", "file" => "tiny.mp4", "thumbnail" => "tiny.png",
          "duration_seconds" => 1, "status" => "published" },
        { "title" => "Klipp to", "file" => "tiny.mp4", "duration_seconds" => 1 }
      ]
    }.to_yaml)
    ActsAsTenant.current_tenant = @city
    User.create!(email_address: "tvowner-#{SecureRandom.hex(4)}@brgen.no",
                 password: SecureRandom.hex(16), username: "tv_#{SecureRandom.hex(3)}", city: @city)
    ActsAsTenant.current_tenant = nil
  end

  teardown do
    FileUtils.rm_rf(@dir)
    ActsAsTenant.current_tenant = nil
  end

  def run_ingest
    Rake::Task["tv:ingest"].reenable
    Rake::Task["tv:ingest"].invoke(File.join(@dir, "manifest.yml"))
  end

  test "ingest creates the channel and published videos in the right city, and re-running adds nothing" do
    assert_output(/2 new video\(s\), 2 total/) { run_ingest }

    ActsAsTenant.with_tenant(@city) do
      channel = Tv::Channel.where("slug LIKE 'testkanal%'").first
      assert channel, "channel must exist inside the city tenant"
      assert_equal @city.id, channel.city_id, "the tenancy asymmetry: the channel must carry the city"
      assert_equal 2, channel.videos.count
      one = channel.videos.find_by!(title: "Klipp én")
      assert_equal "published", one.status
      assert one.video_file.attached?
      assert one.thumbnail.attached?
    end

    assert_output(/0 new video\(s\), 2 total/) { run_ingest }
  end
end
