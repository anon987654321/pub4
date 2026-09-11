# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "support/method_swap"
require_relative "../gates/lib/rendered/rendered_invariants"

# rendered_invariants decides three things from one probe payload: the served
# palette against the declared one, the chat tab's corner against a table of
# declared exceptions, and the top band's centre line. All three are pure
# functions of that payload, so each can be handed a defect without Chrome.
#
# The first test is the one that matters. Without a browser this gate must say
# it measured nothing — not pass. It reported PASSED for months by filing the
# missing browser as a live skip, which the runner counts but cannot name, so
# "measured nothing, and why" printed "exit 3, no reason given (subprocess
# gate)" for an in-process gate.
class RenderedInvariantsGateTest < Minitest::Test
  include MethodSwap

  G = Deploy::RenderedInvariants

  def gate = G.new(result: Deploy::GateResult.new)

  # right/bottom are distances from the viewport edge; cy is a centre line.
  def payload(declared: "dark", luma: 0.05, chat: { "right" => 0, "bottom" => 0 }, band: nil)
    {
      "bg" => "rgb(10, 10, 10)", "luma" => luma, "declared" => declared, "chat" => chat,
      "band" => band || { ".nav_link" => { "cy" => 31 }, ".brgen-logo-mark" => { "cy" => 31 } },
    }
  end

  def check(name, *args)
    result = Deploy::GateResult.new
    G.new(result: result).send(name, *args)
    result
  end

  def assert_names(result, pattern)
    assert result.failures.any? { |f| f.match?(pattern) },
           "no failure matched #{pattern.inspect}; got:\n  #{result.failures.join("\n  ")}"
  end

  # THE assertion. A gate that measured nothing and said ok is the failure every
  # rendered gate in this tree exists to prevent.
  def test_without_chrome_the_gate_is_inconclusive_and_never_passes
    result = swap_value(Deploy::CdpSession, :available?, false) { G.run }

    assert_equal :inconclusive, result.outcome
    assert_predicate result, :ok?, "a missing browser is a fact about the machine, not a verdict about the tree"
    assert_empty result.failures
    assert_equal 0, result.checks_ran
    assert_predicate result, :measured_nothing?
  end

  # The runner prints "N gate(s) measured nothing, and why" from `unchecked`
  # alone. A reason filed anywhere else is a reason the reader never sees.
  def test_the_missing_browser_is_named_where_the_runner_reads_reasons
    result = swap_value(Deploy::CdpSession, :available?, false) { G.run }

    assert_equal 1, result.unchecked.size
    assert_match(/no Chrome/i, result.unchecked.first)
  end

  # GATE_STRICT_INCONCLUSIVE is what the deploy host sets, where Chrome is
  # supposed to be present and its absence is itself the news.
  def test_strict_inconclusive_turns_a_browserless_run_into_a_failure
    was = ENV["GATE_STRICT_INCONCLUSIVE"]
    ENV["GATE_STRICT_INCONCLUSIVE"] = "1"
    result = swap_value(Deploy::CdpSession, :available?, false) { G.run }

    assert_equal :failed, result.outcome
  ensure
    ENV["GATE_STRICT_INCONCLUSIVE"] = was
  end

  # The bug this gate was written for: :root declared dark, a
  # prefers-color-scheme block outranked it, and the page served light. Both are
  # valid CSS, so only the pixels can tell.
  def test_a_page_that_declares_dark_and_paints_light_fails
    result = check(:check_theme, "brgen.no", :dark, payload(declared: "dark", luma: 0.92))

    assert_names result, /declares data-theme="dark" but serves a light background/
  end

  def test_a_page_that_declares_light_and_paints_dark_fails
    result = check(:check_theme, "markedsplass.brgen.no", :light, payload(declared: "light", luma: 0.03))

    assert_names result, /declares data-theme="light" but serves a dark background/
  end

  def test_a_page_whose_declaration_and_pixels_agree_passes
    dark = check(:check_theme, "brgen.no", :dark, payload(declared: "dark", luma: 0.04))
    light = check(:check_theme, "markedsplass.brgen.no", :light, payload(declared: "light", luma: 0.93))

    assert_empty dark.failures
    assert_empty light.failures
  end

  # surface_theme writes the attribute on every surface. A page with none is a
  # page whose palette nothing can be checked against.
  def test_a_page_that_declares_no_theme_at_all_fails
    result = check(:check_theme, "tv.brgen.no", :dark, payload(declared: nil))

    assert_names result, /declares no data-theme/
  end

  # The product decision, pinned separately: a surface that flips agrees with
  # itself perfectly and would otherwise pass.
  def test_a_surface_that_flips_its_declared_theme_fails_even_when_the_pixels_agree
    result = check(:check_theme, "playlist.brgen.no", :dark, payload(declared: "light", luma: 0.93))

    assert_names result, /declares data-theme="light" but this gate expects dark/
  end

  def test_a_chat_tab_adrift_of_the_corner_with_no_declared_reason_fails
    result = check(:check_chat_corner, "brgen.no", payload(chat: { "right" => 24, "bottom" => 40 }))

    assert_names result, /neither the corner nor a declared exception/
  end

  def test_a_chat_tab_flush_in_the_corner_passes
    assert_empty check(:check_chat_corner, "brgen.no", payload(chat: { "right" => 0, "bottom" => 1 })).failures
  end

  # An exemption whose reason has evaporated is the other half of the contract:
  # a surface declared :raised that is flush must fail, or the list rots.
  def test_a_surface_declared_raised_that_sits_flush_fails
    result = check(:check_chat_corner, "playlist.brgen.no", payload(chat: { "right" => 0, "bottom" => 0 }))

    assert_names result, /declares :raised but the chat tab is flush/
  end

  def test_a_surface_declared_raised_that_clears_its_tab_bar_passes
    assert_empty check(:check_chat_corner, "playlist.brgen.no", payload(chat: { "right" => 0, "bottom" => 60 })).failures
  end

  def test_a_surface_declared_absent_that_renders_a_widget_fails
    result = check(:check_chat_corner, "dating.brgen.no", payload(chat: { "right" => 0, "bottom" => 0 }))

    assert_names result, /listed as :absent .* but renders a chat widget/
  end

  def test_a_missing_widget_with_no_declared_reason_fails
    result = check(:check_chat_corner, "brgen.no", payload(chat: nil))

    assert_names result, /no chat widget and no declared reason/
  end

  # The measured case: nav links centred at 31 in a 62px bar while the brand
  # mark and toggle sat at 34, because those took `top` from --chrome-inset.
  def test_top_chrome_three_pixels_out_of_line_fails_and_says_by_how_much
    band = { ".nav_link" => { "cy" => 31 }, ".brgen-logo-mark" => { "cy" => 34 }, ".theme-toggle" => { "cy" => 34 } }
    result = check(:check_top_band_alignment, "brgen.no", payload(band: band))

    assert_names result, /top chrome is 3px out of alignment/
    assert_names result, /--chrome-inset-block/
  end

  def test_sub_pixel_rounding_in_the_top_band_is_not_a_defect
    band = { ".nav_link" => { "cy" => 31 }, ".theme-toggle" => { "cy" => 32 } }

    assert_empty check(:check_top_band_alignment, "brgen.no", payload(band: band)).failures
  end

  # An element the surface does not render is absent, not misaligned. One box
  # cannot be out of line with itself.
  def test_a_band_with_one_measurable_element_reports_nothing
    band = { ".nav_link" => { "cy" => 31 }, ".brgen-logo-mark" => nil, ".theme-toggle" => nil }

    assert_empty check(:check_top_band_alignment, "brgen.no", payload(band: band)).failures
  end
end
