#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "design_tokens"

# __dir__ is <repo>/RAILS/tools, so the repo root is two levels up, not
# three — "../../.." escaped the checkout entirely and crashed on a
# nonexistent <parent>/MASTER/web/public/face.css.
ROOT = File.expand_path("../..", __dir__)
FACE_CSS = File.join(ROOT, "MASTER", "web", "public", "face.css")

changed = DesignTokens.sync_face_css!(FACE_CSS)
puts changed ? "updated #{FACE_CSS}" : "face.css :root already in sync"
