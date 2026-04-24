# encoding: utf-8
# frozen_string_literal: true
BASE = "/home/dev/pub4/MASTER"
content = File.read(File.join(BASE, "lib/master/stages/prune.rb"), encoding: "utf-8")
# Replace the problematic line using Regexp.new instead of literal
content.sub!(
  '      HEADER_RE     = /^#{1,6}\s+/                    # ## Header',
  '      HEADER_RE     = Regexp.new(\'^\#{1,6}\s+\')       # ## Header'
)
File.write(File.join(BASE, "lib/master/stages/prune.rb"), content)
puts "fixed"
