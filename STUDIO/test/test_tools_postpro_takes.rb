# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "tools_helper"
ToolTest::Tools.load_tool("postpro/postpro.rb")
require_relative "postpro_fixtures"

# A take is named for its place in the run, its look and its dealt lane.
class TestPostproTakeNames < Minitest::Test
  include PostproFixtures

  def test_a_take_is_named_by_number_look_and_dealt_lane
    take = RandomTake.new(number: 3, look: :neon_night, lane: :bleeding_edge_analog)
    assert_equal "03_neon_night_bleeding_edge_analog", label(take)
  end

  def test_take_numbers_are_zero_padded_so_names_sort_in_draw_order
    labels = [1, 2, 10].map { |number| label(random_take(number)) }
    assert_equal labels, labels.sort
    assert labels.first.start_with?("01_")
  end

  def test_the_dealt_lane_wins_over_the_inferred_one
    dealt = (HEAVY_LANE_DEAL.uniq - [send(:random_chain_lane, CHAIN)]).first
    assert label(random_take(1, lane: dealt)).end_with?(dealt.to_s)
  end

  def test_without_a_lane_the_chain_lane_is_inferred
    inferred = send(:random_chain_lane, CHAIN).to_s
    assert label(random_take(1, lane: nil)).end_with?(inferred)
  end

  def test_without_a_look_the_name_skips_it
    assert_equal "02_subtle_analog", label(random_take(2, look: nil))
  end

  def test_without_a_take_the_chain_stays_in_the_name
    assert_includes label, "film_curve-halation-grain"
  end

  def test_takes_of_one_family_never_share_a_name
    labels = (1..RANDOM_TAKES).map { |number| label(random_take(number)) }
    assert_equal labels.uniq, labels
  end

  def test_a_take_name_carries_no_path_separator_or_space
    HEAVY_LOOKS.each do |look|
      assert_match(/\A[0-9A-Za-z_-]+\z/, label(random_take(12, look:, lane: :cinematic_color)))
    end
  end
end

