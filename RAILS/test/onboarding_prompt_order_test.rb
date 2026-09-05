# frozen_string_literal: true

require "minitest/autorun"

# The install prompt comes first, always; the menu coach and the push button
# wait until the visitor is familiar with the app and never open over it.
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

  def queue = @queue ||= File.read(QUEUE)

  def test_the_queue_is_pinned_or_no_caller_can_import_it
    assert_path_exists QUEUE
    assert_includes File.read(BASELINE), %(pin "pub4/onboarding", to: "onboarding_queue.js"),
                    "pub4/onboarding must be pinned in the shared baseline, or every import of it 404s"
  end

  def test_install_outranks_everything_else
    thresholds = queue.scan(/^\s{2}(\w+):\s*(\d+),/).to_h { |name, n| [name, n.to_i] }
    refute_empty thresholds, "MIN_SESSIONS did not parse — this test is measuring nothing"

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
    ([INSTALL] + PROMPTS.values).each do |relative|
      assert_path_exists File.join(ROOT, relative)
    end
  end

  def test_install_does_not_wait_for_a_post
    body = File.read(File.join(ROOT, INSTALL))

    refute_match(/install-prompt-value/, body,
                 "a first visit that only reads must still be able to install")
    assert_includes body, "beforeinstallprompt"
    assert_includes body, "iosManual"
  end
end
