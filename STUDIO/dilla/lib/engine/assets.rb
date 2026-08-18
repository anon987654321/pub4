# frozen_string_literal: true
#
# Fetching external soundfonts and kits, and digging the crate.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Explicit, opt-in external asset fetch (never runs on its own — the whole
# engine is otherwise pure-Ruby/ffmpeg synthesis with zero external assets).
# Caches into the same ~/.cache/dilla-soundfonts dir GeneralUser-GS already
# uses, plus a sibling ~/.cache/dilla-samples for one-shot drum WAVs.
EXTERNAL_SOUNDFONTS = {
  "galaxy-electric-pianos.sf2" => "https://smpldsnds.github.io/soundfonts/soundfonts/galaxy-electric-pianos.sf2",
  "supersaw-collection.sf2" => "https://smpldsnds.github.io/soundfonts/soundfonts/supersaw-collection.sf2",
  "giga-hq-fm-gm.sf2" => "https://smpldsnds.github.io/soundfonts/soundfonts/giga-hq-fm-gm.sf2",
  # Yamaha C grand (lite) — acoustic piano body the GM bank never quite nails.
  "yamaha-grand-lite.sf2" => "https://smpldsnds.github.io/soundfonts/soundfonts/yamaha-grand-lite.sf2",
}.freeze
EXTERNAL_DRUM_KIT_REPO = "https://github.com/Boochi44/free-drum-samples"
EXTERNAL_DRUM_KIT_CACHE = File.expand_path("~/.cache/dilla-samples/free-drum-samples")

# Fetched assets are pinned by content: the first fetch records each file's
# SHA256 (and the drum-kit repo's HEAD commit) into checksums.json next to
# the cache; later runs verify and warn on drift instead of silently
# rendering with different-sounding assets. Warn, not abort — upstream may
# have legitimately updated, and the fix is deleting the manifest entry.
def assets_verify_or_record!(manifest_path, key, actual)
  require "digest" # cheap, but only needed on this path
  manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path)) : {}
  if manifest.key?(key)
    return if manifest[key] == actual
    warn "warn: #{key} changed since first fetch (#{manifest[key][0, 12]}… -> #{actual[0, 12]}…) — " \
         "renders may sound different; delete its entry in #{manifest_path} to accept the new version"
  else
    manifest[key] = actual
    File.write(manifest_path, JSON.pretty_generate(manifest))
  end
end

def fetch_assets!
  require_tools! "curl"
  require "digest"
  sf_dir = File.expand_path("~/.cache/dilla-soundfonts")
  FileUtils.mkdir_p(sf_dir)
  manifest_path = File.join(sf_dir, "checksums.json")
  EXTERNAL_SOUNDFONTS.each do |name, url|
    dest = File.join(sf_dir, name)
    if File.exist?(dest)
      puts "have: #{name}"
    else
      puts "fetching #{name}..."
      sh! "curl", "-sL", "--fail", "-o", dest, url
    end
    assets_verify_or_record!(manifest_path, name, Digest::SHA256.file(dest).hexdigest)
  end

  # VintageDreamsWaves ships with fluid-synth — copy into the cache so
  # patch_sf2_path(:vintage_dreams) is stable and checksummed like the rest.
  vintage_dest = File.join(sf_dir, "VintageDreamsWaves-v2.sf2")
  unless File.exist?(vintage_dest)
    src = Dir.glob("/opt/homebrew/Cellar/fluid-synth/*/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2").first ||
          Dir.glob("/usr/local/Cellar/fluid-synth/*/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2").first
    if src && File.exist?(src)
      FileUtils.cp(src, vintage_dest)
      puts "have: VintageDreamsWaves-v2.sf2 (from fluid-synth)"
    end
  end
  if File.exist?(vintage_dest)
    assets_verify_or_record!(manifest_path, "VintageDreamsWaves-v2.sf2",
                             Digest::SHA256.file(vintage_dest).hexdigest)
  end

  if Dir.exist?(EXTERNAL_DRUM_KIT_CACHE)
    puts "have: free-drum-samples"
  else
    require_tools! "git"
    puts "fetching free-drum-samples (CC0)..."
    FileUtils.mkdir_p(File.dirname(EXTERNAL_DRUM_KIT_CACHE))
    sh! "git", "clone", "--depth", "1", EXTERNAL_DRUM_KIT_REPO, EXTERNAL_DRUM_KIT_CACHE
  end
  head, _err, status = capture("git", "-C", EXTERNAL_DRUM_KIT_CACHE, "rev-parse", "HEAD")
  assets_verify_or_record!(manifest_path, "free-drum-samples@HEAD", head.strip) if status.success?
  puts "assets cached. Use DILLA_SOUNDFONT=#{sf_dir}/<file>.sf2, or `ruby dilla.rb use-external-kit <01-hard-trap|02-bounce|03-soulful-vintage>`."
