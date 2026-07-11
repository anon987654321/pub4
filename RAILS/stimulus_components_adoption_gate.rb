#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)
require_relative "../OPERATOR/lib/gate_result"
RAILS_ROOT = File.join(ROOT, "RAILS")
BOOT = File.join(RAILS_ROOT, "shared/frontend/pub4_stimulus_boot.js")
BASELINE = File.join(RAILS_ROOT, "shared/config/importmap_baseline.rb")
VENDOR = File.join(RAILS_ROOT, "shared/vendor/javascript")

REQUIRED_BOOT = %w[
  password-visibility nested-form rails-nested-form carousel character-counter
  checkbox-select-all dialog read-more textarea-autogrow
].freeze

FORBIDDEN_VIEW_PATTERNS = [
  /data-controller="char-counter"/,
  /controller:\s*["']char-counter/,
  /char-counter-max-value/,
  /data-char-counter-target/,
].freeze

FORBIDDEN_CONTROLLER_FILES = %w[
  char_counter_controller.js
  textarea_autogrow_controller.js
  stimulus_rails_nested_form_controller.js
].freeze

result = Deploy::GateResult.new

unless File.file?(BOOT)
  result.fail("missing pub4_stimulus_boot.js")
else
  boot = File.read(BOOT)
  REQUIRED_BOOT.each do |name|
    result.fail("pub4_stimulus_boot must register #{name}") unless boot.include?(%("#{name}"))
  end
  result.fail("deprecated stimulus_components.js must not return") if File.file?(File.join(RAILS_ROOT, "shared/frontend/stimulus_components.js"))
end

if File.file?(BASELINE)
  baseline = File.read(BASELINE)
  result.fail("importmap must pin shared vendor stimulus-components") unless baseline.include?("vendor/javascript")
  %w[password-visibility rails-nested-form carousel].each do |pkg|
    result.fail("importmap missing #{pkg}") unless baseline.include?(pkg)
  end
else
  result.fail("missing shared importmap baseline")
end

Dir.glob(File.join(RAILS_ROOT, "**", "*.{erb,html}"), File::FNM_DOTMATCH).each do |path|
  next if path.include?("/vendor/")
  next if path.include?("/public/assets/")
  next if path.include?("/node_modules/")

  body = File.read(path)
  FORBIDDEN_VIEW_PATTERNS.each do |pattern|
    result.fail("#{path.sub(ROOT + '/', '')}: forbidden legacy char-counter pattern") if body.match?(pattern)
  end
end

Dir.glob(File.join(RAILS_ROOT, "**/app/javascript/controllers/*.js")).each do |path|
  base = File.basename(path)
  result.fail("remove duplicate controller #{path.sub(ROOT + '/', '')}") if FORBIDDEN_CONTROLLER_FILES.include?(base)
end

Dir.glob(File.join(VENDOR, "@stimulus-components--*.js")).each do |path|
  result.fail("empty vendor package #{path}") if File.size(path) < 100
end

result.report!("Stimulus Components adoption gate passed.")