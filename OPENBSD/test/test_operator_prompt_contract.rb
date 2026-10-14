# frozen_string_literal: true

require "minitest/autorun"

class TestOperatorPromptContract < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  COMPAT = File.join(ROOT, "FUN", "zshrc.shared")
  CANONICAL = File.join(ROOT, "OPENBSD", "lib", "zshrc.shared")
  ZSHRC = File.join(ROOT, "OPENBSD", "etc", ".zshrc")

  def test_existing_shell_entrypoint_resolves_to_the_canonical_prompt
    assert File.symlink?(COMPAT), "FUN/zshrc.shared should remain a compatibility symlink"
    assert_equal "../OPENBSD/lib/zshrc.shared", File.readlink(COMPAT)
    assert File.file?(CANONICAL)
    assert_includes File.read(ZSHRC), 'source "${PUB4_ROOT}/FUN/zshrc.shared"'
  end

  def test_provider_credentials_are_loaded_only_from_a_host_local_file
    source = File.read(ZSHRC)

    refute_match(/^\s*export\s+\w*(?:API_KEY|ACCESS_TOKEN|SECRET|TOKEN)\w*\s*=/i, source)
    assert_includes source, 'typeset -g PUB4_OPERATOR_ENV="${HOME}/.config/pub4/operator.env"'
    assert_includes source, 'source "$PUB4_OPERATOR_ENV"'
  end

  def test_prompt_uses_the_plain_openbsd_host_path_shape
    source = File.read(CANONICAL)

    assert_includes source, "PROMPT='%m:%~$ '"
    assert_includes source, "RPROMPT=''"
    refute_match(/starship|powerline|\e\[/i, source)
  end
end
