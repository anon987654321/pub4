# frozen_string_literal: true

require "test_helper"
require "cli/skill_fixtures"

# Approval reads every declared fixture first; a declared path was approval
# enough before, whether or not anything was there.
class TestSkillFixtures < Minitest::Test
  Fixtures = Master::CLI::SkillFixtures

  def statuses(refs, root) = Fixtures.verify(refs, root:).to_h { |outcome| [outcome.ref, outcome.status] }

  def test_each_fixture_is_read_inside_the_skill_directory_and_nowhere_else
    Dir.mktmpdir do |base|
      skill = File.join(base, "skill")
      FileUtils.mkdir_p(skill)
      File.write(File.join(skill, "expect.yml"), "answer: 42\n")
      File.write(File.join(skill, "broken.json"), "{not json")
      File.write(File.join(skill, "run.rb"), "puts :pwned\n")
      File.write(File.join(base, "outside.yml"), "x: 1\n")
      File.symlink(File.join(base, "outside.yml"), File.join(skill, "link.yml"))

      result = statuses(%w[expect.yml broken.json run.rb absent.md ../outside.yml /etc/hosts link.yml], skill)

      assert_equal({ "expect.yml" => "verified", "broken.json" => "unreadable", "run.rb" => "unsupported",
                     "absent.md" => "missing", "../outside.yml" => "escapes_root", "/etc/hosts" => "escapes_root",
                     "link.yml" => "symlink" }, result)
    end
  end

  def test_a_verified_fixture_carries_the_digest_of_the_bytes_read
    Dir.mktmpdir do |skill|
      File.write(File.join(skill, "notes.md"), "Expected output.\n")
      outcome = Fixtures.verify(["notes.md"], root: skill).first

      assert_equal Digest::SHA256.hexdigest("Expected output.\n"), outcome.sha256
    end
  end

  def test_an_oversized_fixture_is_refused_unread
    Dir.mktmpdir do |skill|
      File.write(File.join(skill, "big.txt"), "x" * (Fixtures::MAX_BYTES + 1))

      assert_equal "too_large", Fixtures.verify(["big.txt"], root: skill).first.status
    end
  end
end
