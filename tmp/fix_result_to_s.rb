# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"
content = File.read(File.join(BASE, "lib/master/result.rb"), encoding: "utf-8")
lines = content.lines

# Find the inspect line in Ok class (around line 33)
idx = lines.index { |l| l.include?('def inspect') && l.include?('Ok(') }
if idx
  indent = lines[idx][/^\s*/]
  lines.insert(idx, "#{indent}def to_s                    = @value.to_s\n")
  File.write(File.join(BASE, "lib/master/result.rb"), lines.join)
  puts "fixed: added to_s to Result::Ok at line #{idx + 1}"
else
  puts "could not find Ok#inspect line"
end
