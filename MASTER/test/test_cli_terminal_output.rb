# frozen_string_literal: true

require_relative "test_helper"

class TestCLITerminalOutput < Minitest::Test
  Renderer = Struct.new(:calls) do
    def render(text, mode:)
      calls << [text, mode]
      "#{mode}:#{text}"
    end
  end

  def session
    Master::CLI::Session.allocate.tap do |cli|
      cli.instance_variable_set(:@refs, Struct.new(:renderer, :bus).new(Renderer.new([]), nil))
    end
  end

  def test_long_output_is_pageable_only_on_a_terminal
    output = "row\n" * 30

    $stdout.stub(:tty?, false) do
      refute session.send(:pageable_output?, output)
    end

    saved = ENV["MASTER_PAGER"]
    ENV["MASTER_PAGER"] = "0"
    $stdout.stub(:tty?, true) do
      TTY::Screen.stub(:height, 24) do
        refute session.send(:pageable_output?, output)
      end
    end

    ENV.delete("MASTER_PAGER")
    $stdout.stub(:tty?, true) do
      TTY::Screen.stub(:height, 24) do
        assert session.send(:pageable_output?, output)
      end
    end
  ensure
    saved.nil? ? ENV.delete("MASTER_PAGER") : ENV["MASTER_PAGER"] = saved
  end

  def test_pager_selection_rejects_shell_fragments
    saved = ENV["MASTER_PAGER"]
    ENV["MASTER_PAGER"] = "less; rm -rf /"

    Master::Trace::Dmesg.stub(:status, ->(*) {}) do
      assert_nil session.send(:terminal_pager_command)
    end
  ensure
    saved.nil? ? ENV.delete("MASTER_PAGER") : ENV["MASTER_PAGER"] = saved
  end

  def test_piped_output_stays_plain_and_does_not_start_a_pager
    text = "row\n" * 30
    stdout, = capture_io do
      session.send(:print_terminal_output, text, mode: :dim)
    end

    # puts adds no newline after text that already ends in one.
    assert_equal "dim:#{text}", stdout
  end
end
