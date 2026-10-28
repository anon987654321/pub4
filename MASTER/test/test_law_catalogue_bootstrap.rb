# frozen_string_literal: true

require_relative "test_helper"
require_relative "../law/definition"

# Catch catalogue omissions before Law.load_all evaluates a definition. Without
# this preflight, the first omitted entry raises during boot and prevents the
# registry audit from explaining the complete source drift.
class TestLawCatalogueBootstrap < Minitest::Test
  def catalogue_entries
    Law::LAW_CATALOGUE.fetch("entries")
  end

  def test_literal_law_declarations_are_catalogued_before_runtime_load
    declarations = Dir.glob(File.join(Master::ROOT, "law", "*.rb")).sort.flat_map do |path|
      File.readlines(path, encoding: "UTF-8").filter_map do |line|
        match = line.match(/^[ \t]*Law\.define\(\s*:([A-Z][A-Z0-9_]*)\s*\)/)
        [match[1], path] if match
      end
    end

    missing = declarations.reject { |id, _path| catalogue_entries.key?(id) }
    report = missing.map do |id, path|
      "#{id} (#{path.delete_prefix(Master::ROOT + File::SEPARATOR)})"
    end

    assert_empty report, "executable Laws missing from law_catalogue.entries: #{report.join(', ')}"
  end

  def test_generated_prose_law_ids_are_catalogued_before_runtime_load
    prose = Master.load_laws(root: Master::ROOT).fetch("prose")
    ids = prose.values.flat_map { |language| language.fetch("ids", {}).values }.map(&:to_s).uniq
    missing = ids.reject { |id| catalogue_entries.key?(id) }

    assert_empty missing, "generated prose Laws missing from law_catalogue.entries: #{missing.join(', ')}"
  end
end
