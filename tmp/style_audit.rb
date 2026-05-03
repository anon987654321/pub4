files = Dir["lib/**/*.rb"]
text = files.map{|f| [f, File.read(f, encoding: "UTF-8")]}

n = text.sum{|_,c| c.scan("respond_to?(:ok?)").length}
puts "respond_to?(:ok?) count: #{n}"

n2 = text.sum{|_,c| c.scan("ctx[:args].to_s.strip").length}
puts "ctx[:args].to_s.strip: #{n2} times"

puts "\n=== .freeze on string literals in frozen_string_literal files ==="
text.each{|f,c|
  next unless c.start_with?("# frozen_string_literal: true")
  c.scan(/[a-z_\/][a-z0-9_\/]*\.freeze\b|"[^"]*"\.freeze\b/).each{|m| puts "#{f}: #{m}"}
}

puts "\n=== .compact.first vs .find ==="
text.each{|f,c|
  c.scan(/.{0,40}\.compact\.first.{0,40}/).each{|m| puts "#{f}: #{m.strip}"}
}

puts "\n=== flatten.map vs flat_map ==="
text.each{|f,c|
  c.scan(/.{0,30}\.flatten\.map.{0,40}/).each{|m| puts "#{f}: #{m.strip}"}
}

puts "\n=== Array() wrapping already-array returns ==="
text.each{|f,c|
  c.scan(/Array\([^)]{1,50}\)/).each{|m| puts "#{f}: #{m}"}
}

puts "\n=== rescue => e ... raise same e (pointless rescue) ==="
text.each{|f,c|
  c.scan(/.{0,20}rescue.{0,30}\n.{0,30}raise.{0,30}/).each{|m| puts "#{f}: #{m.strip[0,80]}"}
}

puts "\n=== .to_s[0, N] truncation pattern (could be .then) ==="
text.each{|f,c|
  c.scan(/.{0,30}\.to_s\[0, \d+\].{0,30}/).each{|m| puts "#{f}: #{m.strip}"}
}
