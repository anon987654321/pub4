# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "rbconfig"
require_relative "../../MASTER/contracts/studio"

class StudioContractTest < Minitest::Test
  def test_photograph_contract_reads_structured_result
    Dir.mktmpdir do |root|
      File.write(File.join(root, "photograph.rb"), <<~RUBY)
        # frozen_string_literal: true
        require "json"
        puts JSON.generate("still" => "/tmp/still.jpg")
      RUBY

      original = ENV["PUB4_STUDIO_ROOT"]
      ENV["PUB4_STUDIO_ROOT"] = root
      assert_equal({ "still" => "/tmp/still.jpg" }, Contracts::Studio.photograph(prompt: "test"))
    ensure
      ENV["PUB4_STUDIO_ROOT"] = original
    end
  end

  def test_bounded_runner_stops_a_hung_child_and_keeps_its_partial_output
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output, status = Contracts::Studio.run_bounded(
      [RbConfig.ruby, "-e", "STDOUT.sync = true; print 'started'; sleep 30"],
      chdir: Dir.tmpdir,
      timeout: 0.1
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_includes output, "started"
    refute status.success?
    assert_operator elapsed, :<, 3
  end

  def test_canonical_media_entrypoints_are_addressable
    assert Contracts::Studio.photograph_script
    assert Contracts::Studio.dilla_script
    assert Contracts::Studio.postpro_script
    assert Contracts::Studio.replicate_script
  end

  def test_output_path_contract_delegates_to_studio_and_uses_utc_dates
    original = %w[PUB4_STUDIO_ROOT XDG_DATA_HOME DILLA_OUTPUT_DIR]
      .to_h { |name| [name, ENV[name]] }

    Dir.mktmpdir do |dir|
      ENV.delete("PUB4_STUDIO_ROOT")
      ENV["XDG_DATA_HOME"] = File.join(dir, "xdg-data")
      ENV.delete("DILLA_OUTPUT_DIR")

      at = Time.iso8601("2026-01-02T00:30:00+02:00")
      expected = File.join(File.realpath(dir), "xdg-data", "dilla-renders", "2026-01-01")
      assert_equal expected,
                   Contracts::Studio.output_path(kind: :dilla_render_directory, at:)
    end
  ensure
    original&.each do |name, value|
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end
  end

  def test_unknown_output_path_kind_is_rejected_before_dispatch
    error = assert_raises(ArgumentError) do
      Contracts::Studio.output_path(kind: :unknown)
    end

    assert_match(/unknown STUDIO output path kind/, error.message)
  end
end
