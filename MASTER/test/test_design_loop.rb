# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"
require_relative "../lib/fix/design_loop"

class TestDesignLoop < Minitest::Test
  Surface = Struct.new(:id, :app, :label, :host, :path)
  EDIT = Master::Fix::DesignEdit
  LOOP = Master::Fix::DesignLoop
  SCALE = [0.0, 4.0, 8.0, 16.0].freeze
  FILLER = (1..9).map { |n| ".filler-#{n}" }.freeze

  def with_sheet(css = ".card {\n  padding: 4px;\n  color: #111;\n}\n")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "app.scss")
      File.write(path, css)
      yield path
    end
  end

  def reply(path, find:, replace:, why: "more room")
    JSON.generate("file" => path, "find" => find, "replace" => replace, "why" => why)
  end

  def parse(path, find:, replace:, **rules)
    EDIT.parse(reply(path, find:, replace:), allowed: [path], rules: EDIT::Rules.new(guard: nil, scale: nil, **rules))
  end

  def refused(edit) = assert_raises(EDIT::Refused) { edit.check! }.message

  def test_an_edit_to_spacing_is_applied_and_undone
    with_sheet do |path|
      edit = parse(path, find: "padding: 4px;", replace: "padding: 16px;")
      original = edit.apply!

      assert_includes File.read(path), "padding: 16px;"
      edit.restore(original)
      assert_includes File.read(path), "padding: 4px;"
    end
  end

  def test_rendered_values_are_refused_whatever_the_model_asks
    with_sheet do |path|
      assert_match(/rendered value/, refused(parse(path, find: "color: #111;", replace: "color: #f00;")))
      swapped = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n  background: blue;")

      assert_match(/rendered value/, refused(swapped))
    end
  end

  def test_font_shadow_important_repeats_and_missing_text_are_refused
    with_sheet(".a {\n  gap: 4px;\n  gap: 4px;\n}\n") do |path|
      assert_match(/occurs 2 times/, refused(parse(path, find: "gap: 4px;", replace: "gap: 8px;")))
      assert_match(/occurs 0 times/, refused(parse(path, find: "nothing here", replace: "x")))
      forbidden = [".a {\n  font-size: 20px;", ".a {\n  box-shadow: 0 0 4px #000;", ".a {\n  margin: 0 !important;"]
      forbidden.each do |replace|
        assert_raises(EDIT::Refused) { parse(path, find: ".a {", replace:).apply! }
      end
    end
  end

  def test_a_rule_rewritten_onto_one_line_may_keep_its_colour
    css = ".empty {\n  color: var(--text-secondary);\n  padding: 32px 12px;\n}\n"
    with_sheet(css) do |path|
      replace = ".empty { color: var(--text-secondary); padding: 48px 16px; max-inline-size: 66ch; }"
      parse(path, find: css.strip, replace:).apply!

      assert_includes File.read(path), "padding: 48px 16px"
    end
  end

  def test_changing_the_colour_inside_a_one_line_rule_is_refused
    css = ".empty { color: red; padding: 4px; }\n"
    with_sheet(css) do |path|
      edit = parse(path, find: css.strip, replace: ".empty { color: blue; padding: 4px; }")

      assert_raises(EDIT::Refused) { edit.apply! }
    end
  end

  # RENDERED_VALUES in laws.yml names layout constants: the token files stay the operator's.
  def test_token_files_are_never_edited
    Dir.mktmpdir do |dir|
      path = File.join(dir, "_tokens.scss")
      File.write(path, ":root {\n  --space-3: 12px;\n}\n")

      assert_match(/operator-owned/, refused(parse(path, find: "--space-3: 12px;", replace: "--space-3: 16px;")))
    end
  end

  def test_spacing_must_sit_on_the_declared_scale
    with_sheet do |path|
      off = parse(path, find: "padding: 4px;", replace: "padding: 13px;", scale: SCALE)
      on = parse(path, find: "padding: 4px;", replace: "padding: 1rem;", scale: SCALE)

      assert_match(/off the declared spacing scale/, refused(off))
      assert on.check!
    end
  end

  def test_the_mechanical_laws_can_refuse_the_file_as_it_would_be_written
    with_sheet do |path|
      seen = nil
      guard = ->(file, text) { (seen = [file, text]) && "NO_DECORATIVE_FX: gradient" }
      rules = EDIT::Rules.new(guard:, scale: nil)
      edit = EDIT.parse(reply(path, find: "padding: 4px;", replace: "padding: 16px;"), allowed: [path], rules:)

      assert_match(/the laws refuse it: NO_DECORATIVE_FX/, refused(edit))
      assert_includes seen.last, "padding: 16px;"
      assert_includes File.read(path), "padding: 4px;"
    end
  end

  # `main > h1 ~ *` once reached every page of an app and was kept because few pages were re-measured.
  def test_a_new_rule_must_name_a_class_or_id
    with_sheet do |path|
      universal = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n}\nmain > h1 ~ * {\n  margin: 8px;")
      element_only = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n}\nh2 {\n  margin: 8px;")
      named = parse(path, find: "padding: 4px;", replace: "padding: 4px;\n}\n.card .title {\n  margin: 8px;")

      assert_match(/across the whole app/, refused(universal))
      assert_match(/across the whole app/, refused(element_only))
      assert named.check!
    end
  end

  def test_a_file_that_was_not_offered_is_refused
    with_sheet do |path|
      edit = EDIT.parse(reply("/etc/passwd", find: "a", replace: "b"), allowed: [path])

      assert_match(/not one of the offered/, refused(edit))
    end
  end

  # A fake world: padding 4px scores 40 on the home surface and 16px scores 60; others stay 50.
  def fake_score(surface, wide:, other_drop:, flat:)
    return(wide && !flat ? 60.0 : 40.0) if surface.id == "brgen/home"

    wide ? 50.0 - other_drop : 50.0
  end

  def screenshot(path, surface)
    shot = File.join(File.dirname(path), "#{surface.id.tr('/', '_')}.png")
    File.write(shot, "png")
    shot
  end

  NO_DIFFERENCE = '{"better":"same","why":"no difference"}'

  # options: other_drop (score lost elsewhere), flat (score never moves), vision (the check's reply),
  # classes (what is on the page), built (collects the apps whose CSS was rebuilt), seen (collects
  # the surface ids of each measurement), prompts (collects what the model was asked).
  def world_for(path, committed:, **options)
    drop = options.fetch(:other_drop, 0)
    flat = options.fetch(:flat, false)
    vision = options.fetch(:vision, NO_DIFFERENCE)
    built = options.fetch(:built, [])
    seen = options.fetch(:seen, [])
    prompts = options.fetch(:prompts, [])
    elements = options.fetch(:classes, FILLER + [".card"]).map { |key| { "key" => "body>main>#{key}" } }
    measure = lambda do |surfaces|
      seen << surfaces.map(&:id)
      wide = File.read(path).include?("padding: 16px")
      surfaces.map do |surface|
        payload = { "score" => fake_score(surface, wide:, other_drop: drop, flat:), "elements" => elements }
        [surface, payload, screenshot(path, surface)]
      end
    end
    edit = reply(path, find: "padding: 4px;", replace: "padding: 16px;")
    LOOP::World.new(
      measure:, ask: ->(prompt, _images) { (prompts << prompt) && prompt.include?("Two renders") ? vision : edit },
      build: ->(app) { built << app && true }, commit_file: ->(file, message) { committed << [file, message] },
      sources_for: ->(_surface) { [path] }, guard: nil
    )
  end

  HOME_AND_FEED = [Surface.new("brgen/home", "brgen"), Surface.new("brgen/feed", "brgen")].freeze

  # world: what world_for takes, and surfaces (the surfaces the run measures).
  def loop_for(path, committed:, **world)
    surfaces = world.delete(:surfaces) || HOME_AND_FEED
    plan = LOOP::Plan.new(surfaces:, root: Dir.pwd, rounds: 3, candidates: 1)
    LOOP.new(plan:, world: world_for(path, committed:, **world))
  end

  def stub_scoring(&block)
    store = Master::Fix::LayoutScoreStore
    result = Struct.new(:score, :subs)
    store.stub(:measure, ->(_root, payload) { result.new(payload["score"], { "alignment" => 0.5 }) }) do
      Master::Fix::VisualQualityChecks.stub(:measure, ->(_surface, _payload) { { "offenders" => {} } }, &block)
    end
  end

  def test_an_edit_that_raises_the_score_is_kept_and_committed
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:).run

        assert_equal :kept, rounds.first.outcome
        assert_includes File.read(path), "padding: 16px;"
        assert_equal [path], committed.map(&:first)
        assert_match(/layout score 40\.0 -> 60\.0/, committed.first.last)
      end
    end
  end

  def test_an_edit_that_hurts_another_surface_is_undone_and_not_committed
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, other_drop: 5).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end
  # The score can sit flat while a person sees a better page, so a vision check decides then.
  def test_a_flat_score_is_kept_when_the_vision_check_says_the_new_render_is_better
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, flat: true, vision: '{"better":"B","why":"more room"}').run

        assert_equal :kept, rounds.first.outcome
        assert_equal [path], committed.map(&:first)
      end
    end
  end

  def test_a_flat_score_is_undone_when_the_vision_check_cannot_tell_the_renders_apart
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, flat: true).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end
  # A rule that matches nothing on the page changes nothing either judge can see.
  def test_an_edit_to_a_selector_that_is_not_on_the_page_is_refused_without_a_render
    with_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:, classes: FILLER).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end

  # A second capture of the target that differs by 15 means a gain of 20 is within the noise.
  def test_a_gain_smaller_than_twice_the_measured_noise_is_not_kept
    with_sheet do |path|
      committed = []
      stub_scoring do
        world = world_for(path, committed:)
        calls = 0
        inner = world.measure
        noisy = lambda do |surfaces|
          calls += 1
          rows = inner.call(surfaces)
          calls == 3 ? rows.map { |s, payload, shot| [s, payload.merge("score" => payload["score"] + 15), shot] } : rows
        end
        plan = LOOP::Plan.new(surfaces: [Surface.new("brgen/home", "brgen")], root: Dir.pwd, rounds: 1, candidates: 1)
        rounds = LOOP.new(plan:, world: world.with(measure: noisy)).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_empty committed
      end
    end
  end

  def test_the_selector_of_the_rule_an_edit_sits_in_is_read_from_the_file
    with_sheet(".a, .b > .c { gap: 4px; }\n.d {\n  padding: 4px;\n}\n") do |path|
      assert_equal %w[.d], parse(path, find: "padding: 4px;", replace: "padding: 8px;").selector_tokens
      assert_equal %w[.a .b .c], parse(path, find: "gap: 4px;", replace: "gap: 8px;").selector_tokens
    end
  end

  # font-size is the one font property the loop may set, on a declared step and never smaller.
  def test_a_font_size_takes_only_a_declared_step_and_never_shrinks
    steps = [16.0, 20.0, 24.0]
    with_sheet(".a {\n  gap: 8px;\n}\n") do |path|
      add = ->(size, **rules) { parse(path, find: "gap: 8px;", replace: "gap: 8px;\n  font-size: #{size};", **rules) }

      assert add.("20px", type_scale: steps).check!
      assert add.("1.25rem", type_scale: steps).check!
      assert_match(/not a declared text size/, refused(add.("18px", type_scale: steps)))
      assert_match(/not a declared text size/, refused(add.("clamp(1rem, 2vw, 2rem)", type_scale: steps)))
      assert_match(/not a declared text size/, refused(add.("20px")))
    end
    with_sheet(".a {\n  font-size: 24px;\n}\n") do |path|
      shrunk = parse(path, find: "font-size: 24px;", replace: "font-size: 16px;", type_scale: steps)

      assert_match(/smaller than 24px/, refused(shrunk))
    end
  end

  def test_the_rest_of_the_font_stays_with_the_operator
    with_sheet(".a {\n  gap: 8px;\n}\n") do |path|
      ["font-weight: 700;", "font-family: serif;", "font: 20px/1.2 sans-serif;", "font-size-adjust: 0.5;"].each do |declaration|
        edit = parse(path, find: "gap: 8px;", replace: "gap: 8px;\n  #{declaration}", type_scale: [20.0])

        assert_match(/rendered value/, refused(edit))
      end
    end
  end

  def with_shared_sheet
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "RAILS", "__shared"))
      path = File.join(dir, "RAILS", "__shared", "app.scss")
      File.write(path, ".card {\n  padding: 4px;\n  color: #111;\n}\n")
      yield path
    end
  end

  # A shared stylesheet reaches every app, so a run that measures one app cannot judge an edit to it.
  def test_a_shared_stylesheet_is_refused_when_the_run_measures_one_app
    with_shared_sheet do |path|
      committed = []
      stub_scoring do
        rounds = loop_for(path, committed:).run

        assert_empty rounds.select { |round| round.outcome == :kept }
        assert_includes File.read(path), "padding: 4px;"
        assert_empty committed
      end
    end
  end

  def test_a_shared_stylesheet_edit_is_rebuilt_for_every_measured_app
    with_shared_sheet do |path|
      committed = []
      built = []
      surfaces = [Surface.new("brgen/home", "brgen"), Surface.new("amber/home", "amber")]
      stub_scoring do
        rounds = loop_for(path, committed:, surfaces:, built:).run

        assert_equal :kept, rounds.first.outcome
        assert_equal %w[amber brgen], built.uniq.sort
      end
    end
  end

  def test_every_measured_app_is_guarded_however_many_surfaces_another_app_has
    with_sheet do |path|
      committed = []
      seen = []
      surfaces = %w[home a b c d e f].map { |name| Surface.new("brgen/#{name}", "brgen") } + [Surface.new("amber/home", "amber")]
      stub_scoring do
        loop_for(path, committed:, surfaces:, seen:).run

        assert_includes seen[1], "amber/home"
      end
    end
  end
  # The loop holds a surface to the direction the /fix critic and fixer already use, not a second copy.
  def test_the_edit_request_carries_the_design_layer_brief_and_the_house_typeface_rule
    with_sheet do |path|
      prompts = []
      surfaces = [Surface.new("amber/wardrobe", "amber", "wardrobe", nil, "/wardrobe"), Surface.new("amber/feed", "amber", "feed", nil, "/feed")]
      stub_scoring do
        loop_for(path, committed: [], surfaces:, prompts:).run
      end
      request = prompts.find { |text| text.include?("Make ONE edit") }

      assert_includes request, "Flat, brutalist, Swiss"
      assert_includes request, "aesthetic_direction=editorial_wardrobe"
      assert_includes request, Master::Design::Typeface::HOUSE_RULE
      assert_match(/font-size/, request)
    end
  end
end
