#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../design_tokens"

ROOT = File.expand_path("../../..", __dir__)
FACE_CSS = File.join(ROOT, "MASTER", "web", "public", "face.css")

changed = DesignTokens.sync_face_css!(FACE_CSS)
puts changed ? "updated #{FACE_CSS}" : "face.css :root already in sync"