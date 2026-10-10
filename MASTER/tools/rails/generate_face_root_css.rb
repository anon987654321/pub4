#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../design_tokens"

# __dir__ is <repo>/MASTER/tools/rails, so the repo root is three levels up —
# "../../.." reaches the checkout root where RAILS/master_web/public/face.css lives. This is a
# nonexistent <parent>/RAILS/master_web/public/face.css.
ROOT = File.expand_path("../../../", __dir__)
FACE_CSS = File.join(ROOT, "RAILS", "master_web", "public", "face.css")

changed = DesignTokens.sync_face_css!(FACE_CSS)
puts changed ? "updated #{FACE_CSS}" : "face.css :root already in sync"
