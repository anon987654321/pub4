# frozen_string_literal: true

require_relative "test_helper"
require_relative "../law/definition"

# Run the same preflight Law.load_all invokes, before any law file is evaluated.
class TestLawCatalogueBootstrap < Minitest::Test
  def generated_declarations(data)
    data.fetch("prose").values.flat_map do |language|
      language.fetch("ids", {}).values.map do |id|
        { id: id.to_s, source: "MASTER/law/prose.rb", line: 1 }
      end
    end.uniq { |row| row[:id] }
  end

  def test_live_catalogue_matches_all_executable_definitions_and_source_paths
    data = Master.load_laws(root: Master::ROOT)

    result = Master::LawCataloguePreflight.validate!(
      law_dir: File.join(Master::ROOT, "law"),
      catalogue: Law::LAW_CATALOGUE,
      repo_root: File.dirname(Master::ROOT),
      generated_declarations: generated_declarations(data)
    )

    assert result
  end

  def test_missing_identity_and_wrong_source_are_reported_before_evaluation
    Dir.mktmpdir("law-catalogue-preflight") do |root|
      law_dir = File.join(root, "MASTER", "law")
      FileUtils.mkdir_p(law_dir)
      File.write(File.join(law_dir, "missing.rb"), "Law.define(:MISSING_ID) do\nend\n")
      File.write(File.join(law_dir, "misplaced.rb"), "Law.define(:OTHER_ID) do\nend\n")
      File.write(File.join(law_dir, "actual.rb"), "Law.define(:ACTUAL_ID) do\nend\n")

      catalogue = {
        "entries" => {
          "OTHER_ID" => { "definition_sources" => ["MASTER/law/actual.rb"] },
          "ACTUAL_ID" => { "definition_sources" => ["MASTER/law/actual.rb"] }
        }
      }
      error = assert_raises(ArgumentError) do
        Master::LawCataloguePreflight.validate!(law_dir:, catalogue:, repo_root: root)
      end

      assert_match(/missing catalogue entry for MISSING_ID/, error.message)
      assert_match(/OTHER_ID declares at MASTER\/law\/misplaced\.rb/, error.message)
      assert_match(/OTHER_ID names MASTER\/law\/actual\.rb, but that source does not define OTHER_ID/, error.message)
    end
  end

  def test_detector_catalogue_rejects_a_source_that_does_not_declare_its_id
    Dir.mktmpdir("law-catalogue-detector-source") do |root|
      law_dir = File.join(root, "MASTER", "law")
      detector_dir = File.join(law_dir, "detectors")
      FileUtils.mkdir_p(detector_dir)
      File.write(File.join(law_dir, "actual.rb"), "Law.define(:ACTUAL_ID) do\nend\n")
      File.write(File.join(detector_dir, "detector.rb"), "LawDSL.law :actual_detector do\nend\n")

      catalogue = {
        "entries" => {
          "ACTUAL_ID" => { "definition_sources" => ["MASTER/law/actual.rb"] },
          "actual_detector" => { "detector_sources" => ["MASTER/law/detectors/detector.rb"] },
          "orphan_detector" => { "detector_sources" => ["MASTER/law/detectors/detector.rb"] }
        }
      }
      error = assert_raises(ArgumentError) do
        Master::LawCataloguePreflight.validate!(law_dir:, catalogue:, repo_root: root)
      end

      assert_match(/orphan_detector names MASTER\/law\/detectors\/detector\.rb, but that source does not declare detector orphan_detector/, error.message)
    end
  end

  def test_new_detector_declaration_without_catalogue_membership_is_reported
    Dir.mktmpdir("law-catalogue-unlisted-detector") do |root|
      law_dir = File.join(root, "MASTER", "law")
      detector_dir = File.join(law_dir, "detectors")
      FileUtils.mkdir_p(detector_dir)
      File.write(File.join(law_dir, "actual.rb"), "Law.define(:ACTUAL_ID) do\nend\n")
      File.write(File.join(detector_dir, "detector.rb"), "LawDSL.law :unlisted_detector do\nend\n")

      error = assert_raises(ArgumentError) do
        Master::LawCataloguePreflight.validate!(
          law_dir:,
          catalogue: { "entries" => { "ACTUAL_ID" => { "definition_sources" => ["MASTER/law/actual.rb"] } } },
          repo_root: root
        )
      end

      assert_match(/detector unlisted_detector in MASTER\/law\/detectors\/detector\.rb has no catalogue entry/, error.message)
    end
  end

  def test_manifest_metadata_and_identity_shape_fail_before_law_evaluation
    Dir.mktmpdir("law-catalogue-metadata") do |root|
      law_dir = File.join(root, "MASTER", "law")
      FileUtils.mkdir_p(law_dir)
      File.write(File.join(law_dir, "actual.rb"), "Law.define(:ACTUAL_ID) do\nend\n")

      catalogue = {
        "modalities" => %w[lexical semantic visual],
        "surfaces" => ["whole_file"],
        "defaults" => {},
        "entries" => {
          "ACTUAL_ID" => { "universal" => false, "modalities" => [], "definition_sources" => [] },
          "bad-id" => { "universal" => true, "modalities" => %w[lexical semantic visual] }
        }
      }
      error = assert_raises(ArgumentError) do
        Master::LawCataloguePreflight.validate!(law_dir:, catalogue:, repo_root: root)
      end

      assert_match(/Law ACTUAL_ID must be marked universal/, error.message)
      assert_match(/Law ACTUAL_ID modalities must/, error.message)
      assert_match(/Law ACTUAL_ID has no effective severity/, error.message)
      assert_match(/Law ACTUAL_ID has no definition_sources or detector_sources/, error.message)
      assert_match(/invalid Law catalogue identity.*bad-id/, error.message)
      assert_match(/Law bad-id has no definition_sources or detector_sources/, error.message)
    end
  end

  def test_dynamic_detector_templates_expand_to_literal_catalogue_ids
    Dir.mktmpdir("law-catalogue-dynamic-detector") do |root|
      detector_dir = File.join(root, "MASTER", "law", "detectors")
      FileUtils.mkdir_p(detector_dir)
      path = File.join(detector_dir, "detector.rb")
      File.write(path, <<~RUBY)
        %w[USEFUL HONEST].each do |trait|
          LawDSL.law :"RAMS_\#{trait}" do
          end
        end
      RUBY

      declarations = Master::LawCataloguePreflight.source_detector_declarations(
        detector_dir, root
      )

      assert_equal %w[RAMS_HONEST RAMS_USEFUL], declarations.map { |row| row.fetch(:id) }.sort
    end
  end

  def test_invalid_policy_values_and_scope_patterns_fail_before_law_loading
    Dir.mktmpdir("law-catalogue-invalid-policy") do |root|
      law_dir = File.join(root, "MASTER", "law")
      FileUtils.mkdir_p(law_dir)
      File.write(File.join(law_dir, "actual.rb"), "Law.define(:ACTUAL_ID) do\nend\n")

      catalogue = {
        "modalities" => %w[lexical semantic visual],
        "surfaces" => ["whole_file"],
        "defaults" => { "mode" => "violation", "lifecycle" => "active", "autofix" => "review" },
        "unknown_registry" => true,
        "entries" => {
          "ACTUAL_ID" => {
            "universal" => true,
            "modalities" => %w[lexical semantic visual],
            "definition_sources" => ["MASTER/law/actual.rb"],
            "severity" => "warning",
            "mode" => "silent_pass",
            "path_pattern" => "[",
            "severity_typo" => "warn"
          }
        }
      }

      error = assert_raises(ArgumentError) do
        Master::LawCataloguePreflight.validate!(law_dir:, catalogue:, repo_root: root)
      end

      assert_match(/Law ACTUAL_ID has invalid mode "silent_pass"/, error.message)
      assert_match(/Law ACTUAL_ID has invalid path_pattern/, error.message)
      assert_match(/law_catalogue has unknown field\(s\): unknown_registry/, error.message)
      assert_match(/Law ACTUAL_ID has unknown catalogue field\(s\): severity_typo/, error.message)
    end
  end

  def test_duplicate_static_definitions_are_reported_as_one_preflight_error
    Dir.mktmpdir("law-catalogue-duplicate") do |root|
      law_dir = File.join(root, "MASTER", "law")
      FileUtils.mkdir_p(law_dir)
      File.write(File.join(law_dir, "one.rb"), "Law.define(:DUPLICATE_ID) do\nend\n")
      File.write(File.join(law_dir, "two.rb"), "Law.define(:DUPLICATE_ID) do\nend\n")

      error = assert_raises(ArgumentError) do
        Master::LawCataloguePreflight.validate!(
          law_dir:,
          catalogue: { "entries" => { "DUPLICATE_ID" => { "definition_sources" => ["MASTER/law/one.rb"] } } },
          repo_root: root
        )
      end

      assert_match(/duplicate definition: DUPLICATE_ID/, error.message)
    end
  end
end
