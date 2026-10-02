# frozen_string_literal: true

require "minitest/autorun"

class StudioRuntimeBoundaryTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_studio_runtime_does_not_require_sibling_implementations
    forbidden = %r{
      require(?:_relative)?\s+
      ["'][^"']*(?:MASTER|RAILS|OPENBSD)/
      (?:lib|app|tools|shared|engines)[^"']*["']
    }x
    offenders = Dir.glob(File.join(ROOT, "**", "*.rb")).sort.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, number|
        next if line.lstrip.start_with?("#")
        next unless line.match?(forbidden)
        "#{path.delete_prefix(ROOT + "/")}:#{number}: #{line.strip}"
      end
    end
    assert_empty offenders
  end

  def test_canonical_media_entrypoints_exist
    %w[dilla/dilla.rb postpro/postpro.rb replicate/replicate.rb photograph.rb].each do |entry|
      assert File.file?(File.join(ROOT, entry)), "missing STUDIO/#{entry}"
    end
  end
end
