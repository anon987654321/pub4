# frozen_string_literal: true

require "minitest/autorun"

class SourceWrapperArtifactTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_ruby_sources_contain_no_markup_wrappers
    offenders = Dir.glob(File.join(ROOT, "**", "*.rb")).filter_map do |path|
      next if path.include?("/vendor/") || path.include?("/node_modules/")

      body = File.read(path, encoding: "UTF-8")
      next unless body.match?(/^<sub>$|^<\/sub>$/)

      path.delete_prefix(ROOT + "/")
    end

    assert_empty offenders, "markup wrapper leaked into Ruby source: #{offenders.join(", ")}"
  end
end
