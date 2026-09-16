#!/usr/bin/env ruby
# frozen_string_literal: true

# shell_loop_record — record a terminal session as a video, frame by frame.
#
#   ruby RAILS/gates/probes/shell_loop_record.rb --out ../MASTER/loop2.mp4 \
#        --audio ../STUDIO/dilla/demo.wav --fps 20
#
# The companion to face_loop_record, which records the face; this one records a
# shell. Same three ideas, for the same reason: the clock is ours, the crop is
# Chrome's, and the audio is muxed rather than played.
#
# Why Chrome and not a terminal recorder. asciinema and script(1) capture a byte
# stream with timings, and turning that into a video needs a renderer anyway —
# one that reads ANSI, picks a font, and rasterises. Chrome already is that
# renderer, it has the fonts, and it can be told exactly which rectangle to
# photograph. The cost is that the terminal is a fiction: these lines are real
# output, captured from the real command, but the typing is animated rather than
# recorded keystroke by keystroke.
#
# The content is not invented. The banner is what Master::CLI::BootBanner prints
# with MASTER_BOOT_STATUS=1, read from the tree at record time rather than pasted
# here, so a change to the banner changes the film.

require "json"
require "optparse"

GATES = File.expand_path("..", __dir__)
$LOAD_PATH.unshift File.join(GATES, "support")
require "cdp_session"

options = {
  out: File.expand_path("../../MASTER/loop2.mp4", GATES),
  audio: File.expand_path("../../STUDIO/dilla/demo.wav", GATES),
  fps: 20,
  # Cropped to the boot message and the prompt, nothing else — the frame is the
  # content, so the type reads large without scaling the video up afterwards.
  width: 700,
  height: 420,
}

OptionParser.new do |opts|
  opts.on("--out PATH") { |v| options[:out] = File.expand_path(v) }
  opts.on("--audio PATH") { |v| options[:audio] = File.expand_path(v) }
  opts.on("--fps N", Integer) { |v| options[:fps] = v }
  opts.on("--width N", Integer) { |v| options[:width] = v }
  opts.on("--height N", Integer) { |v| options[:height] = v }
end.parse!

# The banner, from the tree rather than from memory.
def boot_lines
  master = File.expand_path("../../MASTER", GATES)
  script = <<~RUBY
    $LOAD_PATH.unshift File.expand_path("lib")
    require "master"
    require "cli/boot_banner"
    Master::CLI::BootBanner.print(io: $stdout)
  RUBY
  out = IO.popen({ "MASTER_BOOT_STATUS" => "1" }, ["ruby", "-e", script], chdir: master, err: File::NULL, &:read)
  lines = out.lines.map(&:chomp).reject(&:empty?)
  raise "shell_loop_record: BootBanner printed nothing — refusing to film a blank" if lines.empty?

  lines
end

BANNER = boot_lines
PROMPT_HOST = "dev@brgen.no"

# One row per rendered line, tagged so the stylesheet can colour it. Nothing here
# parses ANSI: the banner's shape is `master: key=value`, which is richer to
# colour from structure than from escape codes it does not emit.
def rows
  [
    { kind: "cmd", text: "ssh #{PROMPT_HOST}" },
    { kind: "motd", text: "OpenBSD 7.8 (GENERIC.MP) #54: Wed Sep 10 04:12:33 CEST 2026" },
    { kind: "cmd2", text: "cd pub4/MASTER && bundle exec ruby bin/cli" },
    *BANNER.map { |line| { kind: "boot", text: line } },
    { kind: "ready", text: "" },
  ]
end