# A bare run makes ten light takes and a contact sheet; --heavy builds each take
# on its own named look, within the same strength bands and a step cap.
class TestPostproRunDefaults < Minitest::Test
  include PostproFixtures

  def test_a_run_makes_ten_takes_by_default
    assert_equal 10, RANDOM_TAKES
    assert Postpro::Constitution::DEFAULT_VARIATION_RANGE.cover?(RANDOM_TAKES)
  end

  def test_heavy_mode_is_off_unless_asked_for
    with_env("POSTPRO_HEAVY", nil) { refute send(:heavy_mode?) }
    with_env("POSTPRO_HEAVY", "1") { assert send(:heavy_mode?) }
  end

  def test_there_are_enough_looks_for_ten_different_takes
    assert_operator HEAVY_LOOKS.uniq.size, :>=, RANDOM_TAKES
    HEAVY_LOOKS.each { |look| assert PRESETS.key?(look), "heavy look #{look} is not a preset" }
  end

  def test_ten_drawn_looks_are_all_different
    rng = Random.new(7)
    looks = RANDOM_TAKES.times.each_with_object([]) { |_draw, drawn| drawn << send(:next_heavy_look, rng, drawn) }
    assert_equal looks.uniq, looks
  end

  def test_the_first_looks_of_a_family_avoid_repeating_a_stock
    rng = Random.new(11)
    stock_count = HEAVY_LOOKS.map { |look| PRESETS.fetch(look)[:stock] }.uniq.size
    looks = stock_count.times.each_with_object([]) { |_draw, drawn| drawn << send(:next_heavy_look, rng, drawn) }
    stocks = looks.map { |look| PRESETS.fetch(look)[:stock] }
    assert_equal stocks.uniq, stocks
  end

  def test_the_lane_deal_spans_subtle_to_bleeding_edge_in_ten_takes
    dealt = (0...RANDOM_TAKES).map { |index| HEAVY_LANE_DEAL[index % HEAVY_LANE_DEAL.size] }
    assert_equal HEAVY_LANE_DEAL.uniq.sort, dealt.uniq.sort
  end

  def test_a_heavy_take_keeps_its_look_and_stays_within_the_step_cap
    with_env("POSTPRO_HEAVY", "1") do
      HEAVY_LOOKS.each_with_index do |look, seed|
        chain = send(:look_led_chain, Random.new(seed), look:)
        steps = chain.map(&:first)
        assert_operator steps.size, :<=, [HEAVY_MAX_STEPS, send(:preset_as_recipe, look).size + 1].max, "#{look}: #{steps.inspect}"
        assert_equal RANDOM_ALWAYS, steps.last, "#{look} must close on one grain pass"
        own = send(:preset_as_recipe, look).map(&:first) - RANDOM_UNCLEAN
        assert_empty own - steps, "#{look} lost one of its own clean steps"
      end
    end
  end

  def test_no_light_take_draws_a_blur_relief_or_artefact
    with_env("POSTPRO_HEAVY", "0") { assert_clean_draws(heavy: false) }
  end

  def test_no_heavy_take_draws_a_blur_relief_or_artefact
    with_env("POSTPRO_HEAVY", "1") { assert_clean_draws(heavy: true) }
  end

  def assert_clean_draws(heavy:)
    20.times do |seed|
      drawn = random_steps(seed, heavy)
      assert_empty drawn & RANDOM_UNCLEAN, "heavy=#{heavy} seed #{seed}: #{drawn.inspect}"
    end
  end

  def test_a_black_and_white_stock_develops_a_monochrome_picture
    developed = send(:film_curve, process_frame, :tri_x, 0.9).cast(:float)
    assert_operator (developed.extract_band(0) - developed.extract_band(2)).abs.max, :<, 1.0
  end

  def random_steps(seed, heavy)
    rng = Random.new(seed)
    chain = heavy ? send(:look_led_chain, rng, look: HEAVY_LOOKS[seed % HEAVY_LOOKS.size]) : send(:random_chain, rng)
    chain.map(&:first)
  end

  def test_heavy_strengths_sit_in_the_light_bands
    with_env("POSTPRO_HEAVY", "1") do
      20.times do |seed|
        numbers = send(:random_chain, Random.new(seed)).filter_map { |_, params| params if params.is_a?(Numeric) }
        assert_operator numbers.max, :<=, RANDOM_LEAD_STRENGTH.last
      end
    end
  end

  def test_strongest_steps_keeps_the_loudest_in_their_drawn_order
    chain = [["a", 0.2], ["b", 0.9], ["c", { "intensity" => 0.5 }], ["d", 0.7]]
    assert_equal %w[b d], send(:strongest_steps, chain, 2).map(&:first)
    assert_equal %w[b c d], send(:strongest_steps, chain, 3).map(&:first)
    assert_empty send(:strongest_steps, chain, 0)
    assert_empty send(:strongest_steps, chain, -2)
  end

  def test_the_contact_sheet_is_on_by_default_and_can_be_switched_off
    with_env("POSTPRO_CONTACT", nil) { assert send(:contact_sheet?) }
    with_env("POSTPRO_CONTACT", "0") { refute send(:contact_sheet?) }
  end
end

