# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RadioBergenImportGuardTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync!
    @bergen = City.find_by!(domain: "brgen.no")
    @los_angeles = City.find_by!(domain: "lsangeles.com")
    @bergen_owner = create_owner(@bergen)
    @los_angeles_owner = create_owner(@los_angeles)
    ActsAsTenant.current_tenant = nil
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "does not import without operator confirmation" do
    importer = Playlist::RadioBergenArchiveImport.new(
      owner: nil, city: nil, archive_root: Dir.pwd
    )

    assert_raises(Playlist::RadioBergenArchiveImport::RightsNotConfirmed) { importer.call }
  end

  test "refuses a missing city before archive reads or playlist writes" do
    before = Playlist::Playlist.unscoped.count
    importer = Playlist::RadioBergenArchiveImport.new(
      owner: @bergen_owner, city: nil, archive_root: Dir.pwd, rights_confirmed: true
    )

    assert_raises(Playlist::RadioBergenArchiveImport::TenantNotSelected) { importer.call }
    assert_equal before, Playlist::Playlist.unscoped.count
  end

  test "refuses an owner belonging to another city" do
    before = Playlist::Playlist.unscoped.count
    importer = Playlist::RadioBergenArchiveImport.new(
      owner: @los_angeles_owner, city: @bergen, archive_root: Dir.pwd, rights_confirmed: true
    )

    assert_raises(Playlist::RadioBergenArchiveImport::OwnerTenantMismatch) { importer.call }
    assert_equal before, Playlist::Playlist.unscoped.count
  end

  test "creates the curated playlist inside brgen.no and restores the previous tenant" do
    Dir.mktmpdir do |dir|
      filename = "radio-bergen-test.mp3"
      File.binwrite(File.join(dir, filename), "test audio bytes")
      entry = { "source_file" => filename, "title" => "Test track", "artist" => "Test artist" }
      playlist_name = "Radio Bergen tenant test"
      result = nil

      Brgen::RadioBergenManifest.stub(:curated_tracks, [entry]) do
        Brgen::RadioBergenManifest.stub(:curated_playlist_name, playlist_name) do
          Brgen::RadioBergenManifest.stub(:curated_description, "Tenant-scoped import test") do
            Brgen::RadioBergenManifest.stub(:curated_album, "Tenant-scoped test") do
              importer = Playlist::RadioBergenArchiveImport.new(
                owner: @bergen_owner, city: @bergen, archive_root: dir, rights_confirmed: true
              )
              result = importer.call
            end
          end
        end
      end

      assert_equal @bergen.id, result.playlist.reload.city_id
      assert_equal 1, result.tracks.length
      assert_nil ActsAsTenant.current_tenant
      visible_in_los_angeles = ActsAsTenant.with_tenant(@los_angeles) do
        Playlist::Playlist.exists?(id: result.playlist.id)
      end
      assert_not visible_in_los_angeles
      assert_not Playlist::Playlist.unscoped.where(id: result.playlist.id, city_id: nil).exists?
    end
  end

  private

  def create_owner(city)
    ActsAsTenant.with_tenant(city) do
      User.strict_loading(false).create!(
        email_address: "radio-import-#{city.slug}-#{SecureRandom.hex(4)}@example.test",
        password: "password123",
        city: city
      )
    end
  end
end
