#!/usr/bin/env ruby
# extract heredocs of form `cat > PATH <<'TAG'` ... `TAG`
# usage: ruby extract_heredocs.rb <input.sh> <out_root>
require "fileutils"

input, root = ARGV
abort "usage: extract_heredocs.rb <input.sh> <out_root>" unless input && root

src = File.read(input)
written = 0
i = 0
lines = src.lines

while i < lines.size
  line = lines[i]
  if line =~ /\Acat\s*>+\s*([^\s<]+)\s*<<\s*['"]?([A-Z_]+)['"]?\s*\z/
    path, tag = $1, $2
    body = []
    j = i + 1
    while j < lines.size && lines[j].chomp != tag
      body << lines[j]
      j += 1
    end
    out = File.expand_path(path, root)
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, body.join)
    puts "wrote #{out}"
    written += 1
    i = j + 1
  else
    i += 1
  end
end

puts "extracted #{written} files"
