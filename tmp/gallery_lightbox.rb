# frozen_string_literal: true
# encoding: UTF-8

require "json"

WEB = "/var/www/postpro"
GENERATED = /_(v\d+_\d{14}|[a-z_]+\+[a-z_]+_v\d+_\d{14}|physics|processed|masterpiece|
             postpro|portrait|cinematic|magic_hour|blockbuster|golden_age|reversal|
             warmth|noir|anamorphic|analog_scan|cinema_scan|aged_kodachrome|nitrate|
             contact_print|diffraction|wide_angle|aged_chrome|fiber_print|expired|
             reticulated|ortho|tilt_shift_look|haunted|quality_uplift)/x

files = Dir.glob("#{WEB}/*.{jpg,JPG,jpeg,png,PNG}").map { |f| File.basename(f) }.sort
originals = files.reject { |f| f.match?(GENERATED) }
generated = files.select { |f| f.match?(GENERATED) }

groups = originals.filter_map do |orig|
  stem = File.basename(orig, File.extname(orig))
  variants = generated.select { |g| g.start_with?("#{stem}_") }.sort
  next if variants.empty?
  [orig, variants]
end

preset_label = ->(f) {
  if (m = f.match(/_([a-z_]+\+[a-z_]+)_v\d+_\d{14}/))
    m[1].tr("_+", " +")
  elsif (m = f.match(/_([a-z_]+)_v\d+_\d{14}/))
    m[1].tr("_", " ")
  else
    ""
  end
}

rows = groups.map do |orig, variants|
  items = ([orig] + variants).map do |f|
    label = f.match?(GENERATED) ? preset_label.call(f) : "original"
    %(<a href="#{f}" data-sub-html="<p>#{label}</p>"><img src="#{f}" loading="lazy" alt="#{label}"></a>)
  end.join("\n")
  "<section>\n#{items}\n</section>"
end.join("\n\n")

html = <<~HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Postpro &mdash; analog film gallery</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/lightgallery@2/css/lightgallery.min.css">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/lightgallery@2/css/lg-zoom.min.css">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/lightgallery@2/css/lg-thumbnail.min.css">
  <style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0 }
  :root { --gap: 1.5rem; --bg: #0e0e0e; --fg: #e0e0e0; --dim: #555 }
  html { background: var(--bg); color: var(--fg); font: 400 15px/1.6 "Helvetica Neue", Helvetica, Arial, sans-serif }
  body { max-width: 1400px; margin: 0 auto; padding: var(--gap) }
  h1 { font-size: .85rem; font-weight: 400; color: var(--dim); margin-bottom: 2rem; letter-spacing: .04em }
  section { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: var(--gap); margin-bottom: 3rem }
  section a { display: block; overflow: hidden; cursor: zoom-in }
  section a img { display: block; width: 100%; aspect-ratio: 4/3; object-fit: cover; transition: transform .3s cubic-bezier(.4,0,.2,1) }
  section a:hover img { transform: scale(1.04) }
  section a:first-child img { filter: brightness(.65) }
  @media (max-width: 600px) { section { grid-template-columns: 1fr 1fr } }
  </style>
  </head>
  <body>
  <h1>postpro &mdash; analog film finishing &nbsp;&middot;&nbsp; #{groups.size} originals &nbsp;&middot;&nbsp; #{generated.size} variations</h1>
  #{rows}
  <script src="https://cdn.jsdelivr.net/npm/lightgallery@2/lightgallery.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/lightgallery@2/plugins/zoom/lg-zoom.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/lightgallery@2/plugins/thumbnail/lg-thumbnail.min.js"></script>
  <script>
  document.querySelectorAll("section").forEach(el => {
    lightGallery(el, {
      plugins: [lgZoom, lgThumbnail],
      speed: 300,
      thumbnail: true,
      animateThumb: true,
      zoomFromOrigin: true,
      allowMediaOverlap: false,
      toggleThumb: true,
    });
  });
  </script>
  </body>
  </html>
HTML

index_path = "/tmp/gallery_index.html"
File.write(index_path, html)
system("doas", "cp", index_path, "#{WEB}/index.html")
system("doas", "chmod", "644", "#{WEB}/index.html")
system("doas", "chown", "www:www", "#{WEB}/index.html")
puts "gallery updated: http://brgen.no:6666/"
