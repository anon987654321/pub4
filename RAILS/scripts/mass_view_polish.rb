#!/usr/bin/env ruby
# frozen_string_literal: true

views = Dir[File.expand_path("../brgen/app/views/**/*.html.erb", __dir__)]
changed = 0
views.each do |path|
  src = File.read(path)
  orig = src.dup
  src.gsub!(/<(div|header)( class="page-header")(?![^>]*role=)/, '<\\1\\2 role="banner"')
  src.gsub!(/<div class="empty"(?!.*empty-state)/, '<div class="empty empty-state"')
  src.gsub!(/<section class="empty"(?!.*empty-state)/, '<section class="empty empty-state"')
  src.gsub!(/<p class="empty"(?!.*empty-state)/, '<p class="empty empty-state"')
  next if src == orig

  File.write(path, src)
  changed += 1
end
puts "updated #{changed} views"