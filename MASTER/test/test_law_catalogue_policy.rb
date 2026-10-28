# frozen_string_literal: true

require_relative "test_helper"
require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?

# A Law's enforcement policy lives in its laws.yml law_catalogue entry:
# severity, mode, reach, exemption, lifecycle, autofix and surfaces arrive from
# there, and the Ruby block has no method left to declare them a second time.
class TestLawCataloguePolicy < Minitest::Test
  POLICY = {
    "severity" => "error", "mode" => "opportunity", "languages" => %w[ruby], "path_pattern" => "/lib/",
    "path_exclude" => %w[/test/ /spec/], "lifecycle" => "advisory", "autofix" => "never",
    "surfaces" => %w[whole_file lines]
  }.freeze

  def test_catalogue_rejects_unknown_assessment_surfaces
    with_catalogue_entry(:ASSESSMENT_SURFACE_PROBE, "severity" => "info", "surfaces" => %w[made_up_surface]) do
      error = assert_raises(ArgumentError) { build(:ASSESSMENT_SURFACE_PROBE) }

      assert_includes error.message, "unknown assessment surfaces"
    end
  end

  def test_policy_comes_from_the_catalogue_entry
    with_catalogue_entry(:CATALOGUE_POLICY_PROBE, POLICY) do
      law = build(:CATALOGUE_POLICY_PROBE)

      assert_equal %i[error opportunity advisory never], [law.severity, law.mode, law.lifecycle, law.autofix]
      assert_equal ["ruby"], law.languages
      assert_equal %i[whole_file lines], law.assessment_surfaces
    end
  end

  # A list of path_exclude alternatives excludes what any one of them matches.
  def test_path_scope_and_exclusion_come_from_the_catalogue_entry
    with_catalogue_entry(:CATALOGUE_POLICY_PROBE, POLICY) do
      law = build(:CATALOGUE_POLICY_PROBE)

      assert law.applies?("/repo/lib/a.rb", "ruby")
      refute law.applies?("/repo/test/lib/a.rb", "ruby")
      refute law.applies?("/repo/spec/lib/a.rb", "ruby")
      refute law.applies?("/repo/app/a.rb", "ruby")
    end
  end

  def test_a_law_block_cannot_declare_policy
    declared = %i[severity mode languages path path_exclude lifecycle autofix surfaces law_scope]

    assert_empty declared & Law::Builder.public_instance_methods(false), "a second source beside laws.yml"
  end

  def test_catalogue_defaults_fill_what_an_entry_omits
    with_catalogue_entry(:CATALOGUE_DEFAULT_PROBE, "severity" => "info") do
      policy = Law.catalogue_policy(:CATALOGUE_DEFAULT_PROBE)
      defaults = Law::LAW_CATALOGUE.fetch("defaults")

      assert_equal %w[mode lifecycle autofix].map { |key| defaults.fetch(key).to_sym },
                   policy.values_at(:mode, :lifecycle, :autofix)
      assert_nil policy.fetch(:surfaces)
    end
  end

  def test_an_entry_without_severity_is_refused
    with_catalogue_entry(:SEVERITYLESS_PROBE, {}) do
      error = assert_raises(ArgumentError) { Law::Builder.new(:SEVERITYLESS_PROBE) }

      assert_match(/no severity/, error.message)
    end
  end

  private

  def build(id)
    builder = Law::Builder.new(id)
    builder.source("test")
    builder.practice("keep a measurable contract")
    builder.fix("inspect and report")
    builder.bad("bad")
    builder.good("good")
    builder.build
  end

  def with_catalogue_entry(id, fields)
    original = Law.method(:catalogue_entry)
    entry = { "universal" => true, "modalities" => %w[lexical semantic visual] }.merge(fields)
    Law.define_singleton_method(:catalogue_entry) { |key| key.to_sym == id ? entry : original.call(key) }
    yield
  ensure
    Law.define_singleton_method(:catalogue_entry, original)
  end
end
