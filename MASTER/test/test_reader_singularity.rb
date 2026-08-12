# frozen_string_literal: true

# A second reader of a data file is a second implementation of loading it.
#
# lib/trace/why_explainer.rb duplicated the rule-shard merge loop from
# lib/boot/data.rb. Both called Master.load_yaml — the copy was not bypassing
# the helper, it was composing the result itself — so they agreed until the
# shards moved, and then the copy wrote {} over the real rules and emptied /why
# for all 225 rules without failing anything.

require "minitest/autorun"
require "tmpdir"
require "yaml"
require_relative "../tools/reader_singularity"

class TestReaderSingularity < Minitest::Test
  def self.report = @report ||= Pub4::ReaderSingularity.run

  def setup
    @report = self.class.report
  end

  def test_no_data_file_gains_a_reader
    over = @report["findings"].map do |row|
      "#{row['data']}: #{row['readers']} readers, ceiling #{row['ceiling']}\n    #{row['files'].join("\n    ")}"
    end

    assert_empty over,
                 "a data file gained a reader. Route the new call through an accessor on Master.* " \
                 "(the way load_rules works) rather than loading the file a second way:\n  #{over.join("\n  ")}"
  end

  # A ceiling above the real count is slack, and slack is how a ratchet stops
  # measuring. Same rule data/spine.yml holds itself to.
  def test_no_ceiling_is_slack
    slack = Pub4::ReaderSingularity.ceilings.filter_map do |name, ceiling|
      actual = (Pub4::ReaderSingularity.readers[name] || []).size
      "#{name}: ceiling #{ceiling}, actual #{actual}" if actual < ceiling
    end

    assert_empty slack,
                 "readers were removed and the ceiling was not lowered. Run " \
                 "`ruby MASTER/tools/reader_singularity.rb --ratchet`:\n  #{slack.join("\n  ")}"
  end

  # The detector is the part most likely to be wrong, and a detector that finds
  # nothing passes every "no findings" assertion there is.
  def test_the_detector_finds_the_shape_it_exists_to_find
    assert_operator @report["loaded"], :>, 15,
                    "only #{@report['loaded']} data files detected as loaded — the detector stopped reading"
    assert_includes Pub4::ReaderSingularity.readers.fetch("rules.yml"), "MASTER/lib/boot/data.rb",
                    "the detector does not see the canonical rules.yml loader"
  end

  # The why_explainer shape specifically: the shared helper, a path built by
  # hand, in a file that is not the owner.
  def test_a_second_reader_written_the_why_explainer_way_is_detected
    Dir.mktmpdir do |dir|
      path = File.join(dir, "impostor.rb")
      File.write(path, <<~RUBY)
        def rules
          base = Master.load_yaml(File.join(@root, "data", "rules.yml"))
          base["rules"] = something_else
          base
        end
      RUBY

      found = Hash.new { |hash, key| hash[key] = [] }
      Pub4::ReaderSingularity.scan(path, found)

      assert_includes found.keys, "rules.yml",
                      "the detector misses a hand-built path into data/ through the shared helper — " \
                      "which is exactly how the original defect was written"
    end
  end
end
