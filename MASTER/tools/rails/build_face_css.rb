#!/usr/bin/env ruby
# frozen_string_literal: true

# Assemble MASTER's browser face from ordered, editable CSS sources. The public
# face.css remains the single file consumers load; the :root blocks stay owned
# by MASTER/data/tokens.yml through DesignTokens. The brgen family's dark tokens
# go in first and the face's own :root after them, so face values that read
# var(--text), var(--surface) or var(--font) resolve to brgen's, and the face's
# deliberate differences (flat radii, the grey signal) win by order.
require "fileutils"
require_relative "../design_tokens"

module MasterFaceStylesheet
  ROOT = File.expand_path("../../..", __dir__)
  SOURCE_DIR = File.join(ROOT, "RAILS", "master", "styles", "face")
  OUTPUT = File.join(ROOT, "RAILS", "master", "public", "face.css")
  PARTS = %w[
    00_base.css
    10_foundation.css
    20_chrome.css
    30_conversation.css
    40_accessibility_motion.css
    50_ascii_face.css
    60_session_chrome.css
  ].freeze

  module_function

  def render
    missing = PARTS.map { |name| File.join(SOURCE_DIR, name) }.reject { |path| File.file?(path) }
    raise "face_css: missing source modules: #{missing.join(', ')}" unless missing.empty?

    base = File.read(File.join(SOURCE_DIR, PARTS.first), encoding: "UTF-8")
    remaining = PARTS.drop(1).map do |name|
      File.read(File.join(SOURCE_DIR, name), encoding: "UTF-8")
    end.join

    "#{base}#{DesignTokens.family_tokens_block}\n#{DesignTokens.face_root_block}#{remaining}"
  end

  def run(check: false)
    expected = render
    actual = File.file?(OUTPUT) ? File.read(OUTPUT, encoding: "UTF-8") : nil

    if check
      return true if actual == expected

      warn "face_css: public/face.css differs from ordered source modules — run ruby MASTER/tools/rails/build_face_css.rb"
      return false
    end

    if actual == expected
      puts "face_css: already current" unless check
      return true
    end

    FileUtils.mkdir_p(File.dirname(OUTPUT))
    File.write(OUTPUT, expected)
    puts "face_css: rebuilt #{OUTPUT.sub("#{ROOT}/", '')} (#{expected.bytesize} bytes)"
    true
  end
end

if $PROGRAM_NAME == __FILE__
  check = ARGV.include?("--check")
  exit(MasterFaceStylesheet.run(check:) ? 0 : (check ? 1 : 2))
end