PAGE = <<~'HTML'
  <!doctype html><meta charset="utf-8">
  <style>
    :root { color-scheme: dark; }
    html, body { margin: 0; background: #0d0d11; height: 100%; }
    #term {
      box-sizing: border-box; height: 100%; padding: 18px 22px;
      font: 17px/1.62 "JetBrains Mono", "SF Mono", ui-monospace, Menlo, monospace;
      color: #d8d6e0; white-space: pre; letter-spacing: 0.01em;
    }
    .row { display: block; }
    .sigil { color: #6b7fd7; }
    .host  { color: #12b6c4; }
    .cmd   { color: #efefef; }
    .flag  { color: #e0a33b; }
    .motd  { color: #6f6f78; }
    .key   { color: #12b6c4; }
    .val   { color: #98d47a; }
    .lit   { color: #dc635c; }
    .caret { background: #d8d6e0; color: #0d0d11; }
  </style>
  <div id="term"></div>
HTML

# Colour by structure. `master: loop=none owner=none` becomes a label, then
# key/value pairs — the same reading a person does, made visible.
COLOUR = <<~'JS'
  window.paint = (kind, text) => {
    const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
    if (kind === 'cmd' || kind === 'cmd2') {
      const m = text.match(/^(\S+)\s+(.*)$/);
      const head = m ? m[1] : text, rest = m ? m[2] : '';
      return '<span class="sigil">$ </span><span class="cmd">' + esc(head) + '</span> ' +
             '<span class="host">' + esc(rest) + '</span>';
    }
    if (kind === 'motd') return '<span class="motd">' + esc(text) + '</span>';
    if (kind === 'boot') {
      const m = text.match(/^(\w+):\s*(.*)$/);
      if (!m) return '<span class="cmd">' + esc(text) + '</span>';
      const body = esc(m[2]).replace(/([\w.]+)=([^\s]+)/g,
        '<span class="key">$1</span>=<span class="val">$2</span>');
      return '<span class="lit">' + esc(m[1]) + ':</span> ' + body;
    }
    return '';
  };
JS

rows_json = JSON.generate(rows)
fps = options[:fps]
frame_dir = File.join(Dir.tmpdir, "shell_loop_#{Process.pid}")
require "tmpdir"
require "fileutils"
FileUtils.mkdir_p(frame_dir)

# Frame budget: type each command a character at a time, then reveal the banner a
# line at a time, then hold on the prompt so the loop has somewhere to rest.
typed = rows.select { |r| r[:kind].start_with?("cmd") }.sum { |r| r[:text].length }
total = typed + (rows.size * 6) + (fps * 2)

puts "shell_loop_record: #{rows.size} rows, ~#{total} frames at #{fps}fps"

count = 0
Deploy::CdpSession.open do |cdp|
  cdp.viewport(options[:width], options[:height])
  # A file, not a data: URL — every colour in the stylesheet starts with #, which
  # a data: URL reads as the start of its fragment and truncates.
  page = File.join(frame_dir, "term.html")
  File.write(page, PAGE)
  cdp.navigate("file://#{page}", settle: 0.4)
  cdp.evaluate(COLOUR)
  cdp.evaluate("window.ROWS = #{rows_json}; window.step = 0;")

  # One evaluate per frame, each advancing the fiction by one step. The page keeps
  # the state; this only says "advance", so a dropped frame is a slower film and
  # not a different one.
  advance = <<~'JS'
    (() => {
      const term = document.getElementById('term');
      const rows = window.ROWS;
      let s = window.step++;
      let html = '';
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const typing = r.kind.startsWith('cmd');
        if (typing) {
          const shown = Math.max(0, Math.min(r.text.length, s));
          if (shown <= 0) break;
          html += '<span class="row">' + window.paint(r.kind, r.text.slice(0, shown)) +
                  (shown < r.text.length ? '<span class="caret"> </span>' : '') + '</span>';
          s -= r.text.length + 4;
          if (s < 0) break;
        } else if (r.kind === 'ready') {
          html += '<span class="row"><span class="sigil">› </span><span class="caret"> </span></span>';
        } else {
          if (s <= 0) break;
          html += '<span class="row">' + window.paint(r.kind, r.text) + '</span>';
          s -= 5;
        }
      }
      term.innerHTML = html;
      return window.step;
    })()
  JS

  total.times do |i|
    cdp.evaluate(advance)
    cdp.screenshot(File.join(frame_dir, format("f%05d.png", i)))
    count += 1
  end
end

puts "shell_loop_record: #{count} frames in #{frame_dir}"

have_audio = File.file?(options[:audio])
warn "shell_loop_record: no audio at #{options[:audio]} — writing silent video" unless have_audio

video_args = ["ffmpeg", "-y", "-framerate", fps.to_s, "-i", File.join(frame_dir, "f%05d.png")]
video_args += ["-i", options[:audio], "-shortest", "-c:a", "aac", "-b:a", "192k"] if have_audio
video_args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", options[:out]]

system(*video_args, out: File::NULL, err: File::NULL) or abort "shell_loop_record: ffmpeg failed"
puts "shell_loop_record: wrote #{options[:out]} (#{(File.size(options[:out]) / 1024.0 / 1024).round(2)} MB)"

gif = options[:out].sub(/\.mp4\z/, ".gif")
palette = File.join(frame_dir, "palette.png")
system("ffmpeg", "-y", "-i", options[:out], "-vf", "fps=#{fps},scale=720:-1:flags=lanczos,palettegen",
       palette, out: File::NULL, err: File::NULL)
system("ffmpeg", "-y", "-i", options[:out], "-i", palette, "-lavfi",
       "fps=#{fps},scale=720:-1:flags=lanczos [x]; [x][1:v] paletteuse", gif,
       out: File::NULL, err: File::NULL)
puts "shell_loop_record: wrote #{gif} (#{(File.size(gif) / 1024.0 / 1024).round(2)} MB)" if File.file?(gif)

FileUtils.rm_rf(frame_dir)
