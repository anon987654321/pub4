# frozen_string_literal: true

require "test_helper"
require "cli/intent_router"

class TestIntentRouter < Minitest::Test
  Router = Master::CLI::IntentRouter

  def test_filler_pronouns_do_not_choose_an_intent
    router = Router.new

    assert_equal :unknown, router.classify("Let's do it!")
    assert_equal :unknown, router.classify("I read it")
  end

  def test_exact_continuation_phrases_remain_supported
    router = Router.new

    assert_equal :continue_prior_plan, router.classify("go ahead")
    assert_equal :continue_prior_plan, router.classify("continue prior plan")
    assert_equal :unknown, router.classify("continue the thing")
  end

  def test_specific_actions_still_win_without_pronoun_tokens
    router = Router.new

    assert_equal :codify_policy, router.classify("make it ruby")
    assert_equal :verify_patch_landed, router.classify("verify it")
    assert_equal :write_repo_changes, router.classify("land it")
  end
end