# Sidecars carry the take; the contact sheet reads them back.
class TestPostproSidecarsAndContactSheet < Minitest::Test
  include PostproFixtures

  def test_a_chain_sidecar_records_take_look_and_lane
    Dir.mktmpdir do |dir|
      output = File.join(dir, "postpro_frame_04_noir_bleeding_edge_analog_v1.jpg")
      take = RandomTake.new(number: 4, look: :noir, lane: :bleeding_edge_analog)
      send(:write_chain_sidecar, File.join(dir, "frame.jpg"), output, CHAIN, take:)

      data = JSON.parse(File.read("#{output}.json"))
      expected = ["postpro.chain.v1", 4, "noir", "bleeding_edge_analog"]
      assert_equal expected, data.values_at("schema", "take", "look", "lane")
    end
  end

  def test_a_rendered_chain_sidecar_records_checksums_quality_and_uncanny_delta
    Dir.mktmpdir do |dir|
      input = tiny_frame(File.join(dir, "source.jpg"))
      original = Vips::Image.new_from_file(input, access: :random)
      processed = rgb_bands(apply_finishing_grain(anchor_tones(preset(original, :portrait)), :portrait))
      output = File.join(dir, "graded.jpg")
      processed.write_to_file(output, Q: 95)

      send(:write_chain_sidecar, input, output, CHAIN, original:, processed:)
      data = JSON.parse(File.read("#{output}.json"))

      assert_equal Digest::SHA256.file(input).hexdigest, data["input_sha256"]
      assert_equal Digest::SHA256.file(output).hexdigest, data["output_sha256"]
      assert_equal %w[after before], data.fetch("uncanny").keys.sort
      assert data.fetch("quality").key?("warnings") || data.fetch("quality").key?(:warnings)
    end
  end

  def test_a_chain_sidecar_without_a_take_infers_the_lane
    Dir.mktmpdir do |dir|
      output = File.join(dir, "postpro_frame_v1.jpg")
      send(:write_chain_sidecar, File.join(dir, "frame.jpg"), output, CHAIN)

      data = JSON.parse(File.read("#{output}.json"))
      assert_equal [nil, nil, send(:random_chain_lane, CHAIN).to_s], data.values_at("take", "look", "lane")
    end
  end

  def test_family_takes_reads_this_sources_takes_in_draw_order
    Dir.mktmpdir do |dir|
      mine = File.join(dir, "frame.jpg")
      take(mine, number: 2, look: "noir")
      take(mine, number: 1, look: "dream")

      take(File.join(dir, "other.jpg"), number: 1, look: "bleached")
      found = send(:family_takes, mine).map { |entry| entry.values_at(:take, :look) }
      assert_equal [[1, "dream"], [2, "noir"]], found
    end
  end

  def test_family_takes_skips_a_sidecar_whose_picture_is_gone
    Dir.mktmpdir do |dir|
      mine = File.join(dir, "frame.jpg")
      File.delete(take(mine, number: 1, look: "dream"))
      take(mine, number: 2, look: "noir")
      assert_equal [2], send(:family_takes, mine).map { |entry| entry[:take] }
    end
  end

  def test_the_contact_sheet_lands_beside_the_source
    Dir.mktmpdir do |dir|
      mine = tiny_frame(File.join(dir, "frame.jpg"))
      %w[noir dream bleached].each_with_index { |look, index| take(mine, number: index + 1, look:, picture: true) }
      sheet = quietly { send(:write_contact_sheet, mine) }
      assert_equal File.join(dir, "postpro_frame_contact.jpg"), sheet
      assert_operator Vips::Image.new_from_file(sheet).width, :>, 90, "three tiles should sit side by side"
    end
  end

  def test_the_contact_sheet_sidecar_lists_every_take_in_order
    Dir.mktmpdir do |dir|
      mine = tiny_frame(File.join(dir, "frame.jpg"))
      3.times { |index| take(mine, number: index + 1, look: "noir", picture: true) }
      data = JSON.parse(File.read("#{quietly { send(:write_contact_sheet, mine) }}.json"))
      assert_equal ["postpro.contact.v1", File.expand_path(mine)], data.values_at("schema", "input")
      assert_equal [1, 2, 3], data["takes"].map { |entry| entry["take"] }
    end
  end

  def test_a_single_take_gets_no_contact_sheet
    Dir.mktmpdir do |dir|
      mine = tiny_frame(File.join(dir, "frame.jpg"))
      take(mine, number: 1, look: "noir", picture: true)
      assert_nil send(:write_contact_sheet, mine)
      refute File.exist?(File.join(dir, "postpro_frame_contact.jpg"))
    end
  end

  def test_the_contact_sheet_is_retired_with_its_family
    Dir.mktmpdir do |dir|
      mine = tiny_frame(File.join(dir, "frame.jpg"))
      2.times { |index| take(mine, number: index + 1, look: "noir", picture: true) }
      sheet = quietly { send(:write_contact_sheet, mine) }

      quietly { Postpro::Constitution.retire_previous_renders!(mine) }
      refute File.exist?(sheet)
      refute File.exist?("#{sheet}.json")
    end
  end

  def test_a_contact_sheet_failure_costs_only_the_sheet
    Dir.mktmpdir do |dir|
      mine = File.join(dir, "frame.jpg")
      2.times { |index| take(mine, number: index + 1, look: "noir") }
      assert_nil quietly { send(:write_contact_sheet, mine) }
    end
  end

  def test_a_contact_label_is_as_wide_as_its_tile
    caption = send(:contact_label, "01  neon night", 200)
    assert_equal [200, 3], [caption.width, caption.bands]
  end
end