end

# Copies one kit's one-shots into CUSTOM_DRUM_DIR, which drum_sample_path
# already prefers over the synthesized kit — no synthesis code changes
# needed, this just populates the existing override hook.
# Dig one seam into samples/dug/, recording provenance per side.
#
# Filtered to the public domain before anything is fetched -- see
# CrateDig.pd_year_ceiling. The engine already refuses to write lyrics from real
# songs because those are copyrighted; this is the same rule applied to audio,
# and it is why this exists instead of another yt-dlp call.
def crate_dig!(seam, count)
  unless seam && CrateDig::SEAMS.key?(seam)
    abort "usage: dig <seam> [n]  — seams: #{CrateDig::SEAMS.keys.join(', ')}"
  end

  puts "digging #{seam} (public domain through #{CrateDig.pd_year_ceiling})..."
  # Over-fetch: some sides are already held and some carry no usable transfer.
  docs = CrateDig.search(collection: "great78", seam: seam, rows: count * 3)
  taken = 0

  docs.each do |doc|
    break if taken >= count

    id = doc["identifier"]
    if CrateDig.have?(id)
      puts "  have: #{id}"
      next
    end

    begin
      file = CrateDig.best_file(id)
      next unless file

      dest = File.join(CrateDig::DUG, seam, "#{id}#{File.extname(file['name'])}")
      print "  #{doc['year']}  #{doc['title'].to_s[0, 44]} ... "
      CrateDig.download(file["url"], dest)
      CrateDig.record!(
        "identifier" => id, "seam" => seam, "year" => doc["year"],
        "title" => doc["title"], "creator" => Array(doc["creator"]).first,
        "source" => "https://archive.org/details/#{id}", "collection" => "great78",
        "basis" => "US public domain — published #{doc['year']}, MMA 100-year term expired",
        "rights" => file["rights"], "licenseurl" => file["licenseurl"],
        "path" => dest.sub("#{ROOT}/", ""),
        "sha256" => Digest::SHA256.file(dest).hexdigest, "bytes" => File.size(dest)
      )
      puts "#{(File.size(dest) / 1024.0 / 1024).round(1)}MB"
      taken += 1
    rescue StandardError => e
      puts "skip (#{e.class}: #{e.message.to_s[0, 60]})"
    end
  end

  puts "dug #{taken} side(s) into #{CrateDig::DUG.sub("#{ROOT}/", '')}/#{seam}/"
  puts "provenance: #{CrateDig::MANIFEST.sub("#{ROOT}/", '')}"
end

