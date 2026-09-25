# frozen_string_literal: true

require_relative "test_helper"

# The first boot on a phone says what is present and what is missing, with the
# fix for each. Nothing here touches the real home: the mark, the env file,
# PATH and git are all stubbed.
class TestDeviceOnboarding < Minitest::Test
  Onboarding = Master::Device::Onboarding
  KEY = "k" * 40

  def setup
    @dir = Dir.mktmpdir
    @mark = File.join(@dir, "state", "onboarded")
    @env_file = File.join(@dir, "config", "master", "env")
    @out = StringIO.new
    @present = []
  end

  def teardown = FileUtils.rm_rf(@dir)

  def onboarding(env: {}, android: true, identity: "")
    Onboarding.new(env:, out: @out, android:, mark: @mark, env_file: @env_file,
                   which: ->(cmd) { @present.include?(cmd) }, root: "/data/data/com.termux/files/home/pub4/MASTER",
                   git: ->(_key) { identity })
  end

  def test_a_first_run_is_detected_once
    first = onboarding
    assert first.first_run?
    first.run
    refute onboarding.first_run?
    assert File.exist?(@mark)
  end

  def test_the_phone_checklist_names_each_missing_piece_with_its_fix
    Master::Device.stub(:android?, true) do
      Onboarding.new(env: {}, out: @out, mark: @mark, env_file: @env_file, which: ->(_cmd) { false },
                     git: ->(_key) { "" }).run
    end
    text = @out.string
    assert_match(/^onboard0: first run on this phone$/, text)
    assert_match(/^env0: created /, text)
    assert_match(/^build0: .*pkg install build-essential$/, text)
    assert_match(/^termux0: .*install the Termux:API app, then pkg install termux-api$/, text)
    assert_match(/^model0: no key.*set OPENROUTER_API_KEY in .*env, or pkg install ollama/, text)
    assert_match(/^git0: .*git config --global user.name/, text)
    assert_match(/^ear0: packages /, text)
    assert_match(%r{^checkout0: checkout at }, text)
  end

  def test_a_host_that_is_not_a_phone_skips_the_termux_checks
    onboarding(android: false, identity: "dev").run
    assert_match(/^onboard0: first run on this host$/, @out.string)
    refute_match(/^(build|termux|sqlite|ear)0:/, @out.string)
  end

  def test_a_later_boot_prints_only_what_is_still_missing
    onboarding.run
    @out = StringIO.new
    @present.concat(%w[clang make pkg-config])
    onboarding.run
    lines = @out.string.lines.map { |line| line.split(":").first }
    assert_equal %w[termux0 git0], lines
  end

  def test_a_checkout_on_shared_storage_is_named
    check = Onboarding.new(env: {}, out: @out, android: true, mark: @mark, env_file: @env_file,
                           which: ->(_cmd) { false }, root: "/storage/emulated/0/pub4/MASTER", git: ->(_key) { "" })
                      .checks.find { |candidate| candidate.name == :checkout }
    refute check.ok
    assert_includes check.says, "~/pub4"
  end

  def test_the_env_template_is_written_once_with_no_key
    assert onboarding.ensure_env_file
    text = File.read(@env_file)
    assert_equal 0o600, File.stat(@env_file).mode & 0o777
    assert(text.lines.all? { |line| line.start_with?("#") })
    File.write(@env_file, "OPENROUTER_API_KEY=#{KEY}\n")
    refute onboarding.ensure_env_file
    assert_equal "OPENROUTER_API_KEY=#{KEY}\n", File.read(@env_file)
  end

  def test_one_key_picks_its_lane
    assert_equal %w[gemini GEMINI_API_KEY], onboarding(env: { "GEMINI_API_KEY" => KEY }).lane
    assert_equal %w[replicate REPLICATE_API_TOKEN], onboarding(env: { "REPLICATE_API_TOKEN" => KEY }).lane
    assert_equal %w[openrouter OPENROUTER_API_KEY],
                 onboarding(env: { "GEMINI_API_KEY" => KEY, "OPENROUTER_API_KEY" => KEY }).lane
  end

  def test_no_key_falls_to_ollama_then_the_keyless_tier
    assert_equal ["llm7", nil], onboarding(env: { "OPENROUTER_API_KEY" => "short" }).lane
    @present << "ollama"
    assert_equal ["ollama", nil], onboarding.lane
  end

  def test_it_stays_quiet_without_a_terminal_or_under_proof
    assert_nil Onboarding.run!(env: {}, out: @out, tty: false)
    assert_nil Onboarding.run!(env: { "MASTER_IN_PROOF" => "1" }, out: @out, tty: true)
    assert_empty @out.string
  end

  def test_missing_gems_reads_the_lockfile_and_skips_git_sources
    lock = File.join(@dir, "Gemfile.lock")
    File.write(lock, "GEM\n  specs:\n\nDEPENDENCIES\n  minitest (>= 5.25)\n  no_such_gem_here (~> 1.0)\n  " \
                     "rb-edge-tts!\n\nBUNDLED WITH\n  4.0.7\n")
    assert_equal ["no_such_gem_here"], Onboarding.missing_gems(lock)
  end
end
