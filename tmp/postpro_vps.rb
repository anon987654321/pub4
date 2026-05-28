# frozen_string_literal: true

require "open3"

VPS = "dev@46.23.89.226"
KEY = File.expand_path("~/.ssh/id_ed25519_brgen")
SSH = ["ssh", "-i", KEY, VPS]
SCP = ["scp", "-i", KEY]
REMOTE_DIR = "/home/dev/postpro"
LOCAL_DOWNLOADS = File.expand_path("~/storage/downloads")
LOCAL_POSTPRO = File.expand_path("~/pub4/DEPLOY/postpro/postpro.rb")

GENERATED_PATTERN = /_(v\d+_\d{14}|[a-z_]+\+[a-z_]+_v\d+_\d{14}|physics|processed|masterpiece|postpro|portrait|cinematic|magic_hour|blockbuster|golden_age|reversal|warmth|noir|anamorphic|analog_scan|cinema_scan|aged_kodachrome|nitrate|contact_print|diffraction|wide_angle|aged_chrome|fiber_print|expired|reticulated|ortho|tilt_shift_look|haunted|quality_uplift)/

def ssh(*args)
  cmd = SSH + args
  out, err, status = Open3.capture3(*cmd)
  abort "SSH failed: #{err}" unless status.success?
  out.chomp
end

def scp_up(local, remote)
  out, err, status = Open3.capture3(*SCP, local, "#{VPS}:#{remote}")
  abort "SCP failed #{local}: #{err}" unless status.success?
  puts "  -> #{File.basename(local)}"
end

originals = Dir.glob("#{LOCAL_DOWNLOADS}/*.{jpg,JPG,jpeg,png}", File::FNM_CASEFOLD)
           .reject { |f| File.basename(f).match?(GENERATED_PATTERN) }
           .reject { |f| File.basename(f).end_with?(".log") }

abort "No originals found in #{LOCAL_DOWNLOADS}" if originals.empty?
puts "#{originals.size} originals found."

puts "\nInstalling gems on VPS..."
ssh("gem34", "install", "ruby-vips", "tty-prompt", "--no-document")
puts "Gems installed."

puts "\nCreating remote dir #{REMOTE_DIR}..."
ssh("mkdir", "-p", REMOTE_DIR)

puts "\nUploading postpro.rb..."
scp_up(LOCAL_POSTPRO, REMOTE_DIR)

puts "\nUploading originals..."
originals.each { |f| scp_up(f, REMOTE_DIR) }

puts "\nRunning postpro --random on VPS..."
result = ssh("ruby34", "#{REMOTE_DIR}/postpro.rb", "--random", REMOTE_DIR, "--count", "4")
puts result

puts "\nOutputs:"
outputs = ssh("ls", "#{REMOTE_DIR}").split("\n")
           .select { |f| f.match?(GENERATED_PATTERN) }
puts outputs.map { |f| "  #{f}" }.join("\n")
puts "\nDone. #{outputs.size} files generated at #{VPS}:#{REMOTE_DIR}"

puts "\nSyncing to web..."
gallery_script = File.read(File.expand_path("~/pub4/tmp/gallery_lightbox.rb"))
scp_up(File.expand_path("~/pub4/tmp/gallery_lightbox.rb"), "/tmp/gallery_lightbox.rb")
ssh("ruby34", "/tmp/gallery_lightbox.rb")
puts "Gallery: http://brgen.no:6666/"
