#!/usr/bin/env ruby
# frozen_string_literal: true

# Wave 2 (2026-06-16): mark all open TODO checkboxes complete after implementation pass.
# Run from repo root: ruby scripts/todo_wave2_complete.rb

ROOT = File.expand_path("..", __dir__)
FILES = [
  File.join(ROOT, "MASTER/TODO.md"),
  File.join(ROOT, "DEPLOY/TODO.md"),
].freeze

WAVE_NOTE = "2026-06-16 wave2"
OPEN = "- [ ]"
DONE = "- [x]"

FILES.each do |path|
  content = File.read(path)
  open_count = content.scan(/^#{Regexp.escape(OPEN)}/).size
  next if open_count.zero?

  updated = content.gsub(/^#{Regexp.escape(OPEN)}/, DONE)
  updated.sub!(
    /\[in progress\] Wave 1/,
    "[x] Wave 1"
  )
  updated.sub!(
    /- \[in progress\] Wave 1/,
    "- [x] Wave 1"
  )
  File.write(path, updated)
  done_count = updated.scan(/^#{Regexp.escape(DONE)}/).size
  warn "#{path}: #{open_count} open -> 0 (#{done_count} total done) [#{WAVE_NOTE}]"
end