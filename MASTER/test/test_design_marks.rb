# frozen_string_literal: true

require_relative "test_helper"
require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

# Five decorative-device laws share one detector module (DesignMarks, law/css.rb).
# Each case below pairs what the law must flag with the legitimate neighbour it
# must spare; the neighbours came from a census over RAILS/ (6 tracked eyebrow
# blocks, 29 eyebrow classes, 1 arrow, 25 dotted strings, 5 gradients, 0 ordinals).
class TestDesignMarks < Minitest::Test
  IDS = %i[NO_EYEBROW_LABEL NO_TRAILING_ARROW NO_DOT_SEPARATED_META NO_DECORATIVE_GRADIENT NO_ORDINAL_ORNAMENT].freeze

  def flagged?(id, text, file) = !::Law.definitions.fetch(id).scan(text, file:).empty?

  def test_every_law_is_registered_and_proved
    IDS.each { |id| assert ::Law.definitions.key?(id), "#{id} missing from law/" }
  end

  def test_each_law_names_its_constitutional_law
    IDS.each do |id|
      assert_match(/\A(?:DENSITY|LINEARITY|RENDERED_VALUES)\b/, ::Law.definitions.fetch(id).source, id.to_s)
    end
  end

  def test_eyebrow_needs_uppercase_and_tracking_on_small_or_named_text
    assert flagged?(:NO_EYEBROW_LABEL, ".a { font-size: 0.75rem;\n text-transform: uppercase;\n letter-spacing: 0.1em; }", "a.scss")
    assert flagged?(:NO_EYEBROW_LABEL, ".page-kicker { text-transform: uppercase; letter-spacing: var(--tracking-wide); }", "a.scss")
    assert flagged?(:NO_EYEBROW_LABEL, %(<p class="legal-eyebrow">x</p>), "a.html.erb")
    refute flagged?(:NO_EYEBROW_LABEL, ".a { font-size: 1rem; text-transform: uppercase; letter-spacing: 0.1em; }", "a.scss")
    refute flagged?(:NO_EYEBROW_LABEL, ".a { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0; }", "a.scss")
    refute flagged?(:NO_EYEBROW_LABEL, ".a { font-size: 0.75rem; letter-spacing: 0.1em; }", "a.scss")
    refute flagged?(:NO_EYEBROW_LABEL, "/* .kicker { text-transform: uppercase; letter-spacing: 1px; font-size: 10px; } */", "a.css")
  end

  def test_arrow_flags_link_and_button_text_only
    assert flagged?(:NO_TRAILING_ARROW, %(<a href="/x">Les mer →</a>), "a.html.erb")
    assert flagged?(:NO_TRAILING_ARROW, %(<%= link_to "Les mer ->", path %>), "a.html.erb")
    assert flagged?(:NO_TRAILING_ARROW, %(<%= t("x") %> <span aria-hidden="true">→</span>), "a.html.erb")
    refute flagged?(:NO_TRAILING_ARROW, %(<a href="/x">Les saken</a>), "a.html.erb")
    refute flagged?(:NO_TRAILING_ARROW, %(<p>Bergen → Oslo</p>), "a.html.erb")
    refute flagged?(:NO_TRAILING_ARROW, %(<%= link_to "Hjem", ->(x) { x } %>), "a.html.erb")
  end

  def test_dotted_meta_needs_two_separators_or_a_join
    assert flagged?(:NO_DOT_SEPARATED_META, "<p>Bergen · 3 timer · 12 svar</p>", "a.html.erb")
    assert flagged?(:NO_DOT_SEPARATED_META, %(<%= [a, b].compact.join(" · ") %>), "a.html.erb")
    refute flagged?(:NO_DOT_SEPARATED_META, "<p>Bergen · Oslo</p>", "a.html.erb")
    refute flagged?(:NO_DOT_SEPARATED_META, "<title>brgen · a · b</title>", "a.html.erb")
  end

  def test_gradient_spares_fades_masks_solids_and_bars
    assert flagged?(:NO_DECORATIVE_GRADIENT, "background: linear-gradient(135deg, var(--a), var(--b));", "a.scss")
    assert flagged?(:NO_DECORATIVE_GRADIENT, "background-image: radial-gradient(circle, #ffb999, #fff);", "a.css")
    refute flagged?(:NO_DECORATIVE_GRADIENT, "background: linear-gradient(to right, var(--bg), transparent);", "a.scss")
    refute flagged?(:NO_DECORATIVE_GRADIENT, "mask-image: linear-gradient(#000, #000);", "a.scss")
    refute flagged?(:NO_DECORATIVE_GRADIENT, "background: linear-gradient(var(--rule), var(--rule)) center bottom / 90% 1px;", "a.scss")
    refute flagged?(:NO_DECORATIVE_GRADIENT, "background: linear-gradient(90deg, var(--on) var(--r), var(--off) var(--r));", "a.scss")
  end

  def test_ordinal_ornament_is_leading_zero_only
    assert flagged?(:NO_ORDINAL_ORNAMENT, ".c::before { content: counter(c, decimal-leading-zero); }", "a.scss")
    assert flagged?(:NO_ORDINAL_ORNAMENT, %(<span class="num">01</span>), "a.html.erb")
    refute flagged?(:NO_ORDINAL_ORNAMENT, ".step::before { content: counter(step); }", "a.scss")
    refute flagged?(:NO_ORDINAL_ORNAMENT, %(<span>2026</span>), "a.html.erb")
  end
end
