# frozen_string_literal: true

require_relative "test_helper"

class TestRenderer < Minitest::Test
  class FakeRenderer < Master::Voice::Renderer
    def dmesg_lines
      Array.new(self.class::BOOT_DMESG_LINES + 2) { |i| "boot line #{i}" }.first(self.class::BOOT_DMESG_LINES)
    end

    def git_rev
      "test"
    end

    def soul_version
      "test"
    end

    def imports_loaded
      []
    end

    def active_orders_count
      0
    end
  end

  def test_boot_dmesg_is_capped_at_ten_lines
    assert_equal 10, Master::Voice::Renderer::BOOT_DMESG_LINES
    assert_equal 10, FakeRenderer.new(config: {}).dmesg_lines.size
  end

  def test_splash_is_compact_by_default
    $stdout.stub(:tty?, false) do
      lines = FakeRenderer.new(config: {}).splash("model").lines

      assert_operator lines.size, :<=, 8
      assert_empty lines.grep(/boot line/)
    end
  end

  def test_splash_keeps_multiline_boot_shape_when_verbose
    ENV["MASTER_BOOT_STATUS"] = "1"
    lines = FakeRenderer.new(config: {}).splash("model").lines

    assert_operator lines.size, :>, 10
    assert_operator lines.count { |line| line.include?("boot line") }, :>=, 2
    assert_operator lines.count { |line| line.include?("boot line") }, :<=, 10
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  def test_interactive_splash_leaves_the_terminal_background_alone
    renderer = FakeRenderer.new(config: {})
    old_dmesg = ENV["MASTER_DMESG"]
    ENV.delete("MASTER_DMESG")

    $stdout.stub(:tty?, true) do
      text = renderer.splash("model")

      refute_includes text, "\e[44m"
      assert_includes text, "\e[37m"
      assert_includes text, "boot line 0"
      assert_includes text, "root on master0"
    end
  ensure
    ENV["MASTER_DMESG"] = old_dmesg
  end

  def test_prompt_line_handles_missing_model
    renderer = FakeRenderer.new(config: {})
    state, prompt = renderer.prompt_line(nil, "idle", tokens: 0)

    assert_includes strip_ansi(state), "model: "
    assert_match(/[%$] \z/, strip_ansi(prompt))
  end

  def test_prompt_line_state_shows_context_usage
    state, prompt = FakeRenderer.new(config: {}).prompt_line("model", "idle", tokens: 45_000)

    assert_includes strip_ansi(state), "ctx: 45.0k/128.0k"
    assert_match(/[%$] \z/, strip_ansi(prompt))
  end

  # A dmesg is legible on a serial console: no box drawing, no arrows, no
  # check marks, nothing that a pipe or a 7-bit terminal turns into gibberish.
  def test_shell_prompt_measures_visible_cells_not_ansi_bytes
    renderer = FakeRenderer.new(config: {})

    assert_equal 4, renderer.send(:visible_length, "\e[31mmain\e[0m")
  end

  def test_shell_prompt_truncates_a_long_path_to_the_available_measure
    renderer = FakeRenderer.new(config: {})

    truncated = renderer.send(:prompt_path, suffix_length: 60)
    assert_operator truncated.length, :<=, renderer.send(:prompt_path_budget, suffix_length: 60)
    refute_empty truncated
  end

  def test_shell_prompt_has_a_ruby_orb_and_quiet_typographic_hierarchy
    renderer = FakeRenderer.new(config: {})
    state, prompt = renderer.prompt_line("model", "discover", tokens: 45_000)

    clean = strip_ansi(prompt)
    assert_match(%r{\A◉ (?:~|…|/|[A-Za-z0-9_])}, clean)
    refute_includes clean, "(discover)"
    refute_includes clean, "  "
    assert_match(/(?:discover )?[%$] \z/, clean)
    assert_operator clean.length, :<=, 67
  end

  def test_splash_is_plain_ascii_in_dmesg_shape
    lines = $stdout.stub(:tty?, false) do
      FakeRenderer.new(config: {}).splash("model").lines.map { |l| strip_ansi(l).chomp }
    end
    filled = lines.reject(&:empty?)

    assert_match(/\AMASTER \S+ \(CONSTITUTIONAL\) #\d+: /, filled.first)
    assert_match(/\A {4}\w+@\S+:\//, filled[1])
    assert(filled.any? { |line| line.start_with?("root on master0 (") })
    assert_empty filled.grep(/[^\x20-\x7e]/), "the boot must stay plain ASCII"
  end

  def test_splash_never_prints_the_web_token
    secret = "s3cr3t-token-value-that-must-not-print"
    text = $stdout.stub(:tty?, false) do
      strip_ansi(FakeRenderer.new(config: { "web_token" => secret }).splash("model"))
    end

    refute_includes text, secret
    assert_includes text, "/pair issue"
  end

  def test_prose_wraps_to_the_measure_at_a_space
    renderer = FakeRenderer.new(config: {})
    prose = ("measure " * 20).strip
    wrapped = renderer.measure("#{prose}\n- #{prose}\n")

    assert(wrapped.lines.all? { |line| line.chomp.length <= 72 }, wrapped)
    assert(wrapped.split(/\s+/).all? { |word| %w[measure -].include?(word) }, "a word was split")
    assert(wrapped.lines.any? { |line| line.start_with?("  measure") }, "a list item hangs its continuation")
  end

  def test_code_tables_and_key_value_lines_keep_their_shape
    renderer = FakeRenderer.new(config: {})
    long = "x " * 50
    text = "```\n#{long}\n```\n    #{long}\n| #{long}|\nkey=#{long}\n"

    assert_equal text, renderer.measure(text)
  end

  def test_the_boot_has_one_blank_line_and_no_edges
    lines = $stdout.stub(:tty?, false) do
      strip_ansi(FakeRenderer.new(config: {}).splash("model")).lines.map(&:chomp)
    end

    refute_empty lines.first
    refute_empty lines.last
    assert_equal 1, lines.count(&:empty?)
  end

  # The splash names the model the session runs on, which a pin or the router
  # chooses, and config["model"] can still hold another. The context beside
  # the name belongs to the named model.
  def test_the_splash_reads_the_context_window_of_the_model_it_names
    named = "agy:gemini-2.5-pro"
    configured = "deepseek-chat"
    refute_equal Master.context_window(named), Master.context_window(configured), "the fixture needs two windows"

    renderer = FakeRenderer.new(config: { "model" => configured })
    ENV["MASTER_BOOT_STATUS"] = "1"
    line = strip_ansi(renderer.splash(named)).lines.find { |l| l.start_with?("model0: ") }

    assert_includes line, "1000.0k context"
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "")
  end

  # A repair preview printed {“FEW_ARGUMENTS” => 28}: the renderer curled the
  # quotes inside a hash dump, so the line was no longer the value it reported
  # and no longer pasted back. Prose still gets the typographic pair.
  def test_quotes_stay_straight_on_a_record_line
    renderer = FakeRenderer.new(config: {})

    record = renderer.send(:beautify, %q{preview total=107 top_rules={"FEW_ARGUMENTS" => 28}})
    assert_equal %q{preview total=107 top_rules={"FEW_ARGUMENTS" => 28}}, record

    prose = renderer.send(:beautify, %q{The council called this a "plateau" and stopped.})
    assert_equal "The council called this a “plateau” and stopped.", prose
  end
end
