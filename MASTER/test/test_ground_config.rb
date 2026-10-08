# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# .master/config.yml merges over DEFAULTS, so a misspelled key is kept and never
# read: `budget_mx: 2` leaves the $10 default spending with nothing said.
class TestGroundConfig < Minitest::Test
  def config_with(yaml)
    Dir.mktmpdir("ground_config") do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      File.write(File.join(root, ".master", "config.yml"), yaml)
      config = nil
      _out, err = capture_io { config = Master::Ground::Config.new(root) }
      yield config, err
    end
  end

  def test_a_near_miss_on_a_known_key_is_named_at_load_and_by_validate
    config_with("budget_mx: 2\n") do |config, err|
      assert_match(/'budget_mx' is not read; did you mean 'budget_max'/, err) # source-assertion: ok — the warning written to stderr, not a source file
      assert_includes config.validate.join, "did you mean 'budget_max'"
      assert_in_delta Master::Ground::Config::BUDGET_MAX_DEFAULT, config.budget_max
    end
  end

  # The web tier and pairing keep their own keys here, so only a near miss is
  # a finding; an unrelated key and a short one two edits away are not.
  def test_an_unrelated_key_is_not_a_typo
    config_with("web_token: abc\nroot: /srv\npersona: anchor\n") do |config, err|
      assert_empty err
      assert config.valid?, config.validate.join("; ")
    end
  end
end
