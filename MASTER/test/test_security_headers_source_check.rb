# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../checks/lib/source/security_headers"

class SecurityHeadersSourceCheckTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  SOURCE_PATHS = [
    Deploy::SecurityHeadersSourceCheck::SHARED_HEADERS,
    Deploy::SecurityHeadersSourceCheck::SHARED_CSP,
    Deploy::SecurityHeadersSourceCheck::MASTER_CSP,
    Deploy::SecurityHeadersSourceCheck::RELAYD,
  ].freeze

  def test_current_repository_security_header_contract_passes
    result = Deploy::SecurityHeadersSourceCheck.run(root: ROOT)
    assert result.ok?, result.failures.join("\n")
  end

  def test_global_relayd_csp_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::RELAYD)
      File.open(path, "a") do |file|
        file.puts '  match response header set "Content-Security-Policy" value "default-src *"'
      end

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "must not replace app-owned CSP"
    end
  end

  def test_wildcard_script_source_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      source = File.read(path)
      source = replace_once(source, 'policy.script_src :self, "https://link.tradedoubler.com"',
                                     "policy.script_src :self, :https")
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "overly broad script-src"
    end
  end

  def test_quoted_wildcard_script_source_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      source = File.read(path)
      source = replace_once(source, 'policy.script_src :self, "https://link.tradedoubler.com"',
                                     'policy.script_src :self, "*"')
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "overly broad script-src"
    end
  end

  def test_missing_edge_hsts_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::RELAYD)
      source = File.read(path)
      source = replace_once(
        source,
        'match response header set "Strict-Transport-Security" value "max-age=31536000; includeSubDomains; preload"',
        ""
      )
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "Strict-Transport-Security"
    end
  end

  def test_shared_apps_must_declare_same_origin_frame_ancestors
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      source = File.read(path)
      source = replace_once(source, "    policy.frame_ancestors :self\n", "")
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "policy.frame_ancestors :self"
    end
  end

  def test_missing_master_embed_allowlist_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::MASTER_CSP)
      source = File.read(path)
      source = replace_once(source, "policy.frame_ancestors :self, *embed_hosts",
                                    "policy.frame_src :none")
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "frame_ancestors"
    end
  end

  private

  def with_source_tree
    Dir.mktmpdir("security-headers-source-contract") do |root|
      SOURCE_PATHS.each do |relative|
        target = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join(ROOT, relative), target)
      end
      yield root
    end
  end

  def replace_once(source, old, replacement)
    raise "fixture anchor not found: #{old.inspect}" unless source.include?(old)

    source.sub(old, replacement)
  end
end
