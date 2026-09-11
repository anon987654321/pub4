# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "support/method_swap"
require_relative "../gates/lib/live/human_walkthrough"
require_relative "../gates/lib/live/first_screen"

# human_walkthrough and first_screen each read a marker out of a view or a
# stylesheet. Neither had a test, so neither had ever been shown to fail: a
# marker list that nothing can break is the decorative _tab_bar.html.erb entry
# the gate's own comment records, one level up.
#
# Every defect below is planted into a tree built for the purpose. The live half
# of both gates is held off with a closed port, deliberately — see the last two
# tests, which are about what the gates claim when nothing is listening.
class WalkthroughGatesTest < Minitest::Test
  include MethodSwap

  # Every marker either app's nav table looks for, in one string. The tables
  # accept a Norwegian i18n key or an English literal; keys are what this tree
  # writes, because the apps default to :nb and a literal would be the defect.
  NAV = <<~ERB
    <a href="#main-content"><%= t("a11y.skip_to_content") %></a>
    <%= form_with url: global_search_path do |f| %><% end %>
    <nav>
      <%= link_to t("nav.home"), root_path %>
      <%= link_to t("nav.explore"), explore_path %>
      <%= link_to t("nav.search"), search_path %>
      <%= link_to t("nav.messages"), messages_path %>
      <%= link_to t("nav.nearby"), nearby_path %>
      <%= link_to t("a11y.ai_assistant"), ai_path %>
      <%= link_to t("nav.ports"), ports_path %>
      <%= link_to t("nav.categories"), categories_path %>
      <%= link_to t("nav.maintainers"), maintainers_path %>
      <%= link_to t("nav.sign_in"), new_session_path %>
      <%= link_to t("nav.sign_up"), new_registration_path %>
    </nav>
    <main id="main-content"></main>
  ERB

  HOME = "<section data-visitor-orientation=\"true\"></section>\n"

  def walkthrough_tree
    {
      "amber/app/views/layouts/application.html.erb" => NAV,
      "amber/app/views/home/index.html.erb" => HOME,
      "amber/app/views/shared/_sidebar_nav.html.erb" => NAV,
      "brgen/app/views/layouts/application.html.erb" => NAV,
      "brgen/app/views/home/index.html.erb" => HOME,
      "bsdports/app/views/layouts/application.html.erb" => NAV,
      "bsdports/app/views/ports/index.html.erb" => HOME,
    }
  end

  # first_screen's source half is the touch floor: one token, read out of one
  # stylesheet, and every sheet that spells min-height: var(--tap-min) leans on
  # the number it resolves to.
  def first_screen_tree(tap_min: "44px")
    sheets = %w[
      brgen/app/assets/stylesheets/_nav.scss
      brgen/app/assets/stylesheets/_marketplace.scss
      brgen/app/assets/stylesheets/_marketplace_cards.scss
      amber/app/assets/stylesheets/_items.scss
      bsdports/app/assets/stylesheets/application.scss
      shared/app/assets/stylesheets/_search_yep.scss
    ].to_h { |rel| [rel, ".target { min-height: var(--tap-min); }\n.deal-card { --font: 1rem; }\n.search { color: red; }\n"] }
    sheets.merge("shared/app/assets/stylesheets/_dialect_tokens.scss" => ":root { --tap-min: #{tap_min}; }\n")
  end

  def gate(klass, files)
    Dir.mktmpdir("gate-walkthrough") do |dir|
      files.each do |rel, body|
        path = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end
      swap_value(CrawlSupport, :port_open?, false) do
        return klass.run(rails_root: dir)
      end
    end
  end

  def assert_names(result, pattern)
    assert result.failures.any? { |f| f.match?(pattern) },
           "no failure matched #{pattern.inspect}; got:\n  #{result.failures.join("\n  ")}"
  end

  def test_human_walkthrough_passes_over_a_tree_that_carries_every_marker
    result = gate(Deploy::HumanWalkthroughGate, walkthrough_tree)

    assert_empty result.failures
  end

  def test_human_walkthrough_fails_when_a_layout_loses_the_skip_link
    tree = walkthrough_tree
    tree["bsdports/app/views/layouts/application.html.erb"] = NAV.sub('href="#main-content"', 'href="/"')

    assert_names gate(Deploy::HumanWalkthroughGate, tree), /bsdports: layout needs skip link to main content/
  end

  def test_human_walkthrough_fails_when_a_layout_loses_the_main_landmark
    tree = walkthrough_tree
    tree["amber/app/views/layouts/application.html.erb"] = NAV.sub('id="main-content"', 'id="content"')
    result = gate(Deploy::HumanWalkthroughGate, tree)

    assert_names result, /amber: layout needs main-content landmark/
  end

  # The visitor-orientation marker is the one thing the home page owes a first
  # visitor, and it is the only check reading the home template at all.
  def test_human_walkthrough_fails_when_the_home_page_loses_its_orientation_marker
    tree = walkthrough_tree
    tree["brgen/app/views/home/index.html.erb"] = "<section></section>\n"

    assert_names gate(Deploy::HumanWalkthroughGate, tree), /brgen: home needs data-visitor-orientation marker/
  end

  # An English literal where a key belongs is a defect, not a placeholder, so
  # dropping the key must fire even though the app is not booted.
  def test_human_walkthrough_fails_when_a_nav_label_key_disappears
    tree = walkthrough_tree
    tree.each_key do |rel|
      tree[rel] = tree[rel].sub(/^.*nav\.sign_in.*\n/, "") if rel.start_with?("bsdports/")
    end

    assert_names gate(Deploy::HumanWalkthroughGate, tree), /bsdports: primary visitor nav missing Sign in/
  end

  # The check that exists because a listed partial which does not exist reads as
  # an empty file, and an empty file passes every pattern match against it.
  def test_human_walkthrough_fails_when_a_listed_nav_partial_does_not_exist
    tree = walkthrough_tree.reject { |rel, _| rel.end_with?("_sidebar_nav.html.erb") }

    assert_names gate(Deploy::HumanWalkthroughGate, tree), %r{amber: nav_partials names .*_sidebar_nav\.html\.erb}
  end

  def test_human_walkthrough_fails_when_brgens_sidebar_search_loses_its_action
    tree = walkthrough_tree
    tree["brgen/app/views/layouts/application.html.erb"] = NAV.sub("global_search_path", "root_path")

    assert_names gate(Deploy::HumanWalkthroughGate, tree), /brgen: sidebar search must submit to global_search_path/
  end

  def test_first_screen_passes_over_a_tree_that_declares_a_44px_touch_floor
    result = gate(Deploy::FirstScreenGate, first_screen_tree)

    assert_empty result.failures
  end

  # The gate's own header records it measuring a spelling rather than a
  # geometry once already. A token that resolves below the Fitts floor is the
  # defect that survived that, and it must fire.
  def test_first_screen_fails_when_the_tap_token_drops_below_the_fitts_floor
    result = gate(Deploy::FirstScreenGate, first_screen_tree(tap_min: "30px"))

    assert_names result, /--tap-min is 30px, below the 44px Fitts floor/
  end

  def test_first_screen_fails_when_the_token_file_declares_no_tap_minimum
    tree = first_screen_tree
    tree["shared/app/assets/stylesheets/_dialect_tokens.scss"] = ":root { --font: 1rem; }\n"

    assert_names gate(Deploy::FirstScreenGate, tree), /declares no --tap-min/
  end

  def test_first_screen_fails_when_a_sheet_stops_declaring_a_touch_target
    tree = first_screen_tree
    tree["amber/app/assets/stylesheets/_items.scss"] = ".target { height: 30px; }\n"

    assert_names gate(Deploy::FirstScreenGate, tree), %r{amber/app/assets/stylesheets/_items\.scss missing}
  end

  def test_first_screen_fails_when_the_token_file_is_deleted
    tree = first_screen_tree.reject { |rel, _| rel.end_with?("_dialect_tokens.scss") }

    assert_names gate(Deploy::FirstScreenGate, tree), /--tap-min is unreadable/
  end

  # The third state, for the two gates that have a live half and no browser.
  #
  # Neither goes inconclusive with nothing listening, and that is correct in the
  # letter: both measured their source half. But the pass line each prints —
  # "Human walkthrough gate passed for 3 Rails apps", "ok: first-screen markers
  # present" — describes the half that did not run. So what is pinned here is
  # the only thing standing between that line and a silent false green: every
  # skipped surface is named, and the count of skips is not zero.
  def test_human_walkthrough_names_every_app_it_could_not_walk
    result = gate(Deploy::HumanWalkthroughGate, walkthrough_tree)

    assert_equal 3, result.unchecked.size, "one reason per app, or a parked app speaks for none"
    %w[brgen amber bsdports].each do |app|
      assert result.unchecked.any? { |r| r.start_with?("#{app}: live walkthrough not run") },
             "#{app} was not named among #{result.unchecked.inspect}"
    end
    refute_predicate result, :conclusive?, "a gate whose live half never ran has not checked everything"
  end

  def test_first_screen_names_every_surface_it_could_not_fetch
    result = gate(Deploy::FirstScreenGate, first_screen_tree)

    assert_operator result.live_skips, :>, 0
    assert_equal result.live_skips, result.warnings.count { |w| w.include?("skipped (port") },
                 "every live skip must be named, or the pass line covers for surfaces nobody fetched"
  end

  # GATE_REQUIRE_LIVE exists for the run that means to measure the live half.
  # Without it the skips are warnings; with it they must block, or booting the
  # fleet buys nothing.
  def test_a_run_that_requires_live_fails_on_the_skips_instead_of_warning
    was = ENV["GATE_REQUIRE_LIVE"]
    ENV["GATE_REQUIRE_LIVE"] = "1"
    result = gate(Deploy::FirstScreenGate, first_screen_tree)

    assert_names result, /\[live-required\] first_screen:/
  ensure
    ENV["GATE_REQUIRE_LIVE"] = was
  end
end
