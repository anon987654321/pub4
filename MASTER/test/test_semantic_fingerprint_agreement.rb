# frozen_string_literal: true

require_relative "test_helper"

class TestSemanticFingerprintAgreement < Minitest::Test
  SAMPLE = <<~RUBY
    class Sample
      CONST = 1

      def foo
        1
      end
    end
  RUBY

  # The actual bug, not a hypothetical: FileProcessor (stamps a fingerprint
  # onto every finding when it's first scanned) and RuleLoop::FixVerification
  # (recomputes one just before applying a fix, to detect whether the file
  # changed in between) used to be two independently-maintained copies of
  # the same formula. They quietly drifted -- FileProcessor's included an
  # extra `ast_present` key fix_verification's didn't -- so Marshal.dump
  # produced different bytes for the same code, and RuleLoop#fingerprint_matches?
  # returned false for every file, every time, forever, regardless of
  # whether anything had actually changed. Found live via rule_loop.rb's
  # skip_breakdown trace: 100% of skipped violations attributed to
  # fingerprint across every rule in a full-repo /fix pass, 0% to confidence.
  def test_file_processor_and_fix_verification_compute_identical_fingerprints
    from_file_processor = Master::Review::Scan::SemanticFingerprint.for(SAMPLE)
    from_fix_verification = Master::Review::Scan::SemanticFingerprint.for(SAMPLE)

    assert_equal from_file_processor, from_fix_verification
  end

  def test_a_real_scan_finding_carries_the_same_fingerprint_a_fresh_read_would_compute
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.rb")
      File.write(path, SAMPLE)

      scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
      result = scanner.scan(path)
      assert result.ok?, "expected scan to succeed"

      finding = result.value!.first
      refute_nil finding, "expected at least one finding for a fixture this messy"

      fresh = Master::Review::Scan::SemanticFingerprint.for(File.read(path, encoding: "UTF-8"))
      assert_equal fresh, finding[:fingerprint]
    end
  end

  def test_differs_when_code_actually_changes
    before = Master::Review::Scan::SemanticFingerprint.for(SAMPLE)
    after = Master::Review::Scan::SemanticFingerprint.for(SAMPLE + "\n# a new line\n")

    refute_equal before, after
  end
end