# Dig a ccMixter seam — the only legitimate route to reggae, dub and modern
# breaks, because those idioms postdate the public domain entirely.
#
# Everything fetched is CC-BY or freer: commercial use permitted, credit
# required. The credit obligation is real, so `dug --credits` prints it from the
# provenance rather than leaving it to memory.
def cc_dig!(seam, count)
  unless seam && CrateDig::CC_SEAMS.key?(seam)
    abort "usage: dig-cc <seam> [n]  — seams: #{CrateDig::CC_SEAMS.keys.join(', ')}"
  end

  puts "digging ccMixter #{seam} (CC-BY or freer; NC excluded)..."
  rows = CrateDig.ccmixter_search(seam: seam, rows: count * 3)
  taken = 0

  rows.each do |row|
    break if taken >= count

    id = "ccmixter-#{row['upload_id']}"
    if CrateDig.have?(id)
      puts "  have: #{id}"
      next
    end

    begin
      file = Array(row["files"]).find { |f| f["file_name"].to_s =~ /\.(mp3|flac|wav|ogg)\z/i }
      next unless file

      url = file["download_url"] || file["file_url"] ||
            "https://ccmixter.org/content/#{row['user_name']}/#{file['file_name']}"
      dest = File.join(CrateDig::DUG, seam, "#{id}#{File.extname(file['file_name'])}")
      print "  #{row['upload_name'].to_s[0, 40]} — #{row['user_name']} ... "
      CrateDig.download(url, dest)
      sha = Digest::SHA256.file(dest).hexdigest
      # file_name is the file actually downloaded. ccmixter_entry used to record
      # files.first while this picks the first *audio* file, so any upload whose
      # first file is a zip recorded a name that did not match its own sha256.
      CrateDig.record!(CrateDig.ccmixter_entry(row, seam, dest.sub("#{ROOT}/", ""), sha,
                                               file_name: file["file_name"])
                         .merge("bytes" => File.size(dest)))
      puts "#{(File.size(dest) / 1024.0 / 1024).round(1)}MB [#{row['license_name']}]"
      taken += 1
    rescue StandardError => e
      puts "skip (#{e.class}: #{e.message.to_s[0, 60]})"
    end
  end

  puts "dug #{taken} from ccMixter into #{CrateDig::DUG.sub("#{ROOT}/", '')}/#{seam}/"
  puts "these require credit — `ruby dilla.rb credits` prints it" if taken.positive?
end

# CC-BY is free to use and not free of obligation. This is the list you owe.
def crate_credits
  rows = CrateDig.manifest["items"].select { |i| i["attribution"] }
  if rows.empty?
    puts "no attribution owed — everything dug so far is public domain."
    return
  end
  puts "Credits owed (CC-BY material in the crate):"
  rows.each { |i| puts "  #{i['attribution']}" }
  puts
  puts "#{rows.size} item(s). Public-domain sides carry no obligation and are not listed."
end

def crate_seams
  puts "seams (archive.org Great 78, filtered to the public domain):"
  CrateDig::SEAMS.each { |name, q| puts format("  %-12s %s", name, q) }
  puts
  puts "public domain through #{CrateDig.pd_year_ceiling}; widens by one year each January."
end

def dug_list
  items = CrateDig.manifest["items"]
  if items.empty?
    puts "nothing dug yet — try: ruby dilla.rb dig jazz_small 8"
    return
  end
  items.group_by { |i| i["seam"] }.each do |seam, rows|
    puts "#{seam} (#{rows.size})"
    rows.each { |i| puts format("  %s  %-42s %s", i["year"], i["title"].to_s[0, 42], i["creator"]) }
  end
  puts
  # Was "all US public domain", printed over a manifest that by then held six
  # CC-BY items. Public domain carries no obligation and CC-BY carries credit;
  # a summary that flattens them tells the reader they owe nothing.
  pd = items.count { |i| i["collection"] != "ccmixter" }
  cc = items.size - pd
  parts = ["#{pd} public-domain side(s)"]
  parts << "#{cc} CC-licensed (credit owed — run `ruby dilla.rb credits`)" if cc.positive?
  puts "#{parts.join(', ')}. Source URL, licence and SHA-256 per side in " \
       "#{File.basename(CrateDig::MANIFEST)}."
end

def use_external_kit!(kit_name)
  src_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", kit_name)
  abort "kit '#{kit_name}' not found — run `ruby dilla.rb fetch-assets` first" unless Dir.exist?(src_dir)
  FileUtils.mkdir_p(CUSTOM_DRUM_DIR)
  {
    "kick.wav" => "kicks", "snare.wav" => "snares", "hat.wav" => "hi-hats",
    "open_hat.wav" => "open-hats", "ghost.wav" => "claps", "bass_43.wav" => "808s"
  }.each do |dest_name, subdir|
    src = Dir.glob(File.join(src_dir, subdir, "*.wav")).min_by { |f| File.size(f) }
    next unless src
    FileUtils.cp(src, File.join(CUSTOM_DRUM_DIR, dest_name))
    puts "installed #{dest_name} <- #{kit_name}/#{subdir}/#{File.basename(src)}"
  end
  puts "custom kit installed — clear #{CUSTOM_DRUM_DIR} to go back to synthesized drums."
end
