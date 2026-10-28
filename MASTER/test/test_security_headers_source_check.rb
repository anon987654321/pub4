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
      assert_includes result.failures.join("\n"), "must not alter app-owned CSP"
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

  def test_unsafe_inline_script_source_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      source = File.read(path)
      source = replace_once(
        source,
        'policy.script_src :self, "https://link.tradedoubler.com"',
        "policy.script_src :self, :unsafe_inline",
      )
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "overly broad script-src"
    end
  end

  def test_multiline_script_source_cannot_hide_unsafe_inline
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      source = File.read(path)
      source = replace_once(
        source,
        'policy.script_src :self, "https://link.tradedoubler.com"',
        "policy.script_src(\n      :self,\n      :unsafe_inline\n    )",
      )
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "overly broad script-src"
    end
  end

  def test_script_src_elem_is_checked
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      File.open(path, "a") { |file| file.puts "    policy.script_src_elem :unsafe_inline" }

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "overly broad script-src-elem"
    end
  end

  def test_script_src_attr_is_checked
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      File.open(path, "a") { |file| file.puts "    policy.script_src_attr :unsafe_inline" }

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "overly broad script-src-attr"
    end
  end

  def test_subdomain_wildcard_script_source_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      source = File.read(path)
      source = replace_once(
        source,
        'policy.script_src :self, "https://link.tradedoubler.com"',
        'policy.script_src :self, "https://*.example.com"',
      )
      File.write(path, source)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "overly broad script-src"
    end
  end

  def test_data_and_blob_script_sources_are_rejected
    ["data:text/javascript,alert(1)", "blob:https://attacker.example/id"].each do |url|
      with_source_tree do |root|
        path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
        source = File.read(path)
        source = replace_once(
          source,
          'policy.script_src :self, "https://link.tradedoubler.com"',
          "policy.script_src :self, #{url.inspect}",
        )
        File.write(path, source)

        result = Deploy::SecurityHeadersSourceCheck.run(root:)
        assert_includes result.failures.join("\n"), "overly broad script-src", url
      end
    end
  end

  def test_symlinked_parent_directory_is_rejected
    with_source_tree do |root|
      shared = File.join(root, "RAILS", "__shared")
      outside = File.join(root, "external-shared")
      FileUtils.cp_r(shared, outside)
      FileUtils.rm_rf(shared)
      File.symlink(outside, shared)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "parent path is not a real directory"
    end
  end

  def test_source_reader_refuses_a_symlinked_policy
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      target = File.join(root, "external-csp.rb")
      File.write(target, File.read(path))
      File.unlink(path)
      File.symlink(target, path)

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "refuses non-regular or symlinked source"
    end
  end

  def test_source_reader_rejects_invalid_utf8
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::SHARED_CSP)
      File.binwrite(path, [0xFF].pack("C"))

      result = Deploy::SecurityHeadersSourceCheck.run(root:)
      assert_includes result.failures.join("\n"), "invalid UTF-8"
    end
  end

  def test_missing_edge_hsts_is_rejected
    with_source_tree do |root|
      path = File.join(root, Deploy::SecurityHeadersSourceCheck::RELAYD)
      source = File.read(path)
      source = replace_once(
        source,
        'match response header set "Strict-Transport-Security" value "max-age=31536000; includeSubDomains; preload"',
        "",
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
