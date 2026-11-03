# frozen_string_literal: true

# The contact sheet is on by default: a family of ten is judged side by side,
# not by opening ten files. POSTPRO_CONTACT=0 leaves it out.
def contact_sheet? = ENV.fetch("POSTPRO_CONTACT", "1") != "0"

# The takes of a source's current family, in draw order, read back from their
# sidecars rather than remembered, so the sheet shows what is on disk.
def family_takes(file)
  input = File.expand_path(file)
  sidecars = Dir.glob(File.join(Postpro::Constitution.output_dir_for(input), "postpro_*.json"))
  sidecars.filter_map { |sidecar| family_take(sidecar, input) }.sort_by { |entry| [entry[:take], entry[:path]] }
end

# One sidecar read as a take of `input`, or nil when it belongs to another
# source, is not a chain, has lost its picture, or cannot be read.
def family_take(sidecar, input)
  data = JSON.parse(File.read(sidecar, encoding: "UTF-8"))
  media = sidecar.delete_suffix(".json")
  return unless data["schema"] == "postpro.chain.v1" && data["input"] == input && File.file?(media)

  { take: data["take"].to_i, look: (data["look"] || data["lane"]).to_s, path: media }
rescue JSON::ParserError, SystemCallError => e
  $logger.debug "contact sheet skips #{File.basename(sidecar)}: #{e.message}"
  nil
end

CONTACT_TILE = [480, 720].freeze
CONTACT_ACROSS = 5
CONTACT_BACKGROUND = [17, 17, 17].freeze

# One picture of the whole family: every take tiled in draw order with its
# number and look beneath it, written beside the source like every render and
# carrying a sidecar, so the next run of that source retires it with the rest.
def write_contact_sheet(file)
  takes = family_takes(file)
  return if takes.size < 2

  output = contact_sheet_path(file)
  contact_sheet_image(takes).write_to_file(output, Q: 90)
  write_contact_sidecar(file, output:, takes:)
  $cli_logger.info "contact sheet: #{takes.size} takes in #{File.basename(output)}"

  output
rescue StandardError => e
  # The takes are the work; a sheet that cannot be drawn costs only itself.
  $logger.error "contact sheet #{File.basename(file)}: #{e.message}"
  $cli_logger.error "contact sheet failed: #{e.message}"
  nil
end

def contact_sheet_path(file)
  safe_stem = File.basename(file, File.extname(file)).gsub(/[^0-9A-Za-z_-]+/, "_")
  output = File.join(Postpro::Constitution.output_dir_for(file), "postpro_#{safe_stem}_contact.jpg")
  output = Postpro::Constitution.available_output_path(output)
  Postpro::Constitution.verify_output!(input_path: file, output_path: output)
  output
end

def contact_sheet_image(takes)
  cells = takes.map { |entry| contact_cell(entry) }
  Vips::Image.arrayjoin(cells, across: [CONTACT_ACROSS, cells.size].min, shim: 6,
                               background: CONTACT_BACKGROUND, valign: :low)
end

# A take's tile with its caption strip beneath it.
def contact_cell(entry)
  tile = rgb_bands(Vips::Image.thumbnail(entry[:path], CONTACT_TILE.first, height: CONTACT_TILE.last))
  caption = format("%02d  %s", entry[:take], entry[:look].tr("_", " "))
  tile.join(contact_label(caption, tile.width), :vertical, expand: true, background: CONTACT_BACKGROUND)
end

def write_contact_sidecar(file, output:, takes:)
  listed = takes.map { |entry| { take: entry[:take], look: entry[:look], file: File.basename(entry[:path]) } }

  write_sidecar(output, {
    schema: "postpro.contact.v1",
    generated_at: Time.now.utc.iso8601,
    input: File.expand_path(file),
    output: File.expand_path(output),
    seed: $postpro_seed,
    takes: listed,
  })
end

# A caption strip as wide as its tile. libvips draws text through Pango; a build
# without it still gets a sheet, captionless, rather than no sheet.
def contact_label(caption, width)
  text = Vips::Image.text(caption, dpi: 96, font: "sans 14")
  mask = text.embed(10, 8, width, text.height + 16)
  mask.ifthenelse([230, 230, 230], CONTACT_BACKGROUND, blend: true)
rescue Vips::Error
  (Vips::Image.black(width, 1) + CONTACT_BACKGROUND).cast(:uchar)
end
