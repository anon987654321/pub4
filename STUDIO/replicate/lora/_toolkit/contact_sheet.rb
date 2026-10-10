#!/usr/bin/env ruby
# frozen_string_literal: true

# Lay a directory of frames out as one sheet, the way a roll comes back.
#
# Twelve tabs is not a contact sheet. The point of the format is that the eye
# compares neighbours without moving between windows — which is the only way to
# see that a face has drifted between two lighting setups, because drift is a
# difference and a difference needs two things side by side.
#
# The dataset sheet was built ad hoc and thrown away, so it got built twice.
# This is that, kept.
#
#   ruby _toolkit/contact_sheet.rb ~/Downloads --out ~/Downloads/sheet.jpg
#   ruby _toolkit/contact_sheet.rb ~/Downloads --match '000001000' --cols 4
#   ruby _toolkit/contact_sheet.rb <dir> --label     # filename under each frame

require "optparse"
require "pathname"

begin
  require "vips"
rescue LoadError
  abort "warn: ruby-vips missing. `gem install ruby-vips` (libvips itself: `brew install vips`)"
end

IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze

options = { cols: nil, cell: 512, gap: 12, match: nil, label: false, out: nil, bg: 18 }
OptionParser.new do |parser|
  parser.banner = "usage: contact_sheet.rb <dir> [options]"
  parser.on("--out PATH", "output jpg (default <dir>/contact_sheet.jpg)") { |v| options[:out] = v }
  parser.on("--cols N", Integer, "columns (default: near-square)") { |v| options[:cols] = v }
  parser.on("--cell N", Integer, "cell size in px (default 512)") { |v| options[:cell] = v }
  parser.on("--gap N", Integer, "gutter in px (default 12)") { |v| options[:gap] = v }
  parser.on("--match STR", "only files whose name contains STR") { |v| options[:match] = v }
  parser.on("--label", "print the filename under each frame") { options[:label] = true }
end.parse!

dir = Pathname.new(ARGV.fetch(0) { abort "warn: usage: contact_sheet.rb <dir> [options]" }).expand_path
abort "warn: not a directory: #{dir}" unless dir.directory?

# Sorted by name, because ai-toolkit's sample filenames lead with a timestamp and
# end with the prompt index — so name order is prompt order, which is the order
# the shoots were written in. Shuffling that loses the sequence.
frames = dir.children.select { |p| p.file? && IMAGE_EXT.include?(p.extname.downcase) }
             .reject { |p| p.basename.to_s.start_with?("contact_sheet") }
frames = frames.select { |p| p.basename.to_s.include?(options[:match]) } if options[:match]
frames = frames.sort_by { |p| p.basename.to_s }
abort "warn: no images in #{dir}#{options[:match] && " matching #{options[:match]}"}" if frames.empty?

cols = options[:cols] || Math.sqrt(frames.length).ceil
rows = (frames.length / cols.to_f).ceil
cell = options[:cell]
gap = options[:gap]
label_h = options[:label] ? 22 : 0

# thumbnail_image, not resize: it honours EXIF orientation. A phone photo written
# with orientation=6 is stored landscape and displayed portrait, and resizing the
# stored pixels lays the whole sheet out sideways. That cost a full rebuild once.
def fit(path, cell)
  image = Vips::Image.thumbnail(path.to_s, cell, height: cell, size: :down)
  image = image.colourspace("srgb") if image.bands < 3
  image = image[0..2] if image.bands > 3 # drop alpha; the sheet is opaque
  image
end

sheet = Vips::Image.black(cols * cell + (cols + 1) * gap,
                          rows * (cell + label_h) + (rows + 1) * gap)
                   .add(options[:bg]).cast("uchar").bandjoin([options[:bg], options[:bg]])

frames.each_with_index do |path, i|
  frame = fit(path, cell)
  x = gap + (i % cols) * (cell + gap) + ((cell - frame.width) / 2)
  y = gap + (i / cols) * (cell + label_h + gap) + ((cell - frame.height) / 2)
  sheet = sheet.insert(frame, x, y)

  next unless options[:label]

  text = Vips::Image.text(path.basename.to_s, width: cell, dpi: 62)
  tinted = text.ifthenelse([210, 210, 210], [options[:bg]] * 3, blend: true)
  sheet = sheet.insert(tinted, gap + (i % cols) * (cell + gap),
                       gap + (i / cols) * (cell + label_h + gap) + cell + 4)
end

out = options[:out] ? Pathname.new(options[:out]).expand_path : dir.join("contact_sheet.jpg")
sheet.write_to_file(out.to_s, Q: 92, strip: true)
puts "ok: #{frames.length} frame(s), #{cols}x#{rows} -> #{out}"
puts "ok: #{sheet.width}x#{sheet.height}, #{(out.size / 1024.0).round} KB"
