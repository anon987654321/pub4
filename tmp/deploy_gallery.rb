# frozen_string_literal: true
# encoding: UTF-8

require "fileutils"

SRC = "/home/dev/postpro"
WEB = "/var/www/postpro"
GENERATED = /_(v\d+_\d{14}|[a-z_]+\+[a-z_]+_v\d+_\d{14}|physics|processed|masterpiece|
             postpro|portrait|cinematic|magic_hour|blockbuster|golden_age|reversal|
             warmth|noir|anamorphic|analog_scan|cinema_scan|aged_kodachrome|nitrate|
             contact_print|diffraction|wide_angle|aged_chrome|fiber_print|expired|
             reticulated|ortho|tilt_shift_look|haunted|quality_uplift)/x

def sh(*cmd)
  system(*cmd) || abort("failed: #{cmd.join(" ")}")
end

# 1. Web dir + copy images

sh("doas", "mkdir", "-p", WEB)

Dir.glob("#{SRC}/*.{jpg,JPG,jpeg,png,PNG}")
  .reject { |f| File.basename(f).start_with?("FB_") }
  .each   { |f| sh("doas", "cp", f, "#{WEB}/#{File.basename(f)}") }
sh("doas", "chmod", "755", WEB)
sh("doas", "find", WEB, "-type", "f", "-exec", "chmod", "644", "{}", "+")
sh("doas", "chown", "-R", "www:www", WEB)

puts "images copied to #{WEB}"

# 2. Gallery HTML

files = Dir.glob("#{WEB}/*.{jpg,JPG,jpeg,png,PNG}").map { |f| File.basename(f) }.sort
originals = files.reject { |f| f.match?(GENERATED) }
generated = files.select { |f| f.match?(GENERATED) }

groups = originals.filter_map do |orig|
  stem = File.basename(orig, File.extname(orig))
  variants = generated.select { |g| g.start_with?("#{stem}_") }.sort
  next if variants.empty?
  [orig, variants]
end

preset_label = lambda do |filename|
  m = filename.match(/_([a-z_]+)_v\d+_\d{14}/)
  m ? m[1].gsub("_", " ") : ""
end

rows = groups.map do |orig, variants|
  orig_tag = %(<figure class="orig"><img src="#{orig}" loading="lazy" alt="original"><figcaption>original</figcaption></figure>)
  var_tags = variants.map do |v|
    label = preset_label.call(v)
    %(<figure><img src="#{v}" loading="lazy" alt="#{label}"><figcaption>#{label}</figcaption></figure>)
  end.join("\n")
  %(<section>\n#{orig_tag}\n#{var_tags}\n</section>)
end.join("\n\n")

html = <<~HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Postpro &mdash; analog film gallery</title>
  <style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0 }
  :root { --gap: 1.5rem; --bg: #0e0e0e; --fg: #e0e0e0; --dim: #666 }
  html { background: var(--bg); color: var(--fg); font: 400 15px/1.6 "Helvetica Neue", Helvetica, Arial, sans-serif }
  body { max-width: 1400px; margin: 0 auto; padding: var(--gap) }
  h1 { font-size: 1rem; font-weight: 400; color: var(--dim); margin-bottom: 2rem }
  section { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: var(--gap); margin-bottom: 3rem }
  figure { position: relative }
  img { display: block; width: 100%; aspect-ratio: 4/3; object-fit: cover; filter: brightness(0.95) }
  figcaption { position: absolute; bottom: 0; left: 0; right: 0; padding: .4rem .6rem; background: rgba(0,0,0,.55); font-size: .72rem; letter-spacing: .06em; text-transform: lowercase; color: var(--fg) }
  figure.orig img { filter: brightness(0.7) }
  figure.orig figcaption { color: var(--dim) }
  @media (max-width: 600px) { section { grid-template-columns: 1fr 1fr } }
  </style>
  </head>
  <body>
  <h1>postpro &mdash; analog film finishing &middot; #{groups.size} originals &middot; #{generated.size} variations</h1>
  #{rows}
  </body>
  </html>
HTML

index_path = "/tmp/gallery_index.html"
File.write(index_path, html)
sh("doas", "cp", index_path, "#{WEB}/index.html")
sh("doas", "chmod", "644", "#{WEB}/index.html")
sh("doas", "chown", "www:www", "#{WEB}/index.html")
puts "gallery HTML written"

# 3. httpd.conf &mdash; append port 666 server block

httpd_conf = "/etc/httpd.conf"
current = File.read(httpd_conf)

block = <<~CONF

  server "brgen.no" {
    listen on * port 666
    root "/postpro"
  }
CONF

unless current.include?("port 666")
  File.write("/tmp/httpd_append.conf", current + block)
  sh("doas", "cp", "/tmp/httpd_append.conf", httpd_conf)
  puts "httpd.conf updated"
else
  puts "httpd.conf already has port 666 block"
end

# 4. pf.conf &mdash; add port 666 rule

pf_conf = "/etc/pf.conf"
pf_current = IO.popen(["doas", "cat", pf_conf], &:read)
pf_rule = "pass in on vio0 inet proto tcp from any to 46.23.89.226 port = 666 flags S/SA"

unless pf_current.include?("port = 666")
  patched = pf_current.sub(
    /^(pass in on vio0 inet proto tcp from any to 46\.23\.89\.226 port = 443.*)/,
    "\\1\n#{pf_rule}"
  )
  File.write("/tmp/pf_patched.conf", patched)
  sh("doas", "cp", "/tmp/pf_patched.conf", pf_conf)
  puts "pf.conf updated"
else
  puts "pf.conf already has port 666"
end

# 5. Reload pf and httpd

sh("doas", "pfctl", "-f", pf_conf)
puts "pf reloaded"
sh("doas", "rcctl", "enable", "httpd")
sh("doas", "rcctl", "restart", "httpd")
puts "httpd restarted"

puts "\nhttp://brgen.no:6666/"
