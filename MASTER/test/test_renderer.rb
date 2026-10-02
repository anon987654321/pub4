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

  def test_compact_splash_names_the_release_version
    old = ENV.delete("MASTER_BOOT_STATUS")
    $stdout.stub(:tty?, false) do
      text = FakeRenderer.new(config: {}).splash("model")
      assert_includes strip_ansi(text), "master0 at mainbus0: MASTER 1.0.0"
    end
  ensure
    ENV["MASTER_BOOT_STATUS"] = old if old
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

  def test_session_line_is_dmesg_shaped
    renderer = FakeRenderer.new(config: {})
    assert_equal "session0 at master0: main, 3 messages kept", strip_ansi(renderer.session_line("Main", 3))
  end

  def test_prompt_line_handles_missing_model
    renderer = FakeRenderer.new(config: {})
    state, prompt = renderer.prompt_line(nil, "idle", tokens: 0)

    assert_includes strip_ansi(state), "model: "
    assert_equal "* ", strip_ansi(prompt).lines.last.chomp
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

  def test_shell_prompt_is_small_and_two_line
    renderer = FakeRenderer.new(config: {})
    _state, prompt = renderer.prompt_line("model", "discover", tokens: 45_000)

    clean = strip_ansi(prompt)
    lines = clean.lines.map(&:chomp)

    assert_match(/\A(?:~|…|\/|[A-Za-z0-9_])/, lines.first)
    refute_includes lines.first, "(discover)"
    refute_includes clean, "  "
    assert_equal 2, lines.size
    assert_match(/discover [%$]\z/, lines.first)
    assert_equal "* ", lines.last
    assert_operator lines.first.length, :<=, Master::Voice::Renderer::PromptComponents::PROMPT_MAX_CHARS
  end

  def test_shell_prompt_home_path_uses_path_operations
    renderer = FakeRenderer.new(config: {})
    path = File.join(Dir.home, "src", "pub4")

    assert_equal "~/src/pub4", renderer.send(:home_path, path)
    assert_equal "/tmp/pub4", renderer.send(:home_path, "/tmp/pub4")
  end

  def test_prompt_uses_one_bounded_git_status_probe
    renderer = FakeRenderer.new(config: {})
    calls = []
    status = Struct.new(:success?).new(true)
    output = "# branch.head main\n# branch.ab +2 -1\n1 .M N... 100644 100644 abc def app.rb\n"

    Master::Io::Exec.stub(:capture3, ->(*args, **kwargs) { calls << [args, kwargs]; [output, "", status] }) do
      state = renderer.send(:git_prompt_state)
      assert_equal({ branch: "main", ahead: 2, behind: 1, dirty: true }, state)
    end

    assert_equal 1, calls.size
    assert_equal 0.15, calls.first.last[:timeout]
  end

  def test_long_git_branch_is_bounded_before_prompt_layout
    renderer = FakeRenderer.new(config: {})
    renderer.stub(:git_prompt_state, branch: "feature/with/a/very/long/operator/branch/name", ahead: 0, behind: 0, dirty: false) do
      _state, prompt = renderer.prompt_line("model", "discover", tokens: 10)
      assert_operator strip_ansi(prompt).lines.first.length, :<=, Master::Voice::Renderer::PromptComponents::PROMPT_MAX_CHARS
      assert_includes strip_ansi(prompt), "feature/with/a/very/long/o…"
    end
  end

  def test_splash_is_plain_ascii_in_dmesg_shape
    lines = $stdout.stub(:tty?, false) do
      FakeRenderer.new(config: {}).splash("model").lines.map { |l| strip_ansi(l).chomp }
    end
    filled = lines.reject(&:empty?)

    assert_match(/\Amaster0 at mainbus0: MASTER \S+ #\d+, model /, filled.first)
    assert_match(/\Ahost0 at mainbus0: \w+@\S+:\//, filled[1])
    assert(filled.any? { |line| line == "root on master0" })
    assert(filled.all? { |line| line.match?(/\A(?:[a-z]+\d+ at [a-z]+\d+: |[a-z]+\d+: |root on )/) })
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
