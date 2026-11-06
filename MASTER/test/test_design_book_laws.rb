# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

# The design-book Laws' source detectors (law/typesetting.rb, brand.rb, css.rb, javascript.rb,
# html.rb, geometry.rb) and the snapshot adapters of the ones with a rendered half, run as the
# scanner runs them: through LawTree, on the paths in fixtures/design_book_laws.yml. Each Law
# is also in scan.yml's aesthetic group, so the design scan profile reaches it.
class TestDesignBookLaws < Minitest::Test
  FIXTURES = YAML.safe_load_file(File.expand_path("fixtures/design_book_laws.yml", __dir__))
  ROOT = File.expand_path("../..", __dir__)
  AESTHETIC = YAML.safe_load_file(File.expand_path("../data/scan.yml", __dir__)).dig("law_groups", "aesthetic")

  def code_of(row)
    return row.fetch("code") unless row["source"]

    text = File.read(File.join(ROOT, row["source"]))
    from, to = row["replace"]
    from ? text.sub(from, to) : text
  end

  def assert_case(id, row)
    found = law_findings(id, code_of(row), path: row.fetch("path"))
    where = "#{id} at #{row["path"]}"
    return assert_empty(found, "#{where} flagged a good case") unless row["flags"]

    refute_empty found, "#{where} missed a bad case"
    assert_equal row["count"], found.size, where if row["count"]
    assert_match Regexp.new(row["match"]), found.first[:message].to_s, where if row["match"]
  end

  FIXTURES.group_by { |row| row.fetch("law") }.each do |id, rows|
    define_method("test_#{id.downcase}_flags_its_bad_cases_and_passes_its_good_ones") do
      rows.each { |row| assert_case(id, row) }
      assert_includes AESTHETIC, id, "#{id} is missing from scan.yml law_groups.aesthetic"
      ask = rows.filter_map { |row| row["ask"] }.first
      assert_includes Law.definitions.fetch(id.to_sym).ask.to_s, ask if ask
    end
  end

  # The guarantee Operator::TypographyLint's serif rule gave before it folded into TYPEFACE_PER_ROLE:
  # no serif family anywhere in the Swiss trees (brgen*, __shared, amber), vendored sheets aside.
  def test_typeface_per_role_finds_no_serif_in_the_swiss_trees
    trees = Dir[File.join(ROOT, "RAILS/{brgen*,__shared,amber}/**/*.{css,scss,erb,html}")]
    found = trees.reject { |file| file.include?("/builds/") || file.include?("/node_modules/") }.flat_map do |file|
      hits = law_findings("TYPEFACE_PER_ROLE", File.read(file), path: file)
      hits.map { |hit| "#{file.delete_prefix(ROOT)}:#{hit[:line]}" }
    end
    assert_empty found
  end
end
