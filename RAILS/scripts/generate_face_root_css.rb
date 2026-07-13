#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../design_tokens"

# __dir__ is <repo>/RAILS/scripts, so the repo root is two levels up, not
# three — "../../.." escaped the checkout entirely and crashed on a
# nonexistent <parent>/MASTER/web/public/face.css.
ROOT = File.expand_path("../..", __dir__)
FACE_CSS = File.join(ROOT, "MASTER", "web", "public", "face.css")

face_changed = DesignTokens.sync_face_css!(FACE_CSS)
chrome_changed = DesignTokens.sync_chrome_css!(FACE_CSS)
if face_changed || chrome_changed
  parts = []
  parts << "face-root" if face_changed
  parts << "x-chrome" if chrome_changed
  puts "updated #{FACE_CSS} (#{parts.join(', ')})"
else
  puts "face.css face-root and x-chrome already in sync"
end