# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "time"

# What a paid run checks before it spends. A dataset that is too small, too soft
# or captioned against the caption law costs the same per second as a good one,
# so the checks run on the Mac, in seconds, before anything is uploaded.
#
# The figures are Replicate's fine-tuning guide (replicate.com/docs/guides/
# fine-tune-an-image-model): at least 10 images, 1024 on the short edge or more,
# a trigger that is not an existing word and not "TOK", and a run billed per
# second on 8x H100.
module Preflight
  IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze
  MIN_IMAGES = 10
  FLOOR_SHORT_EDGE = 512
  PREFERRED_SHORT_EDGE = 1024
  RESERVED_TRIGGERS = %w[tok].freeze
  DICTIONARY = "/usr/share/dict/words"

  # Replicate's published rate and its example run: 1000 steps in about two
  # minutes. The README logged fourteen minutes for the same step count, so the
  # estimate prints both and the sidecar records the seconds actually billed.
  TRAIN_USD_PER_SECOND = 0.0122
  GUIDE_SECONDS_PER_STEP = 0.12
  OBSERVED_SECONDS_PER_STEP = 0.84

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
      marker = file.read(2)
      return nil if marker.nil? || marker.bytesize < 2
      return nil unless marker.getbyte(0) == 0xFF

      code = marker.getbyte(1)
      next if code == 0xFF || (0xD0..0xD9).cover?(code)

      length = file.read(2)&.unpack1("n") or return nil
      if (0xC0..0xCF).cover?(code) && ![0xC4, 0xC8, 0xCC].include?(code)
        data = file.read(5) or return nil
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
    return nil unless status.success? && out.bytesize == 64

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

  def sha256(path) = Digest::SHA256.file(path).hexdigest

  # One JSON line per paid call, appended where the subject's output lives, so
  # what a subject has cost is a file read.
  def ledger_append(path, row)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "a") { |file| file.puts JSON.generate({ at: Time.now.utc.iso8601 }.merge(row)) }
  end

  # Sum of billed seconds already in a ledger, for a spend ceiling.
  def ledger_seconds(path, kind)
    return 0.0 unless File.file?(path)

    File.readlines(path).sum do |line|
      row = JSON.parse(line)
      row["kind"] == kind ? row["seconds"].to_f : 0.0
    rescue JSON::ParserError
      0.0
    end
  end

  # Entries of a trainer tar that would land outside the target directory.
  def unsafe_tar_entries(tar_path)
    out, status = Open3.capture2("tar", "-tf", tar_path)
    return ["tar listing failed"] unless status.success?

    out.lines.map(&:strip).select { |entry| entry.start_with?("/") || entry.split("/").include?("..") }
  end
end
