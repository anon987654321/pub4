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
    owner = User.find_by!(email_address: owner_email)

    result = Playlist::RadioBergenArchiveImport.new(
      owner: owner,
      archive_root: archive_root,
      rights_confirmed: ENV["RADIO_BERGEN_RIGHTS_CONFIRMED"] == "1"
    ).call

    puts "playlist0: #{result.playlist.name}"
    puts "tracks0: #{result.tracks.size}"
    puts "audio_attached0: #{result.new_audio_attachments}"
    puts "playlist_entries_added0: #{result.new_playlist_entries}"
    puts "streaming0: Active Storage attachments; no media was committed to Git"
  end
end
