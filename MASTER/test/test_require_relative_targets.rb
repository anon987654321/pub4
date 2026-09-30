# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class TestRequireRelativeTargets < Minitest::Test
  ROOT = File.expand_path("../lib", __dir__)

  def test_literal_require_relative_targets_exist
    missing = []

    Dir.glob(File.join(ROOT, "**", "*.rb")).sort.each do |source|
      base = File.dirname(source)
      File.read(source).scan(/require_relative\s+["']([^"']+)["']/).flatten.each do |spec|
        target = File.expand_path(spec, base)
        candidates = ["#{target}.rb", File.join(target, "index.rb")]
        missing << "#{source.delete_prefix("#{ROOT}/")}: #{spec}" unless candidates.any? { |path| File.file?(path) }
      end
    end

    assert_empty missing, "broken require_relative targets:\n#{missing.join("\n")}"
  end
end
