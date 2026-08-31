# The crate, dug from its manifest.
#
# Lives in the repo, not in a scratchpad: the scratchpad swept two earlier
# copies of this away mid-run. Resumable -- a slug whose chopped rack exists is
# skipped -- so it can be killed and restarted without losing a track.
#
# The dug source is deleted after its chop. Fifty-two full-length WAVs plus
# their demucs stems do not fit on this disk, and the loops are what the engine
# plays; the source is scaffolding. chop demucses and strips drums and vocals,
# so every rack arrives drumless and the kit is always ours.
require "yaml"

D = File.expand_path("..", __dir__)
YTDLP = "/opt/homebrew/bin/yt-dlp"
# Eight minutes. A thirty-eight-minute ambient set is 417MB of source and hours
# of demucs for a loop nobody will chop; the crate is songs, not sets.
MAX_SECONDS = 480

Dir.chdir(D)
crate = YAML.safe_load_file("project/crate.yml")["crate"].select { |e| e["available"] }
slugify = ->(t) { t.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")[0, 44] }

crate.each_with_index do |entry, i|
  slug = slugify.call(entry["title"])
  next if slug.empty?
  next if entry["duration_s"].to_i > MAX_SECONDS
  if Dir.glob("samples/chopped/#{slug}*").any?
    puts "[#{i + 1}/#{crate.size}] have #{slug}"
    next
  end

  src = "samples/dug/#{slug}.wav"
  unless File.file?(src)
    puts "[#{i + 1}/#{crate.size}] dig #{slug}"
    system(YTDLP, "-f", "bestaudio", "--extract-audio", "--audio-format", "wav",
           "-q", "--no-warnings", "-o", "samples/dug/#{slug}.%(ext)s",
           "https://youtu.be/#{entry["id"]}")
  end
  next puts("  MISS #{slug}") unless File.file?(src)

  puts "  chop #{slug} (#{File.size(src) / 1024 / 1024}MB)"
  system({ "RBENV_VERSION" => "3.4.9" }, "rbenv", "exec", "ruby", "dilla.rb", "chop", src,
         out: File::NULL, err: File::NULL)
  File.delete(src) if File.file?(src)
  puts "  done #{slug}  racks=#{Dir.glob("samples/chopped/*/").size}  free=#{`df -h /Users/mac`.lines.last.split[3]}"
end
puts "CRATE_DIG_COMPLETE racks=#{Dir.glob("samples/chopped/*/").size}"
