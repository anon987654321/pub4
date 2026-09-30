# frozen_string_literal: true

module Master
  # The release version belongs to pub4's root VERSION file. Constitutional
  # revisions remain in data/soul.yml and are deliberately independent.
  VERSION = File.read(File.expand_path("../../VERSION", __dir__), encoding: "UTF-8").strip.freeze
end
