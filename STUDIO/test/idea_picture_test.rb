# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "minitest/mock"
require "open3"
require "tmpdir"
require_relative "../output_paths"
require_relative "../visual/generators/idea_picture"

class TestIdeaPictureOutput < Minitest::Test
  def test_grade_returns_the_external_render_not_the_original_still
    Dir.mktmpdir do |dir|
      source = File.join(dir, "portrait source.jpg")
      File.write(source, "source")
      picture = Studio::Visual::IdeaPicture.new(directory: dir)
      render_root = File.join(dir, "renders")
      status = successful_status

      runner = lambda do |env, *_args|
        output_dir = env.fetch("POSTPRO_OUTPUT_DIR")
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, "postpro_portrait_source_test_v1.jpg"), "graded")
        ["postpro0: ok write", status]
      end

      Studio::OutputPaths.stub(:render_directory, render_root) do
        Open3.stub(:capture2e, runner) do
          graded = picture.send(:grade, source, "stamp")
          assert_equal File.join(render_root, "photograph-stamp",
                                 "postpro_portrait_source_test_v1.jpg"), graded
          refute_equal source, graded
          assert_equal "graded", File.read(graded)
        end
      end
    end
  end

  def test_grade_fails_instead_of_returning_an_ungraded_still
    Dir.mktmpdir do |dir|
      source = File.join(dir, "portrait.jpg")
      File.write(source, "source")
      picture = Studio::Visual::IdeaPicture.new(directory: dir)

      Studio::OutputPaths.stub(:render_directory, File.join(dir, "renders")) do
        Open3.stub(:capture2e, ->(_env, *_args) { ["postpro0: ok", successful_status] }) do
          error = assert_raises(RuntimeError) { picture.send(:grade, source, "stamp") }
          assert_match(/produced no graded still/, error.message)
        end
      end
    end
  end

  private

  def successful_status
    Object.new.tap { |status| status.define_singleton_method(:success?) { true } }
  end
end
