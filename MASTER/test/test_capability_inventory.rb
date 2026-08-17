# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/capability_inventory"

class TestCapabilityInventory < Minitest::Test
  def setup
    @report = Pub4::CapabilityInventory.report
  end

  def test_no_named_capability_is_silently_dropped
    assert_empty @report[:lost],
                 "names present on #{@report[:baseline_ref]} are gone from the working tree:\n" \
                 "#{@report[:lost].map { |kind, names| "  #{kind}: #{names.join(", ")}" }.join("\n")}"
  end

  def test_current_inventory_covers_the_closed_slash_set
    slashes = @report[:current][:slashes]
    %w[through status undo commit model pair doctor help clear].each do |name|
      assert_includes slashes, name
    end
  end

  def test_law_files_are_the_four_budgeted_yamls
    assert_equal %w[limits.yml rules.yml soul.yml voice.yml], @report[:current][:law_files].sort
  end

  def test_constitution_still_names_the_incident_rules
    ids = @report[:current][:constitution]
    %w[batch_delete forbidden_file scope_creep two_hats ideation_before_write].each do |id|
      assert_includes ids, id
    end
  end
end
