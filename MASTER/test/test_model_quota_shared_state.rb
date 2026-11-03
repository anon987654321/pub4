# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "etc"

# vm23 keeps MASTER/.master as a group-shared 0770 directory: dev deploys and
# the master service runs. The quota file sat directly in it, the
# private-directory check refused it, and the 2026-11-03 deploy preflight's boot
# smoke failed on "model quota directory must be ... non-writable-by-group".
class TestModelQuotaSharedState < Minitest::Test
  QUOTA = Master::Io::ModelQuota

  def test_the_default_quota_file_sits_in_a_directory_of_its_own_per_user
    user = Etc.getpwuid(Process.uid).name
    expected = File.join(Master::ROOT, ".master", "quota-#{user}", "model_quota.json")

    with_env("MASTER_MODEL_QUOTA_PATH" => nil) { assert_equal expected, QUOTA.path }
  end

  def test_a_group_shared_parent_works_through_the_private_per_user_directory
    Dir.mktmpdir("master-shared-") do |shared|
      File.chmod(0o770, shared)
      path = File.join(shared, "quota-#{Etc.getpwuid(Process.uid).name}", "model_quota.json")

      QUOTA.stub(:path, path) do
        QUOTA.record("probe/model:free")
        assert_equal 1, QUOTA.count("probe/model:free")
      end
      assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777
    end
  end

  def test_the_quota_file_directly_in_a_group_shared_directory_is_still_refused
    Dir.mktmpdir("master-shared-") do |shared|
      File.chmod(0o770, shared)
      path = File.join(shared, "model_quota.json")
      File.write(path, "{}")
      File.chmod(0o600, path)

      QUOTA.stub(:path, path) do
        error = assert_raises(RuntimeError) { QUOTA.count("probe/model:free") }
        assert_match(/non-writable-by-group/, error.message)
      end
    end
  end

  private

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
