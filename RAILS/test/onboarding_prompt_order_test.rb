# frozen_string_literal: true

require "minitest/autorun"

# The editorial welcome comes first. Install follows it, then the menu coach
# and push button, with cookie consent resolved before any of them interrupt.
#
# That is a product decision, and before this it lived nowhere: each of the
# three prompts decided on its own when to appear, none of them knew the others
# existed, and the ordering that resulted was whichever timer happened to fire
# first. The rule now lives in shared/frontend/onboarding_queue.js and this
# holds the three callers to it.
#
# Read as text, like the rest of RAILS/test — no Rails boot.
class OnboardingPromptOrderTest < Minitest::Test
  # Overridable so this test can be run against a mutated copy of the five files
  # it reads, and shown to fail. Checking it in place would mean writing to
  # source in a checkout several agents share. Unset in every normal run.
  ROOT = ENV.fetch("ONBOARDING_TEST_ROOT", File.expand_path("..", __dir__))
  QUEUE = File.join(ROOT, "shared/frontend/onboarding_queue.js")
  BASELINE = File.join(ROOT, "shared/config/importmap_baseline.rb")

  # kind => the file that decides whether that prompt appears.
  #
  # This list is the gate. A fourth onboarding interruption added without a row
  # here is exactly the failure the queue exists to prevent, so adding one means
  # adding it here and giving it a threshold.
  PROMPTS = {
    "menu_coach" => "shared/frontend/scroll_chrome_controller.js",
    "push" => "brgen/app/javascript/controllers/push_controller.js",
  }.freeze

  INSTALL = "shared/frontend/install_prompt_controller.js"
  WELCOME = "shared/frontend/welcome_onboarding_controller.js"
  WELCOME_VIEW = "shared/app/views/shared/_welcome_onboarding.html.erb"
  ARTWORK = "shared/app/services/shared/onboarding_artwork.rb"

  def queue = @queue ||= File.read(QUEUE)

  def test_the_queue_is_pinned_or_no_caller_can_import_it
    assert_path_exists QUEUE
    assert_includes File.read(BASELINE), %(pin "pub4/onboarding", to: "onboarding_queue.js"),
                    "pub4/onboarding must be pinned in the shared baseline, or every import of it 404s"
  end

  def test_welcome_is_first_and_later_prompts_wait
    thresholds = queue.scan(/^\s{2}(\w+):\s*(\d+),/).to_h { |name, n| [name, n.to_i] }
    refute_empty thresholds, "MIN_SESSIONS did not parse — this test is measuring nothing"

    assert_equal thresholds.fetch("welcome"), thresholds.fetch("install")
    install = thresholds.fetch("install")
    PROMPTS.each_key do |kind|
      assert_operator thresholds.fetch(kind), :>, install,
                      "#{kind} must wait longer than the install prompt"
    end
  end

  def test_every_deferred_prompt_asks_the_queue_first
    PROMPTS.each do |kind, relative|
      body = File.read(File.join(ROOT, relative))
      assert_includes body, %(from "pub4/onboarding"), "#{relative} does not import the queue"
      assert_includes body, %(mayPrompt("#{kind}")),
                      "#{relative} must gate on mayPrompt(\"#{kind}\") before revealing"
    end
  end

  # Install can appear at any moment — the visitor posts, plays a track, sends a
  # message — so a threshold alone would still let a lower prompt sit on top of
  # one that arrived after it.
  def test_welcome_blocks_install_and_later_prompts
    welcome = File.read(File.join(ROOT, WELCOME))
    view = File.read(File.join(ROOT, WELCOME_VIEW))
    artwork = File.read(File.join(ROOT, ARTWORK))
    install = File.read(File.join(ROOT, INSTALL))

    assert_includes view, %(data-controller="welcome-onboarding")
    assert_includes view, "OnboardingArtwork.url"
    assert_includes view, "image_tag"
    assert_includes artwork, "REPLICATE_API_TOKEN"
    assert_includes welcome, %(mayPrompt("welcome"))
    assert_includes welcome, "setWelcomePending"
    assert_includes install, %(mayPrompt("install"))
    assert_includes install, "pub4:cookie-consent-resolved"
    assert_includes install, "pub4:welcome-dismissed"
  end

  def test_install_announces_and_the_others_step_back
    assert_includes File.read(File.join(ROOT, INSTALL)), "announceInstallVisible()",
                    "the install prompt must announce itself when it reveals"

    PROMPTS.each_value do |relative|
      assert_includes File.read(File.join(ROOT, relative)), "YIELD_EVENT",
                      "#{relative} must listen for the install prompt taking the screen"
    end
  end

  # A check whose pattern matches nothing passes for the wrong reason. Every
  # assertion above is a substring search, so the one failure mode they share is
  # searching a file that has moved.
  def test_the_files_this_asserts_against_exist
    ([INSTALL, WELCOME, WELCOME_VIEW, ARTWORK] + PROMPTS.values).each do |relative|
      assert_path_exists File.join(ROOT, relative)
    end
  end

  def test_install_does_not_wait_for_chrome_or_a_post
    body = File.read(File.join(ROOT, INSTALL))

    refute_match(/install-prompt-value/, body,
                 "a first visit that only reads must still be able to install")
    assert_includes body, "beforeinstallprompt"
    assert_includes body, "pointer: coarse"
    assert_includes body, "this.phone()"
  end
end