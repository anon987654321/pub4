# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rubygems/package"
require "time"
require_relative "../../atomic_write"

# What a paid run checks before it spends. A dataset that is too small, too soft
# or captioned against the caption law costs the same per second as a good one,
# so the checks run on the Mac, in seconds, before anything is uploaded.
#
# The preflight shape rules follow Replicate's fine-tuning guide. The cost rate
# must match Studio::ReplicateClient::LORA_TRAINER_VERSION: the reviewed version's
# public page lists H200 hardware at $0.001525/s. Training deliberately avoids the
# provider's moving "latest" pointer, so a hardware/rate change requires a pin review.
module Preflight
  IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze

  MIN_IMAGES = 10
  FLOOR_SHORT_EDGE = 512
  PREFERRED_SHORT_EDGE = 1024
  RESERVED_TRIGGERS = %w[tok].freeze
  DICTIONARY = "/usr/share/dict/words"

  # The guide estimate is 1000 steps in about two minutes; one logged run took
  # fourteen. Show both runtimes at the pinned version's published hardware rate.
  # https://replicate.com/ostris/flux-dev-lora-trainer/versions
  TRAIN_USD_PER_SECOND = 0.001525
  GUIDE_SECONDS_PER_STEP = 0.12
  OBSERVED_SECONDS_PER_STEP = 0.84

  # Stills and clips are billed by GPU time, not tokens. The rate is Replicate's
  # published H100 price (replicate.com/pricing). That flux-dev-lora runs on an
  # H100 is an assumption, and a clip's price per run is not in the API at all.
  RENDER_USD_PER_SECOND = 0.001525
  OBSERVED_RENDER_SECONDS = 7.5

  # Caption law (curate.rb): face shape, eye colour, natural hair colour and age
  # belong to the trigger token. A caption that names them spreads identity over
  # generic words.
  AGE_WORDS = /\b(?:\d{2}[- ]?(?:years?|yo)\b|years?[- ]old|middle[- ]aged|elderly|young(?:er)?|teen(?:age|ager)?|aged)\b/i
  IDENTITY_WORDS = /\b(?:(?:blonde?|brunette|brown|black|red|grey|gray|auburn)[- ]hair(?:ed)?|(?:blue|green|brown|hazel|grey|gray)[- ]eyes?|eye colou?r|face shape|cheekbones?)\b/i

  # Hamming distance between 8x8 average hashes at or under which two frames
  # are one moment photographed twice.
  NEAR_DUPLICATE_BITS = 5

  Report = Struct.new(:images, :problems, :warnings, keyword_init: true) do
    def ok? = problems.empty?
  end

  module_function

  def image_files(dir)
    Dir.children(dir).map { |name| File.join(dir, name) }
       .select { |path| File.file?(path) && IMAGE_EXT.include?(File.extname(path).downcase) }.sort
  end

  # [width, height] from the file header alone: the checks must run where no
  # image library does, and a header read cannot be fooled by a decoder.
  def image_size(path)
    File.open(path, "rb") do |file|
      head = file.read(32).to_s
      return png_size(head) if head.start_with?("\x89PNG".b)

      return jpeg_size(file) if head.start_with?("\xFF\xD8".b)
      return webp_size(head) if head[0, 4] == "RIFF" && head[8, 4] == "WEBP"
    end
    nil
  end

  def png_size(head) = head[16, 8].unpack("NN")

  def jpeg_size(file)
    file.seek(2)
    loop do
      prefix = file.read(1)
      return unless prefix&.getbyte(0) == 0xFF

      marker = file.read(1)
      marker = file.read(1) while marker&.getbyte(0) == 0xFF
      return unless marker

      code = marker.getbyte(0)
      return if code == 0xD8 || code == 0xD9
      next if code == 0x01 || (0xD0..0xD7).cover?(code)

      length = file.read(2)&.unpack1("n") or return
      if (0xC0..0xCF).cover?(code) && ![0xC4, 0xC8, 0xCC].include?(code)
        data = file.read(5) or return
        _precision, height, width = data.unpack("Cnn")
        return [width, height]
      end
      file.seek(length - 2, IO::SEEK_CUR)
    end
  end

  def webp_size(head)
    case head[12, 4]
    when "VP8X" then [le24(head[24, 3]) + 1, le24(head[27, 3]) + 1]
    when "VP8L"
      bits = head[21, 4].unpack1("V")
      [(bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1]
    when "VP8 " then head[26, 4].unpack("vv").map { |value| value & 0x3FFF }
    end
  end

  def le24(bytes) = bytes.unpack("C3").each_with_index.sum { |byte, i| byte << (8 * i) }

  def caption_for(image) = "#{image.delete_suffix(File.extname(image))}.txt"

  # Problems stop a paid run; warnings are printed and do not.
  def dataset_report(dir, trigger:)
    images = image_files(dir)
    problems = []
    warnings = []
    problems << "#{images.length} image(s); Replicate recommends at least #{MIN_IMAGES}" if images.length < MIN_IMAGES

    check_sizes(images, problems, warnings)
    check_captions(dir, images, trigger, problems, warnings)
    check_duplicates(images, warnings)
    Report.new(images:, problems:, warnings:)
  end

  def check_sizes(images, problems, warnings)
    tiny = []
    soft = []
    images.each do |path|
      size = image_size(path)
      next problems << "#{File.basename(path)}: unreadable image header" unless size

      edge = size.min
      tiny << "#{File.basename(path)} (#{edge})" if edge < FLOOR_SHORT_EDGE
      soft << File.basename(path) if edge.between?(FLOOR_SHORT_EDGE, PREFERRED_SHORT_EDGE - 1)
    end
    problems << "#{tiny.length} image(s) under #{FLOOR_SHORT_EDGE} on the short edge, below what FLUX trains on: #{tiny.first(3).join(', ')}" unless tiny.empty?
    warnings << "#{soft.length} image(s) under #{PREFERRED_SHORT_EDGE} on the short edge: #{soft.first(5).join(', ')}" unless soft.empty?
  end

  def check_captions(dir, images, trigger, problems, warnings)
    images.each do |path|
      caption = caption_for(path)
      name = File.basename(caption)
      next warnings << "#{name}: no caption" unless File.file?(caption)

      text = File.read(caption)
      if text.strip == "#{trigger.strip},"
        problems << "#{name}: stub caption needs review; describe pose, clothing, light and setting"
      end
      problems << "#{name}: names an age (#{text[AGE_WORDS]}); age rides the token" if text.match?(AGE_WORDS)
      warnings << "#{name}: names #{text[IDENTITY_WORDS].inspect}; identity rides the token" if text.match?(IDENTITY_WORDS)
      warnings << "#{name}: lacks the trigger #{trigger.inspect}" unless text.downcase.include?(trigger.downcase)
    end

    stems = images.map { |path| File.basename(path, ".*") }
    Dir.glob(File.join(dir, "*.txt")).each do |path|
      warnings << "#{File.basename(path)}: caption without an image" unless stems.include?(File.basename(path, ".txt"))
    end
  end

  # Ten frames of one moment are one training example with nine copies. The
  # hash needs ffmpeg; without it the check is skipped and says so.
  def check_duplicates(images, warnings)
    hashes = images.to_h { |path| [path, average_hash(path)] }
    return warnings << "near-duplicate check skipped: no ffmpeg" if hashes.values.any?(:no_ffmpeg)

    hashes.reject! { |_, hash| hash.nil? }
    pairs = hashes.keys.combination(2).select { |a, b| (hashes[a] ^ hashes[b]).to_s(2).count("1") <= NEAR_DUPLICATE_BITS }
    pairs.each { |a, b| warnings << "near-duplicates: #{File.basename(a)} and #{File.basename(b)}" }
  end

  def average_hash(path)
    out, _err, status = Open3.capture3("ffmpeg", "-v", "quiet", "-i", path, "-vf", "scale=8:8,format=gray",
                                       "-frames:v", "1", "-f", "rawvideo", "-", binmode: true)
    return unless status.success? && out.bytesize == 64

    mean = out.bytes.sum / 64.0
    out.bytes.each_with_index.sum { |byte, bit| byte > mean ? 1 << bit : 0 }
  rescue Errno::ENOENT
    :no_ffmpeg
  end

  def trigger_report(word)
    problems = []
    warnings = []
    problems << "trigger #{word.inspect} is reserved: it clashes with other fine-tunes" if RESERVED_TRIGGERS.include?(word.downcase)
    problems << "trigger #{word.inspect} is shorter than 4 letters" if word.length < 4
    problems << "trigger #{word.inspect} is an existing word" if dictionary_word?(word)
    warnings << "trigger #{word.inspect} is a plain name; FLUX has its own idea of it, and Replicate advises a string that is not a word (for example #{word}_lora)" if word.match?(/\A[a-z]+\z/i) && problems.empty?
    Report.new(images: [], problems:, warnings:)
  end

  def dictionary_word?(word)
    return false unless File.file?(DICTIONARY)

    File.foreach(DICTIONARY).any? { |line| line.strip.casecmp?(word) }
  end

  def cost_estimate(steps)
    guide = steps * GUIDE_SECONDS_PER_STEP
    observed = steps * OBSERVED_SECONDS_PER_STEP
    format("estimate: %<g>d s ($%<gu>.2f) by the guide's example, %<o>d s ($%<ou>.2f) by the logged run", g: guide, gu: guide * TRAIN_USD_PER_SECOND,
                                                                                                           o: observed, ou: observed * TRAIN_USD_PER_SECOND)
  end

  # Preflight ceiling uses the more expensive of the published guide runtime and
  # the observed run, priced at the explicitly pinned trainer version. This is a
  # hard pre-call estimate check, not a guarantee that provider billing cannot vary.
  def training_estimate_usd(steps)
    count = Integer(steps)
    raise ArgumentError, "steps must be a positive integer" unless count.positive?

    [GUIDE_SECONDS_PER_STEP, OBSERVED_SECONDS_PER_STEP].max * count * TRAIN_USD_PER_SECOND
  end

  def render_estimate(count)
    seconds = count * OBSERVED_RENDER_SECONDS
    format("cost before: %<n>d render(s) x ~%<s>.0f s = ~%<t>d s, ~$%<u>.3f at $%<r>s/s (billed by time, not tokens)",
           n: count, s: OBSERVED_RENDER_SECONDS, t: seconds, u: seconds * RENDER_USD_PER_SECOND, r: RENDER_USD_PER_SECOND)
  end

  # What a subject has been billed in all: a training row carries its own usd, a
  # render is its seconds at the render rate.
  # Parse the whole ledger or refuse to claim an amount. A malformed row is
  # unknown spend, not zero spend; continuing would understate cost and may pass
  # a ceiling that the recorded calls have already crossed.
  def ledger_rows(path)
    target = File.expand_path(path)
    raise IOError, "ledger path is a symlink: #{target}" if File.symlink?(target)
    return [] unless File.file?(target)

    File.foreach(target).with_index.map do |line, index|
      begin
        row = JSON.parse(line)
      rescue JSON::ParserError
        raise IOError, "ledger line #{index + 1} is invalid JSON"
      end
      raise IOError, "ledger line #{index + 1} is not a JSON object" unless row.is_a?(Hash)

      row
    end
  end

  # A response receipt is billable even if downloading its temporary URL failed.
  # Once a final render row with the same prediction id exists, count the final
  # row only; otherwise the attempt receipt carries the spend.
  def billable_render_rows(rows)
    renders = rows.select { |row| row["kind"] == "render" }

    rendered_ids = renders.filter_map do |row|
      id = row["id"].to_s
      id unless id.empty?
    end
    pending = rows.select do |row|
      next false unless row["kind"] == "render_attempt" && row["status"] == "prediction_received"

      id = row["id"].to_s
      id.empty? || !rendered_ids.include?(id)
    end
    renders + pending
  end

  def ledger_usd(path)
    rows = ledger_rows(path)
    render_rows = billable_render_rows(rows)
    render_row_ids = render_rows.map(&:object_id)
    rows.sum do |row|
      next row["usd"].to_f if row.key?("usd")
      next row["seconds"].to_f * RENDER_USD_PER_SECOND if render_row_ids.include?(row.object_id)

      0.0
    end
  end

  def sha256(path) = Digest::SHA256.file(path).hexdigest

  # One JSON line per paid call, appended where the subject's output lives, so
  # what a subject has cost is a file read. Never rotated or truncated: lora.rb
  # and the render scripts sum it to enforce the spend cap, so dropping old rows
  # would hand back budget already spent. It grows by about 100 bytes a call
  # (33 KB per subject by 2026-10); clips.jsonl beside a video is the same record.
  def ledger_append(path, row)
    target = File.expand_path(path)
    raise IOError, "ledger path is a symlink: #{target}" if File.symlink?(target)
    File.chmod(0o600, target) if File.file?(target) && (File.stat(target).mode & 0o077).positive?

    writer = Object.new.extend(Studio::AtomicWrite)
    writer.append_jsonl(target, { at: Time.now.utc.iso8601 }.merge(row), mode: 0o600)
  end

  # Stable identity for one paid render request. A rerun with changed
  # settings must not silently reuse an older prediction's URL.
  def render_fingerprint(model:, input:)
    normalized = input.sort_by { |key, _| key.to_s }.to_h.transform_keys(&:to_s)
    Digest::SHA256.hexdigest(JSON.generate(model: model.to_s, input: normalized))
  end

  # A paid call without a terminal receipt must never be repeated automatically.
  # A known prediction can be downloaded again only for the exact same request.
  def render_receipt_action(event, fingerprint:)
    return :new unless event

    if event["kind"] == "render_attempt"
      return :blocked if event["status"] == "started"
      return :blocked unless event["status"] == "prediction_received"
      return :resume if resumable_render_receipt?(event, fingerprint:)

      return :blocked
    end

    if event["kind"] == "render" && event["status"] == "output_ready" &&
       event["fingerprint"] == fingerprint
      return :resume if resumable_render_receipt?(event, fingerprint:)

      return :blocked
    end

    :new
  end

  def resumable_render_receipt?(event, fingerprint:)
    return false unless event["fingerprint"] == fingerprint
    return false if event["id"].to_s.empty? || event["output_url"].to_s.empty?

    seconds = Float(event["seconds"])
    seconds.finite? && seconds >= 0
  rescue ArgumentError, TypeError
    false
  end

  # Last known state for one sitting. Malformed ledger data blocks automatic
  # retries: dropping an unreadable paid receipt would risk charging twice.
  def latest_render_event(path, set:, n:)
    ledger_rows(path).reverse.find do |row|
      %w[render render_attempt].include?(row["kind"]) &&
        row["set"] == set && row["n"].to_i == n.to_i
    end
  end

  # Sum of billed seconds already in a ledger, for a spend ceiling.
  def ledger_seconds(path, kind)
    rows = ledger_rows(path)
    rows = billable_render_rows(rows) if kind == "render"
    rows.sum do |row|
      matching = row["kind"] == kind || (kind == "render" && row["kind"] == "render_attempt")
      matching ? row["seconds"].to_f : 0.0
    end
  end

  # Unknown duration and an unresolved create intent both leave total spend
  # unknowable. Evaluate only the latest state for each sitting, so a later
  # provider response or final receipt can supersede an older started row.
  def inconclusive_render_receipts(path)
    latest = ledger_rows(path).each_with_object({}) do |row, states|
      next unless %w[render render_attempt].include?(row["kind"])

      states[[row["set"].to_s, row["n"].to_s]] = row
    end

    latest.values.select do |row|
      next true if row["kind"] == "render_attempt" && row["status"] == "started"

      seconds = Float(row["seconds"])
      !seconds.finite? || seconds.negative?
    rescue ArgumentError, TypeError
      true
    end
  end

  # Inspect the archive format itself before extraction. Name-only tar listings
  # miss symlink/hardlink targets and special filesystem entries. Reject links,
  # special files, unsafe paths and duplicate checkpoint basenames.
  def unsafe_tar_entries(tar_path)
    unsafe = []
    weight_basenames = {}

    File.open(tar_path, "rb") do |file|
      Gem::Package::TarReader.new(file).each do |entry|
        header = entry.header
        name = entry.full_name.to_s
        type = header.typeflag.to_s
        root_name = name.tr("\\", "/").sub(/\/+\z/, "")
        next if type == "5" && root_name == "."

        # Strip harmless leading ./ segments produced by standard tar commands,
        # but refuse parent traversal, internal dot segments and ambiguous slashes.
        normalized = name.tr("\\", "/")
        normalized = normalized.sub(/\A(?:\.\/)+/, "")
        normalized = normalized.sub(/\/+\z/, "")
        parts = normalized.split("/")

        if normalized.empty? || normalized.start_with?("/") ||
           normalized.match?(/\A[A-Za-z]:/) || name.include?("\\") ||
           name.include?("\0") || parts.any? { |part| part.empty? || part == "." || part == ".." }
          unsafe << "#{name.inspect}: unsafe archive path"
          next
        end

        unless ["0", "\0", "5", "x", "g", "L", "K"].include?(type)
          unsafe << "#{name}: unsupported archive entry type #{type.inspect}"
          next
        end
        next unless ["0", "\0"].include?(type) && name.downcase.end_with?(".safetensors")

        basename = File.basename(normalized)
        key = basename.downcase
        if (previous = weight_basenames[key])
          unsafe << "#{name}: duplicate weight basename also used by #{previous}"
        else
          weight_basenames[key] = name
        end
      end
    end

    unsafe
  rescue StandardError => error
    ["archive could not be inspected (#{error.class}: #{error.message})"]
  end
end
