# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"

# Fix 1: Remove duplicate banner from Master.boot (CLI.run already prints it)
content = File.read(File.join(BASE, "lib/master.rb"), encoding: "utf-8")
lines = content.lines
idx = lines.index { |l| l.include?("r.banner(container[:agent].model)") }
if idx
  lines.delete_at(idx)
  File.write(File.join(BASE, "lib/master.rb"), lines.join)
  puts "fixed: removed duplicate banner from Master.boot"
else
  puts "banner line not found"
end

# Fix 2: Gracefully handle Ferrum errors in web_search tool
# Find the web_search tool
Dir.glob(File.join(BASE, "lib/master/tools/*.rb")).each do |f|
  content = File.read(f, encoding: "utf-8")
  if content.include?("web_search") || content.include?("WebSearch")
    puts "web_search tool: #{f}"
    content.lines.each_with_index { |l, i| puts "  #{i+1}: #{l}" if l.include?("value!") || l.include?("ferrum") || l.include?("Ferrum") }
  end
end

# Check bridges
Dir.glob(File.join(BASE, "lib/master/bridges/*.rb")).each do |f|
  content = File.read(f, encoding: "utf-8")
  puts "bridge: #{f.sub(BASE + '/', '')}"
end
