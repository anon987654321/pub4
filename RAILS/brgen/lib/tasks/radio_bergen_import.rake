# frozen_string_literal: true

namespace :radio_bergen do
  desc "Import the selected pub2 Radio Bergen crate into Playlist/Active Storage"
  task import_curated: :environment do
    archive_root = ENV.fetch("RADIO_BERGEN_ARCHIVE_ROOT") do
      abort "Set RADIO_BERGEN_ARCHIVE_ROOT to the local pub2 checkout containing the selected MP3 files."
    end
    owner_email = ENV.fetch("RADIO_BERGEN_OWNER_EMAIL") do
      abort "Set RADIO_BERGEN_OWNER_EMAIL to an existing Brgen account that will own the playlist."
    end
    city = City.find_by(domain: "brgen.no") or abort "brgen.no city missing; sync the city registry before importing"
    result = ActsAsTenant.with_tenant(city) do
      owner = User.find_by!(email_address: owner_email)
      Playlist::RadioBergenArchiveImport.new(
        owner: owner,
        city: city,
        archive_root: archive_root,
        rights_confirmed: ENV["RADIO_BERGEN_RIGHTS_CONFIRMED"] == "1"
      ).call
    end

    puts "playlist0: #{result.playlist.name}"
    puts "tracks0: #{result.tracks.size}"
    puts "audio_attached0: #{result.new_audio_attachments}"
    puts "playlist_entries_added0: #{result.new_playlist_entries}"
    puts "streaming0: Active Storage attachments; no media was committed to Git"
  end
end
