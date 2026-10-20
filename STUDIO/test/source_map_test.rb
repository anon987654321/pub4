# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../source_map"

# The map names every section a reader would jump to, by line number, and never loads the file.
class SourceMapTest < Minitest::Test
  def with_source(text)
    Dir.mktmpdir("source-map-") do |dir|
      path = File.join(dir, "tool.rb")
      File.write(path, text)
      yield path
    end
  end

  def test_names_modules_classes_methods_and_banners_with_their_lines
    with_source("# --- wav.rb ---\nmodule WAV\n  class Inner; end\nend\n\ndef helper?\nend\nclass Late\nend\n") do |path|
      assert_equal [[1, "section", "wav.rb"], [2, "module", "WAV"], [6, "def", "helper?"], [8, "class", "Late"]],
                   Studio::SourceMap.entries(path)
    end
  end

  def test_never_executes_the_file
    with_source("raise 'loaded'\nmodule Quiet\nend\n") do |path|
      assert_equal [[2, "module", "Quiet"]], Studio::SourceMap.entries(path)
    end
  end

  def test_render_leads_with_the_line_and_section_counts
    with_source("module A\nend\n") { |path| assert_match(/tool\.rb: 2 lines, 1 sections\n\s+1  module  A/, Studio::SourceMap.render(path)) }
  end

  def test_both_large_tools_print_their_own_map
    %w[dilla/dilla.rb postpro/postpro.rb].each do |tool|
      out = IO.popen([RbConfig.ruby, File.expand_path("../#{tool}", __dir__), "--map"], err: File::NULL, &:read)
      assert_match(/#{File.basename(tool)}: \d+ lines, \d+ sections/, out)
    end
  end
end
