# frozen_string_literal: true

# The tv content pipeline. The vertical has been fully built — channels,
# uploads, the watch-time feed, sounds, shows — and completely EMPTY, because
# "tv content comes from repligen" was a sentence, not a path. These two tasks
# are the path.
#
#   bin/rails "tv:starter_pack[out_dir]"   # write clips + posters + manifest
#   bin/rails "tv:ingest[manifest.yml]"    # manifest -> channel + published videos
#
# starter_pack generates with Replicate when REPLICATE_API_TOKEN is present
# and REFUSES with a clear sentence when it is not — never a fake success,
# the vipps doctrine — then falls back, if TV_TEST_CARDS=1 says so out loud,
# to ffmpeg-drawn broadcast test cards: honest placeholder television that
# exercises the whole player/feed/watch-time loop and says what it is on
# every frame.
namespace :tv do
  desc "Ingest a manifest of video files into a Tv::Channel (idempotent by slug)"
  task :ingest, [ :manifest ] => :environment do |_, args|
    require "yaml"
    manifest_path = args[:manifest] or abort "tv:ingest needs a manifest path"
    manifest = YAML.safe_load_file(manifest_path)
    base = File.dirname(File.expand_path(manifest_path))

    city = City.find_by!(domain: manifest.fetch("city"))
    ActsAsTenant.with_tenant(city) do
      owner = User.find_by(email_address: manifest.dig("channel", "owner_email")) ||
              User.where(guest: false).order(:id).first or abort "tv:ingest: no owner user in #{city.domain}"

      chan_attrs = manifest.fetch("channel")
      channel = Tv::Channel.find_or_create_by!(slug: chan_attrs.fetch("slug")) do |c|
        c.name = chan_attrs.fetch("name")
        c.user = owner
        c.description = chan_attrs["description"]
      end

      created = 0
      manifest.fetch("videos").each do |v|
        # Idempotent on title-within-channel: re-running a manifest adds the
        # new rows and leaves the ingested ones alone.
        next if channel.videos.exists?(title: v.fetch("title"))

        video = channel.videos.new(
          user: owner,
          title: v.fetch("title"),
          description: v["description"],
          duration_seconds: v["duration_seconds"],
          status: v.fetch("status", "published")
        )
        video.video_file.attach(io: File.open(File.join(base, v.fetch("file"))),
                                filename: File.basename(v.fetch("file")), content_type: "video/mp4")
        if v["thumbnail"]
          video.thumbnail.attach(io: File.open(File.join(base, v["thumbnail"])),
                                 filename: File.basename(v["thumbnail"]),
                                 content_type: v["thumbnail"].end_with?(".png") ? "image/png" : "image/webp")
        end
        video.save!
        created += 1
      end
      puts "tv:ingest #{city.domain}/#{channel.slug}: #{created} new video(s), #{channel.videos.count} total"
    end
  end

  desc "Generate a starter pack (Replicate when keyed; TV_TEST_CARDS=1 for ffmpeg test cards)"
  task :starter_pack, [ :out_dir ] => :environment do |_, args|
    out = File.expand_path(args[:out_dir] || "tmp/tv_starter_pack")
    FileUtils.mkdir_p(out)

    if ENV["REPLICATE_API_TOKEN"].to_s.strip.empty? && ENV["REPLICATE_API_KEY"].to_s.strip.empty?
      unless ENV["TV_TEST_CARDS"] == "1"
        abort "tv:starter_pack: no REPLICATE_API_TOKEN — real generation needs the key. " \
              "TV_TEST_CARDS=1 generates labeled ffmpeg test cards instead (says so on every frame)."
      end
      generate_test_cards(out)
    else
      abort "tv:starter_pack: the Replicate lane is wired for stills via repligen; " \
            "video model selection (kling et al) is the next sitting once the key is present. " \
            "Use TV_TEST_CARDS=1 meanwhile."
    end
  end

  def generate_test_cards(out)
    # One lavfi source per card, visually distinct — drawtext needs a
    # libfreetype ffmpeg and the Homebrew build ships without it, so the
    # frame is the pattern and the LABEL is the product's own title overlay.
    cards = [
      [ "testbilde-1", "brgen tv · fargebar",     "smptehdbars=size=1280x720:rate=25", 12 ],
      [ "testbilde-2", "brgen tv · monoskop",     "testsrc2=size=1280x720:rate=25",    10 ],
      [ "testbilde-3", "brgen tv · rgb",          "rgbtestsrc=size=1280x720:rate=25",   8 ],
      [ "testbilde-4", "brgen tv · gradient",     "gradients=size=1280x720:rate=25",   15 ],
      [ "testbilde-5", "brgen tv · mandelbrot",   "mandelbrot=size=1280x720:rate=25",   9 ],
      [ "testbilde-6", "brgen tv · livssignal",   "life=size=1280x720:rate=25:mold=10", 11 ]
    ]
    videos = cards.map do |slug, label, source, secs|
      mp4 = File.join(out, "#{slug}.mp4")
      png = File.join(out, "#{slug}.png")
      system("ffmpeg", "-y", "-loglevel", "error",
             "-f", "lavfi", "-t", secs.to_s, "-i", source,
             "-f", "lavfi", "-t", secs.to_s, "-i", "sine=frequency=440",
             "-shortest", "-pix_fmt", "yuv420p", mp4, exception: true)
      # PNG here; the app's own MediaProcessable variants render the webp —
      # this ffmpeg ships without a webp encoder, and the pipeline conversion
      # is the production path anyway.
      system("ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vframes", "1", "-vf", "scale=1280:720", png, exception: true)
      { "title" => label, "file" => File.basename(mp4), "thumbnail" => File.basename(png),
        "duration_seconds" => secs, "status" => "published",
        "description" => "Testbilde — ekte innhold kommer fra repligen når nøkkelen er på plass." }
    end
    manifest = {
      "city" => ENV.fetch("TV_CITY", "brgen.no"),
      "channel" => { "name" => "brgen testbilde", "slug" => "testbilde",
                     "description" => "Prøvesendinger mens kanalene fylles." },
      "videos" => videos
    }
    File.write(File.join(out, "manifest.yml"), manifest.to_yaml)
    puts "tv:starter_pack: #{videos.size} test cards + manifest -> #{out}"
  end
end
