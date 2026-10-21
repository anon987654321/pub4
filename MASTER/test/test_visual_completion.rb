# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/visual_completion"
require_relative "../lib/fix/visual_custody_blocking"
require_relative "../lib/fix/visual_quality_gates"
require_relative "../lib/fix/transaction"
require_relative "../gates/support/geometry_probe"

class TestVisualCompletion < Minitest::Test
  class AuthorizedCustody
    def layout_completion? = true
  end

  class OrdinaryCustody
    def layout_completion? = false
  end

  def repo = Master::REPO_ROOT

  def test_campaign_is_limited_to_rails_apps_and_excludes_master
    completion = Master::Fix::VisualCompletion

    assert completion.enabled_for_target?(root: repo, target: "RAILS")
    refute completion.enabled_for_target?(root: repo, target: "RAILS/brgen"), "multi-app campaign requires the full Rails target"
    refute completion.enabled_for_target?(root: repo, target: "RAILS/master")
    refute completion.enabled_for_target?(root: repo, target: "OPENBSD")
    refute completion.enabled_for_path?(root: repo, path: File.join(repo, "RAILS/master/public/face.css"))
    refute completion.enabled_for_path?(root: repo, path: File.join(repo, "RAILS/brgen/app/models/post.rb"))
    refute completion.enabled_for_path?(root: repo, path: File.join(repo, "RAILS/__shared/app/assets/stylesheets/_dialect_tokens.scss"))
  end

  def test_reflow_gate_covers_core_mobile_tablet_and_desktop_widths
    required = [320, 360, 375, 390, 430, 480, 640, 768, 1024, 1280]

    assert_empty required - Deploy::GeometryProbe.reflow_widths
  end

  def test_only_bounded_layout_rules_bypass_operator_owned_visual_decisions
    path = File.join(repo, "RAILS/brgen/app/assets/stylesheets/application.scss")
    blocking = Master::Fix::VisualCustodyBlocking

    assert_nil blocking.gap_for("TYPE_SCALE", root: repo, path:, custody: AuthorizedCustody.new)
    assert_nil blocking.gap_for("LEADING", root: repo, path:, custody: AuthorizedCustody.new)
    assert_equal Master::Gap::OPERATOR_DECISION,
                 blocking.gap_for("TYPE_SCALE", root: repo, path:, custody: OrdinaryCustody.new)
    assert_equal Master::Gap::OPERATOR_DECISION,
                 blocking.gap_for("COLOR_CONTRAST", root: repo, path:, custody: AuthorizedCustody.new)
    assert_equal Master::Gap::OPERATOR_DECISION,
                 blocking.gap_for("TYPE_SCALE", root: repo, path: File.join(repo, "RAILS/master/public/face.css"),
                                  custody: AuthorizedCustody.new)
  end

  def test_completion_prompt_preserves_product_identity_and_requires_live_evidence
    path = File.join(repo, "RAILS/brgen/app/views/home/index.html.erb")
    prompt = Master::Fix::VisualCompletion.prompt_context(root: repo, path:, custody: AuthorizedCustody.new)

    assert_includes prompt, "finish incomplete Rails layouts professionally"
    assert_includes prompt, "Preserve each application's existing product dialect"
    assert_includes prompt, "canonical token edits"
    assert_includes prompt, "live Chrome/CDP measurements before and after"
    assert_includes prompt, "INCONCLUSIVE"
    assert_empty Master::Fix::VisualCompletion.prompt_context(root: repo, path:, custody: OrdinaryCustody.new)
  end

  def test_visual_completion_refuses_palette_font_and_canonical_token_changes
    completion = Master::Fix::VisualCompletion
    path = File.join(repo, "RAILS/brgen/app/assets/stylesheets/application.scss")
    custody = AuthorizedCustody.new
    original = ".card { gap: 8px; color: var(--text); font-family: 'Inter', sans-serif; }\\n"

    layout_change = ".card { gap: 16px; color: var(--text); font-family: 'Inter', sans-serif; }\\n"
    colour_change = ".card { gap: 16px; color: var(--muted); font-family: 'Inter', sans-serif; }\\n"
    font_change = ".card { gap: 16px; color: var(--text); font-family: 'Arial', sans-serif; }\\n"

    assert_nil completion.change_blocker(root: repo, path:, before: original, after: layout_change, custody:)
    assert_match(/palette\\/semantic colours/, completion.change_blocker(root: repo, path:, before: original, after: colour_change, custody:))
    assert_match(/font-family/, completion.change_blocker(root: repo, path:, before: original, after: font_change, custody:))

    tokens = File.join(repo, "RAILS/__shared/app/assets/stylesheets/_dialect_tokens.scss")
    assert_match(/canonical visual tokens/, completion.change_blocker(root: repo, path: tokens, before: "$space: 8px;", after: "$space: 16px;", custody:))
  end

  def test_layout_completion_ignores_only_geometry_shift_not_quality_regressions
    before = {
      "metrics" => { "layout_shift" => 0.0, "overflow" => 0 },
      "offenders" => { "layout_shift" => [], "overflow" => [] },
    }
    after = {
      "metrics" => { "layout_shift" => 1.5, "overflow" => 1 },
      "offenders" => { "layout_shift" => [], "overflow" => ["#main"] },
    }

    allowed = Master::Fix::VisualQualityGates.worse(before, after, allow_layout_change: true)
    ordinary = Master::Fix::VisualQualityGates.worse(before, after)

    assert_equal 1, allowed.size
    assert_match(/overflow/, allowed.first)
    refute allowed.any? { |finding| finding.include?("layout_shift") }
    assert_equal 2, ordinary.size
  end

  def test_related_snapshot_enlistment_rolls_back_with_the_fix_transaction
    Dir.mktmpdir("master-layout-transaction") do |root|
      source = File.join(root, "RAILS", "layout.scss")
      snapshot = File.join(root, "MASTER", "gates", "data", "layout_snapshots", "app-home-mobile.json")
      FileUtils.mkdir_p(File.dirname(source))
      FileUtils.mkdir_p(File.dirname(snapshot))
      File.write(source, ".page { display: block; }\n")
      original = "{\"title\":\"before\"}\n"
      File.write(snapshot, original)

      transaction = Master::Fix::Transaction.new(root:, paths: ["RAILS/layout.scss"], id: "visual-layout-test")
      transaction.begin!
      enlisted = transaction.enlist!(["MASTER/gates/data/layout_snapshots/app-home-mobile.json"])
      assert_predicate enlisted, :ok?

      File.write(snapshot, "{\"title\":\"after\"}\n")
      observed = transaction.observe_paths!(["MASTER/gates/data/layout_snapshots/app-home-mobile.json"])
      assert_predicate observed, :ok?

      rolled_back = transaction.rollback!

      assert_predicate rolled_back, :ok?
      assert_equal original, File.read(snapshot)
      assert_equal ".page { display: block; }\n", File.read(source)
    end
  end
end
