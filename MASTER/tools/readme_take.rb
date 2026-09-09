#!/usr/bin/env ruby
# frozen_string_literal: true

# readme_take — the README's opening image, from the README's own words.
#
#   ruby tools/readme_take.rb              # speech, then the take
#   ruby tools/readme_take.rb --speech     # only tts.wav
#   ruby tools/readme_take.rb --record     # only loop.mp4 and loop.gif
#
# Three steps, each skippable and each resumable, because the whole thing takes
# twenty minutes and has been killed twice mid-way by the machine running out of
# memory.
#
#   1. README.md becomes speakable prose and then tts.wav, read by the voice
#      data/voice.yml names. Code blocks, the image and the HTML comment are
#      dropped: they are for a reader's eye and are noise read aloud.
#   2. The face speaks it, recorded frame by frame by RAILS/gates/probes/
#      face_loop_record.rb, in slices with a fresh browser each time. One
#      browser holding four minutes of this face grows until the machine
#      complains.
#   3. ffmpeg makes loop.mp4 at 20fps and loop.gif from three seconds of it.
#
# The gif is what GitHub renders — its sanitizer strips <video> — and it is 12
# colours at 8fps because a field of hard white dots is high-entropy: the same
# three seconds at 64 colours and 12fps is 4.5MB against 1.3MB.

require "fileutils"
require "net/http"
require "shellwords"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
REPO = File.expand_path("..", ROOT)
RAILS_DIR = File.join(REPO, "RAILS")
FACE_URL = "http://127.0.0.1:53187/"

README = File.join(ROOT, "README.md")
WAV = File.join(ROOT, "tts.wav")
MP4 = File.join(ROOT, "loop.mp4")
GIF = File.join(ROOT, "loop.gif")
WORK = File.join(Dir.tmpdir, "master_readme_take")

FPS = 20
VIEWPORT = "900x760"
CLIP = "315,160,270,370"     # the face, in CSS pixels, at that viewport
SLICE = 300
ATTEMPTS = 3
GIF_FROM = 300               # a lively three seconds, well past the opening
# 20fps of hard 1px dots is near the worst case for h264 and the recorder defaults
# to 28, which gives 23MB for four minutes. 36 gives 14MB with the dots still
# crisp; 10fps saves only a fifth of that and costs the motion, measured.
CRF = 36

# README.md, read aloud. The parenthetical asides an eye skips are kept, because
# they are the sentences; what goes is everything that is not a sentence.
SPOKEN = {
  "3D-printing" => "three-D printing",
  "~98%" => "about ninety-eight percent",
  "8 °C" => "eight degrees",
  "1.1" => "one point one",
  "1.5" => "one point five",
  "IP" => "I P",
  "MIT" => "M I T",
  "AI" => "A I",
  "OpenBSD" => "Open B S D",
}.freeze

# Paragraphs the file keeps and the take does not. The title is the image's own
# caption, the closing paragraph is a list of links, and the three under "Under
# the hood" introduce a console transcript and a Ruby snippet — read aloud they
# announce something the listener is never shown.
SILENT = [
  "Read START_HERE", "Under the hood", "Wake it with one line",
  "Every change a model wants", "Three verdicts",
].freeze

def prose
  kept = []
  fenced = false
  commented = false

  File.readlines(README, chomp: true).each do |line|
    if commented
      commented = false if line.include?("-->")
      next
    end
    if line.lstrip.start_with?("<!--")
      commented = true unless line.include?("-->")
      next
    end
    if line.lstrip.start_with?("```")
      fenced = !fenced
      next
    end
    next if fenced || line.lstrip.start_with?("<img")

    kept << line
  end

  paragraphs(kept).map { |para| speakable(para) }.reject(&:empty?)
end

