# frozen_string_literal: true

require "minitest/autorun"

class SocialFrontpageContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  COOKIE = File.join(ROOT, "shared/app/views/shared/_cookie_banner.html.erb")
  EN = File.join(ROOT, "shared/config/locales/social.en.yml")
  NB = File.join(ROOT, "shared/config/locales/social.nb.yml")
  PROMPT = File.join(ROOT, "shared/app/views/shared/_post_auth_prompt.html.erb")
  MODAL = File.join(ROOT, "shared/app/assets/stylesheets/_modal.scss")
  BRGEN_SHOW = File.join(ROOT, "brgen/app/views/posts/show.html.erb")
  AMBER_SHOW = File.join(ROOT, "amber/app/views/posts/show.html.erb")
  MASTER_RUNTIME = File.join(ROOT, "..", "MASTER/data/runtime.yml")

  def test_cookie_preferences_name_necessary_storage_separately
    body = File.read(COOKIE)
    assert_includes body, "cookie-purpose--necessary"
    assert_includes File.read(EN), 'necessary:'
    assert_includes File.read(NB), 'necessary:'
  end

  def test_post_auth_prompt_is_native_popover_and_shared
    prompt = File.read(PROMPT)
    assert_includes prompt, 'popovertarget='
    assert_includes prompt, 'popover'
    assert_includes prompt, 'nav.sign_in'
    assert_includes prompt, 'auth.create_account'
    assert_includes File.read(MODAL), ".post-auth-prompt"
  end

  def test_both_post_detail_surfaces_keep_public_reading_open
    assert_includes File.read(BRGEN_SHOW), 'shared/post_auth_prompt'
    assert_includes File.read(AMBER_SHOW), 'shared/post_auth_prompt'
    assert_includes File.read(BRGEN_SHOW), 'anchor: "comments-section"'
    assert_includes File.read(AMBER_SHOW), 'anchor: "comments"'
  end

  def test_master_carries_the_reference_as_runtime_knowledge
    body = File.read(MASTER_RUNTIME)
    assert_includes body, "social_frontpage_reference:"
    assert_includes body, "support.reddithelp.com"
    assert_includes body, "help.x.com/en/rules-and-policies/x-cookies"
    assert_includes body, "support.tiktok.com/en/getting-started/for-you/test-for-you"
  end
end
