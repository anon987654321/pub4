# frozen_string_literal: true

require_relative "test_helper"
require "rbconfig"
require "tmpdir"
require_relative "../lib/io/idea_picture"

class TestIdeaPicture < Minitest::Test
  Status = Struct.new(:ok) do
    def success? = ok
  end

  def test_write_uses_the_shared_runner_and_parses_result_keys
    with_script do |script|
      calls = []
      runner = lambda do |*argv, **options|
        calls << [argv, options]
        ['{"clip":"out.mp4"}', Status.new(true)]
      end

      result = Master::Io::Exec.stub(:capture2e, runner) do
        Master::Io::IdeaPicture.new(script:).write("portrait", film: false, duration: 7, timeout: 9)
      end

      assert_equal "out.mp4", result.fetch(:clip)
      argv, options = calls.fetch(0)
      assert_equal [RbConfig.ruby, script, "--duration", "7", "portrait"], argv
      assert_equal File.dirname(script), options.fetch(:chdir)
      assert_equal 9, options.fetch(:timeout)
      assert_equal true, options.fetch(:raise_on_timeout)
    end
  end

  def test_write_reports_failed_studio_output
    with_script do |script|
      runner = lambda { |*args, **options| ["warning\nrender failed\n", Status.new(false)] }
      error = assert_raises(RuntimeError) do
        Master::Io::Exec.stub(:capture2e, runner) do
          Master::Io::IdeaPicture.new(script:).write("portrait")
        end
      end

      assert_match(/render failed/, error.message)
    end
  end

  def test_write_reports_timeout_explicitly
    with_script do |script|
      runner = lambda { |*args, **options| raise Master::Io::Exec::TimeoutError, "process timed out after 0.1s" }
      error = assert_raises(RuntimeError) do
        Master::Io::Exec.stub(:capture2e, runner) do
          Master::Io::IdeaPicture.new(script:).write("portrait")
        end
      end

      assert_match(/STUDIO photograph timed out/, error.message)
    end
  end

  private

  def with_script
    Dir.mktmpdir("idea-picture-test") do |dir|
      script = File.join(dir, "photograph.rb")
      File.write(script, "# test fixture\n")
      yield script
    end
  end
end
