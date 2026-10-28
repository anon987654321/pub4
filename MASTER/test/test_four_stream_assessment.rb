# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/four_stream_assessment"

class TestFourStreamAssessment < Minitest::Test
  Rule = Struct.new(:id)

  def build(laws: [Rule.new("DRY")], surfaces: [:whole_file], **limits)
    Master::Fix::FourStreamAssessment.new(laws:, surfaces:, **limits)
  end

  def clean(evidence: ["read whole_file; sha256=fixture"])
    { status: :assessed_clean, evidence: }
  end

  def test_four_streams_and_artifact_surfaces_are_explicit
    assert_equal %i[
      lexical_violations lexical_opportunities semantic_violations semantic_opportunities visual
    ], Master::Fix::FourStreamAssessment::STREAMS
    %i[repository_tree directories file_names paths whole_file sections lines syntax_tree cross_file
       structured_data documentation media_assets compiled_assets rendered_ui interactive_behavior tests runtime deployment].each do |surface|
      assert_includes Master::Fix::FourStreamAssessment::SURFACES, surface
    end

    report = build(surfaces: %i[paths whole_file cross_file]).report
    assert_equal 15, report[:expected_cells]
    assert_equal 0, report[:recorded_cells]
    refute report[:complete]
    refute report[:clean]
    assert_equal 15, report[:unassessed].size
  end

  # Coverage separates what can be measured from what no assessor can and from
  # what does not apply, per stream, instead of one INCOMPLETE.
  def test_coverage_counts_measurable_unmeasurable_and_not_applicable_cells
    assessment = build(surfaces: %i[whole_file])
    law = assessment.laws.first
    assessment.record(law:, stream: :lexical_violations, surface: :whole_file, status: :assessed_clean,
                      iteration: 1, evidence: ["read"])
    assessment.record(law:, stream: :lexical_opportunities, surface: :whole_file, status: :not_applicable,
                      iteration: 1, reason: "violation mode")
    assessment.record(law:, stream: :visual, surface: :whole_file, status: :inconclusive, iteration: 1,
                      reason: "no per-Law visual verdict")
    coverage = assessment.coverage(unmeasurable: Set[[law, :visual, :whole_file]])
    counts = ->(stream) { coverage.fetch(stream).values_at(:cells, :measurable, :unmeasurable, :not_applicable) }

    assert_equal [1, 1, 0, 0], counts.call("lexical_violations")
    assert_equal [1, 0, 0, 1], counts.call("lexical_opportunities")
    assert_equal [1, 0, 1, 0], counts.call("visual")
    refute assessment.complete?, "an unmeasurable cell still blocks DONE"
  end

  def test_each_stream_iterates_until_two_clean_assessments_after_a_repair
    assessment = build
    calls = Hash.new(0)
    repairs = []
    assessors = Master::Fix::FourStreamAssessment::STREAMS.to_h do |stream|
      [stream, lambda do |law:, surface:, iteration:, **|
        calls[stream] += 1
        if stream == :lexical_opportunities && iteration == 1
          { status: :opportunity_found, evidence: ["duplicate knowledge at #{law}/#{surface}"] }
        else
          clean(evidence: ["#{stream} inspected #{law}/#{surface} at round #{iteration}"])
        end
      end]
    end

    report = assessment.run(
      assessors:,
      repairer: lambda do |law:, stream:, surface:, status:, **|
        repairs << [law, stream, surface, status]
        { changed: true }
      end,
    )

    assert report[:complete]
    assert report[:clean]
    assert_equal 3, calls[:lexical_opportunities]
    assert_equal 3, calls[:lexical_violations]
    assert_equal 3, calls[:semantic_violations]
    assert_equal 3, calls[:semantic_opportunities]
    assert_equal [["DRY", :lexical_opportunities, :whole_file, :opportunity_found]], repairs
    clean_generations = assessment.history[["DRY", :lexical_violations, :whole_file]]
                              .select { |row| row.status == :assessed_clean }
                              .map(&:generation)
    assert_equal [0, 1, 1], clean_generations
    assert_equal 2, report[:clean_passes_required]
    assert_equal 1, report[:generation]
  end

  def test_missing_assessor_is_inconclusive_not_clean
    assessment = build
    report = assessment.run(
      assessors: {
        lexical_violations: ->(**) { clean },
      },
    )

    refute report[:complete]
    refute report[:clean]
    assert_equal 4, report[:inconclusive].size
    assert report[:inconclusive].all? { |row| row[:reason].include?("no assessor registered") }
  end

  def test_not_applicable_requires_a_reason_and_is_counted_as_covered
    assessment = build
    key = ["DRY", :semantic_violations, :whole_file]
    assert_raises(ArgumentError) do
      assessment.record(law: key[0], stream: key[1], surface: key[2],
        status: :not_applicable, iteration: 1)
    end

    Master::Fix::FourStreamAssessment::STREAMS.each do |stream|
      assessment.record(law: "DRY", stream:, surface: :whole_file,
        status: :not_applicable, iteration: 1,
        reason: "this law's declared scope excludes this surface")
    end
    assert assessment.complete?
    assert assessment.clean?
  end

  def test_clean_findings_and_inconclusive_states_require_evidence
    assessment = build
    assert_raises(ArgumentError) do
      assessment.record(law: "DRY", stream: :lexical_violations, surface: :whole_file,
        status: :assessed_clean, iteration: 1)
    end
    assert_raises(ArgumentError) do
      assessment.record(law: "DRY", stream: :lexical_violations, surface: :whole_file,
        status: :violation_found, iteration: 1)
    end
    assert_raises(ArgumentError) do
      assessment.record(law: "DRY", stream: :lexical_violations, surface: :whole_file,
        status: :inconclusive, iteration: 1)
    end
  end

  def test_two_records_from_the_same_iteration_cannot_fake_a_clean_streak
    assessment = build
    args = { law: "DRY", stream: :lexical_violations, surface: :whole_file,
      status: :assessed_clean, evidence: ["same source revision"], iteration: 1 }
    assessment.record(**args)
    assert_raises(ArgumentError) { assessment.record(**args) }
    refute assessment.complete?
  end

  def test_assessor_failure_is_visible_and_never_reads_as_clean
    assessment = build
    report = assessment.run(
      assessors: Master::Fix::FourStreamAssessment::STREAMS.to_h do |stream|
        [stream, lambda do |**|
          raise "fixture failure" if stream == :semantic_opportunities

          clean
        end]
      end,
    )

    refute report[:clean]
    failure = report[:inconclusive].find { |row| row[:stream] == "semantic_opportunities" }
    assert_includes failure[:reason], "fixture failure"
  end

  def test_plan_invalidation_resets_every_clean_streak
    assessment = build(clean_passes: 2)
    Master::Fix::FourStreamAssessment::STREAMS.each do |stream|
      1.upto(2) do |iteration|
        assessment.record(
          law: "DRY", stream:, surface: :whole_file,
          status: :assessed_clean,
          evidence: ["sha256=source-#{iteration}", "adapter=fixture"],
          iteration:, generation: 0
        )
      end
    end

    assert assessment.clean?
    generation = assessment.invalidate!(iteration: 2, reason: "source changed")
    assert_equal 1, generation
    refute assessment.complete?
    refute assessment.clean?
    summary = assessment.summary
    assert_equal 1, summary[:generation]
    assert_equal 5, summary[:recorded_cells]
    assert_equal 0, summary[:unassessed_cells]
  end

  def test_not_applicable_receipts_do_not_survive_a_new_generation
    assessment = build
    Master::Fix::FourStreamAssessment::STREAMS.each do |stream|
      assessment.record(
        law: "DRY", stream:, surface: :whole_file,
        status: :not_applicable, iteration: 1,
        reason: "fixture has no relevant surface"
      )
    end

    assert assessment.complete?
    assessment.invalidate!(iteration: 1, reason: "surface inventory changed")
    refute assessment.complete?
  end

  def test_unknown_surfaces_are_rejected
    assert_raises(ArgumentError) { build(surfaces: [:made_up_surface]) }
  end
end
