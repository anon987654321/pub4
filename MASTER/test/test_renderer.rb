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

  def test_compact_splash_reports_degraded_voice_when_synthesis_failed
    old = ENV["MASTER_TTS_DEGRADED"]
    ENV.delete("MASTER_TTS_DEGRADED")
    renderer = FakeRenderer.new(config: {})

    assert defined?(Master::Voice::Speech), "speech service should be available to the renderer"
    Master::Voice::Speech.stub(:last_error, "provider unavailable") do
      text = renderer.splash("model")
      assert_includes strip_ansi(text), "voice0 at mainbus0: degraded"
    end
  ensure
    ENV["MASTER_TTS_DEGRADED"] = old
  end

  def test_compact_splash_names_the_release_version
    old = ENV.delete("MASTER_BOOT_STATUS")
    $stdout.stub(:tty?, false) do
      text = FakeRenderer.new(config: {}).splash("model")
      assert_includes strip_ansi(text), "master0 at mainbus0: MASTER 1.0.3"
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

      refute_match(/\e\[/, text, "the boot is plain dmesg on a terminal too")
      assert_includes text, "root on master0"
    end
  ensure
    ENV["MASTER_DMESG"] = old_dmesg
  end

  def test_session_line_is_dmesg_shaped
    renderer = FakeRenderer.new(config: {})
    assert_equal "session0 at master0: main, 3 messages kept", strip_ansi(renderer.session_line("Main", 3))
  end

  def test_cli_prompt_bounds_are_the_face_contract
    assert_equal Master::Face::Contract.prompt_max, Master::Voice::Renderer::PromptComponents::PROMPT_MAX_CHARS
    assert_equal Master::Face::Contract.prompt_measure, Master::Voice::Renderer::PromptComponents::PROMPT_MEASURE_CH
  end

  def test_face_contract_exposes_one_state_and_spatial_budget
    budget = Master::Face::Contract.budget
    aliases = Master::Face::Contract.mode_aliases

    assert_equal 24, budget.fetch("active_fps")
    assert_equal 120, budget.fetch("mobile_particles")
    assert_equal "error", aliases.fetch("phantom")
    assert_equal 38, Master::Face::Contract.camera.fetch("fov")
  end

  def test_prompt_line_handles_missing_model
    renderer = FakeRenderer.new(config: {})
    state, prompt = renderer.prompt_line(nil, "idle", tokens: 0)

    assert_match(/\bno model, /, strip_ansi(state))
    refute_match(/\n|\r/, strip_ansi(prompt))
    assert_match(/\A\S+:.+\$ \z/, strip_ansi(prompt))
  end

  def test_phase_prompt_uses_the_plain_openbsd_operator_words
    renderer = FakeRenderer.new(config: {})

    # The REPL's shell-shaped prompt and the face's glyph remain distinct.
    Master::Face::Contract.stub(:glyph, nil) do
      assert_equal "input", renderer.phase_prompt(true, "discover")
    end
    assert_equal "error input", renderer.phase_prompt(false, "discover")
  end

  def test_face_renderer_keeps_its_shared_ascii_glyphs
    assert_equal "|-", Master::Face::Contract.glyph(:input)
    assert_equal "\\_", Master::Face::Contract.glyph(:continuation)
    assert_equal "/", Master::Face::Contract.glyph(:output)
  end

  def test_boot_identity_shell_token_follows_zsh_and_posix_conventions
    renderer = FakeRenderer.new(config: {})
    old_shell = ENV["SHELL"]

    ENV["SHELL"] = "/bin/zsh"
    assert_equal "%", renderer.prompt_token
    ENV["SHELL"] = "/bin/sh"
    assert_equal "$", renderer.prompt_token
  ensure
    ENV["SHELL"] = old_shell
  end

  def test_prompt_line_state_shows_context_usage
    state, prompt = FakeRenderer.new(config: {}).prompt_line("model", "idle", tokens: 45_000)

    assert_includes strip_ansi(state), "model, 45.0k/128.0k"
    assert_match(/\A\S+:.+\$ \z/, strip_ansi(prompt))
  end

  def test_cli_prompt_uses_face_interface_geometry
    contract = Master::Design.face_interface(root: Master::ROOT)
    refute_empty contract
    assert_equal 66, contract.dig("prompt", "measure_ch")
    assert_equal 72, contract.dig("prompt", "max_ch")
  end

  # The stipple moods are one table for the web face and Ruby; every state the
  # contract names has a row, each dial is a bounded number, and an unknown
  # mode reads as idle the way the browser reads it.
  def test_stipple_profiles_cover_every_face_mode_with_bounded_dials
    contract = Master::Face::Contract
    contract.modes.each do |mode|
      profile = contract.stipple_profile(mode)
      assert_equal %w[attract density luminosity ripple turbulence], profile.keys.sort, mode
      profile.each_value { |value| assert_includes 0.0..1.2, value, mode }
    end
    assert_equal contract.stipple_profile("idle"), contract.stipple_profile("no-such-mode")
  end

  # The meaning of each state in the material is one table with the dials: every mode has a
  # membership and a force, and the force is a word the vocabulary defines.
  def test_stipple_meaning_covers_every_face_mode_from_the_vocabulary
    contract = Master::Face::Contract
    vocabulary = contract.data.fetch("stipple_vocabulary")

    contract.modes.each do |mode|
      meaning = contract.stipple_meaning(mode)
      assert_equal %w[force membership note], meaning.keys.sort, mode
      assert vocabulary.key?(meaning.fetch("force")), "#{mode}: force is not in the vocabulary"
    end

    assert_equal "residual", contract.stipple_meaning("idle").fetch("force")
    assert_equal contract.stipple_meaning("idle"), contract.stipple_meaning("no-such-mode")
  end

  def test_stipple_point_size_is_canonical_and_bounded
    sizing = Master::Face::Contract.stipple_point_size

    assert_equal %w[base bias_max bias_min bias_scale distance_max distance_min output_max output_min reference_depth],
                 sizing.keys.sort
    assert_equal 5.0, sizing.fetch("reference_depth")
    assert_operator sizing.fetch("bias_min"), :<=, sizing.fetch("bias_max")
    assert_operator sizing.fetch("distance_min"), :<=, sizing.fetch("distance_max")
    assert_operator sizing.fetch("output_min"), :<=, sizing.fetch("output_max")
    assert_includes 1.0..1.5, sizing.fetch("output_min")
    assert_includes 1.0..1.5, sizing.fetch("output_max")
  end

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

  def test_openbsd_operator_prompt_matches_the_historical_shell_contract
    renderer = FakeRenderer.new(config: {})

    renderer.stub(:safe_hostname, "vm23.brgen.no") do
      Dir.stub(:pwd, File.join(Dir.home, "pub4")) do
        _state, prompt = renderer.prompt_line("model", "discover", tokens: 10)

        assert_equal "vm23:~/pub4$ ", strip_ansi(prompt)
      end
    end
  end

  def test_shell_prompt_is_small_and_single_line
    renderer = FakeRenderer.new(config: {})
    _state, prompt = renderer.prompt_line("model", "discover", tokens: 45_000)

    clean = strip_ansi(prompt)
    assert_equal 1, clean.lines.size
    assert_match(/\A\S+:.+\$ \z/, clean)
    refute_match(/\e\[/, prompt, "the OpenBSD-console prompt does not need ANSI segment styling")
    assert_operator clean.chomp.length, :<=, Master::Voice::Renderer::PromptComponents::PROMPT_MAX_CHARS
  end

  def test_shell_prompt_names_the_active_chat_destination
    renderer = FakeRenderer.new(config: {})
    state, prompt = renderer.prompt_line("model", "discover", tokens: 10, destination: "read-only:irc:#help")

    assert_includes strip_ansi(state), "read only irc help discover"
    refute_includes strip_ansi(prompt), "read only irc help"
    assert_operator strip_ansi(prompt).length, :<=, Master::Voice::Renderer::PromptComponents::PROMPT_MAX_CHARS
  end

  def test_shell_prompt_bounds_long_branch_destination_and_phase
    renderer = FakeRenderer.new(config: {})
    git = { branch: "feature/this/is/a/very/long/branch/name", ahead: 1234, behind: 987, dirty: true }
    renderer.stub(:git_prompt_state, git) do
      state, prompt = renderer.prompt_line(
        "model", "a-phase-name-that-is-far-too-long", tokens: 10,
        destination: "read-only:irc:#a-very-long-channel-name"
      )
      state_text = strip_ansi(state)
      clean = strip_ansi(prompt)

      refute_match(/\n|\r/, clean)
      assert_operator clean.length, :<=, Master::Voice::Renderer::PromptComponents::PROMPT_MAX_CHARS
      assert_includes state_text, "read only irc a very"
      assert_includes state_text, "feature dirty"
      assert_includes state_text, "a phase na"
      assert_match(/\A\S+:.+\$ \z/, clean)
    end
  end

  def test_shell_prompt_home_path_uses_path_operations
    renderer = FakeRenderer.new(config: {})
    path = File.join(Dir.home, "src", "pub4")

    assert_equal "~/src/pub4", renderer.send(:home_path, path)
    assert_equal "/tmp/pub4", renderer.send(:home_path, "/tmp/pub4")
  end

  def test_shell_prompt_names_the_checkout_and_governed_tree
    renderer = FakeRenderer.new(config: {})
    expected = "#{File.basename(Master.repo_root)}/MASTER"

    Dir.stub(:pwd, File.join(Master.repo_root, "MASTER")) do
      assert_equal expected, renderer.send(:prompt_path, suffix_length: 20)
    end
  end

  def test_shell_prompt_keeps_checkout_tree_and_current_leaf_when_truncated
    renderer = FakeRenderer.new(config: {})
    path = File.join(Master.repo_root, "RAILS", "brgen", "app", "controllers", "messages", "directs")

    Dir.stub(:pwd, path) do
      displayed = renderer.send(:prompt_path, suffix_length: 34)

      assert_match(/\Apub4\/RAILS\//, displayed)
      assert_includes displayed, "/.../"
      assert_match(/directs\z/, displayed)
      assert_operator displayed.length, :<=, renderer.send(:prompt_path_budget, suffix_length: 34)
    end
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
    git = { branch: "feature/with/a/very/long/operator/branch/name", ahead: 0, behind: 0, dirty: false }
    renderer.stub(:git_prompt_state, git) do
      state, prompt = renderer.prompt_line("model", "discover", tokens: 10)
      clean = strip_ansi(prompt)
      refute_match(/\n|\r/, clean)
      assert_operator clean.length, :<=, Master::Voice::Renderer::PromptComponents::PROMPT_MAX_CHARS
      assert_includes strip_ansi(state), "feature"
    end
  end

  # A dmesg is legible on a serial console: no box drawing, no arrows, no
  # check marks, nothing that a pipe or a 7-bit terminal turns into gibberish.
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

  def test_measure_preserves_authored_paragraph_and_list_lines
    renderer = FakeRenderer.new(config: {})
    prose = ("measure " * 20).strip
    source = "#{prose}\n- #{prose}\n"

    assert_equal source, renderer.measure(source, width: 20)
  end

  def test_code_tables_and_key_value_lines_keep_their_shape
    renderer = FakeRenderer.new(config: {})
    long = "x " * 50
    text = "```\n#{long}\n```\n    #{long}\n| #{long}|\nkey=#{long}\n"

    assert_equal text, renderer.measure(text)
  end

  def test_the_boot_has_no_blank_line_and_no_edges
    lines = $stdout.stub(:tty?, false) do
      strip_ansi(FakeRenderer.new(config: {}).splash("model")).lines.map(&:chomp)
    end

    refute_empty lines.first
    refute_empty lines.last
    assert_equal 0, lines.count(&:empty?)
  end

  # The splash names the model the session runs on, which a pin or the router
  # chooses, and config["model"] can still hold another. The context beside
  # the name belongs to the named model.
  def test_the_splash_reads_the_context_window_of_the_model_it_names
    named = "agy:gemini-3.1-pro-high"
    configured = "deepseek-chat"
    refute_equal Master.context_window(named), Master.context_window(configured), "the fixture needs two windows"

    renderer = FakeRenderer.new(config: { "model" => configured })
    ENV["MASTER_BOOT_STATUS"] = "1"
    line = strip_ansi(renderer.splash(named)).lines.find { |l| l.start_with?("model0: ") }

    assert_includes line, "1000.0k context"
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  def test_terminal_markdown_preserves_long_paragraph_lines
    renderer = FakeRenderer.new(config: {})
    prose = ("This paragraph must remain one authored line " * 4).strip
    source = "# News\n\n#{prose}\n"

    rendered = $stdout.stub(:tty?, false) { renderer.terminal_markdown(source) }

    assert_equal "News\n\n#{prose}\n", rendered
  end

  def test_terminal_markdown_renders_headings_links_inline_code_and_fences
    renderer = FakeRenderer.new(config: {})
    source = "# Reply\n\nUse **bold**, `Ruby`, and [docs](https://example.com).\n\n```ruby\nputs \"hello\"\n```\n"
    rendered = $stdout.stub(:tty?, false) { renderer.terminal_markdown(source) }

    assert_includes rendered, "Reply"
    refute_includes rendered, "# Reply"
    assert_includes rendered, "Use bold, Ruby, and docs (https://example.com)."
    assert_includes rendered, "    puts \"hello\""
    refute_includes rendered, "```"
  end

  def test_terminal_markdown_keeps_table_rows_and_record_lines_intact
    renderer = FakeRenderer.new(config: {})
    source = "# Data\n| name | value |\nkey=value\n```ruby\nanswer = 42\n```"

    rendered = $stdout.stub(:tty?, false) { renderer.terminal_markdown(source) }

    assert_includes rendered, "| name | value |"
    assert_includes rendered, "key=value"
    assert_includes rendered, "    answer = 42"
  end

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "")
  end

  # A repair preview printed {“FEW_ARGUMENTS” => 28}: the renderer curled the
  # quotes inside a hash dump, so the line was no longer the value it reported
  # and no longer pasted back. Prose still gets the typographic pair.
  def test_prose_gets_bringhursts_apostrophe_and_one_space_after_a_period
    renderer = Master::Voice::Renderer.new(config: {})

    assert_equal "Don’t wait. It’s done.", renderer.beautify("Don't wait.  It's done.")
    assert_equal "see https://x.org/o'brien", renderer.beautify("see https://x.org/o'brien")
    assert_equal "count=3 isn't", renderer.beautify("count=3 isn't")
  end

  def test_the_terminal_reply_path_sets_prose_typographically
    renderer = Master::Voice::Renderer.new(config: {})
    text = renderer.terminal_markdown("It's a fine day -- really, 3-5 of them.  Truly.\n")

    assert_includes text, "It’s a fine day — really, 3–5 of them. Truly."
  end

  def test_quotes_stay_straight_on_a_record_line
    renderer = FakeRenderer.new(config: {})

    record = renderer.send(:beautify, %q{preview total=107 top_rules={"FEW_ARGUMENTS" => 28}})
    assert_equal %q{preview total=107 top_rules={"FEW_ARGUMENTS" => 28}}, record

    prose = renderer.send(:beautify, %q{The council called this a "plateau" and stopped.})
    assert_equal "The council called this a “plateau” and stopped.", prose
  end
end
