# frozen_string_literal: true

# Fix single-quoted requires to double quotes in 3 files

files = %w[
  /home/dev/pub4/MASTER/lib/master/axioms.rb
  /home/dev/pub4/MASTER/lib/master/config.rb
  /home/dev/pub4/MASTER/lib/master/event_bus.rb
]

files.each do |path|
  next unless File.exist?(path)
  src = File.read(path, encoding: "UTF-8")
  updated = src.gsub(/require\s+'([^']+)'/) { "require \"#{$1}\"" }
  if src != updated
    File.write(path, updated)
    puts "fixed: #{path}"
  end
end