def paragraphs(lines)
  out = []
  buffer = []
  lines.each do |line|
    if line.strip.empty?
      out << buffer.join(" ") unless buffer.empty?
      buffer = []
    elsif line.start_with?("#")
      out << buffer.join(" ") unless buffer.empty?
      buffer = []
      out << line.sub(/\A#+\s*/, "")
    else
      buffer << line.strip
    end
  end
  out << buffer.join(" ") unless buffer.empty?
  out.map(&:strip).reject { |para| para == "MASTER" || SILENT.any? { |start| para.start_with?(start) } }
end

def speakable(para)
  text = para.gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')   # a link is its words
             .gsub(/\*\*([^*]+)\*\*/, '\1')
             .gsub(/`([^`]+)`/, '\1')
             .gsub("—", ",")
  SPOKEN.each { |from, to| text = text.gsub(from, to) }
  text.gsub(/\s+([,.])/, '\1').gsub(/\s+/, " ").strip
end

# One synthesis per paragraph: data/tts.yml caps an utterance at 900 characters,
# and a paragraph break is the pause a listener expects anyway.
def speak!
  # The voice, its rate and its pitch come from the one file that decides how
  # MASTER sounds, so a take never disagrees with the daemon.
  policy = YAML.safe_load_file(File.join(ROOT, "data", "voice.yml"), aliases: true).fetch("tts")
  parts_dir = File.join(WORK, "speech")
  FileUtils.mkdir_p(parts_dir)

  parts = prose.each_with_index.map do |para, index|
    out = File.join(parts_dir, format("%02d.mp3", index))
    next out if File.size?(out)

    text = File.join(parts_dir, format("%02d.txt", index))
    File.write(text, para)
    ok = system({ "RBENV_VERSION" => "3.4.9" }, "rbenv", "exec", "ruby",
                File.join(ROOT, "bin", "tts-worker"), policy.fetch("neural"),
                policy.fetch("default_rate"), policy.fetch("default_pitch"), out,
                in: text, out: File::NULL, err: File::NULL)
    abort "tts-worker failed on paragraph #{index}" unless ok && File.size?(out)
    out
  end

  list = File.join(parts_dir, "parts.txt")
  File.write(list, parts.map { |part| "file '#{part}'" }.join("\n") + "\n")
  system("ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0",
         "-i", list, "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", WAV) or abort "ffmpeg concat failed"
  puts "#{parts.size} paragraphs -> #{WAV} (#{File.size(WAV) / 1_048_576} MB)"
end

def face_up?
  Net::HTTP.get_response(URI(FACE_URL)).code == "200"
rescue StandardError
  false
end

def record!
  abort "no face at #{FACE_URL} — start it with: cd MASTER/web && ruby bin/rails server -p 53187" unless face_up?

  frames = (duration_of(WAV) * FPS).floor
  (0...frames).step(SLICE) do |from|
    to = [from + SLICE, frames].min
    puts "slice #{from}...#{to}"
    ok = false
    ATTEMPTS.times do |attempt|
      ok = system({ "RBENV_VERSION" => "3.4.9" }, "rbenv", "exec", "ruby",
                  "gates/probes/face_loop_record.rb",
                  "--audio", WAV, "--out", MP4, "--fps", FPS.to_s,
                  "--viewport", VIEWPORT, "--scale", "2", "--clip", CLIP,
                  "--warmup", "60", "--timeout", "90", "--crf", CRF.to_s,
                  "--work", File.join(WORK, "frames"),
                  "--from", from.to_s, "--to", to.to_s, chdir: RAILS_DIR)
      break if ok

      # The CDP transport times out or loses the page's context now and then,
      # always transiently. A retry costs nothing: a frame on disk is never
      # recaptured.
      puts "  attempt #{attempt + 1} failed, retrying"
    end
    abort "slice #{from}...#{to} failed #{ATTEMPTS} times" unless ok
  end

  gif!
end

def duration_of(path)
  out = `ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 #{path.shellescape}`
  out.to_f
end

def gif!
  filter = "fps=8,scale=360:-1:flags=lanczos,split[a][b];" \
           "[a]palettegen=max_colors=12[p];[b][p]paletteuse=dither=none"
  system("ffmpeg", "-y", "-loglevel", "error", "-framerate", FPS.to_s,
         "-start_number", GIF_FROM.to_s, "-i", File.join(WORK, "frames", "f_%05d.jpg"),
         "-frames:v", (FPS * 3).to_s, "-vf", filter, GIF) or abort "gif failed"
  puts "#{MP4} #{File.size(MP4) / 1_048_576}MB, #{GIF} #{File.size(GIF) / 1_048_576}MB"
end

speech = ARGV.include?("--speech") || ARGV.empty?
record = ARGV.include?("--record") || ARGV.empty?

FileUtils.mkdir_p(WORK)
speak! if speech
record! if record
puts "frames kept at #{File.join(WORK, 'frames')} — delete them once the take is approved"
