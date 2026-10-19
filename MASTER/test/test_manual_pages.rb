# frozen_string_literal: true

require "open3"
require_relative "test_helper"

class TestManualPages < Minitest::Test
  REPO = File.expand_path("../..", __dir__)
  EXPECTED = %w[
    MASTER/man/man1/master.1
    MASTER/man/man1/operator.1
    MASTER/man/man1/master-fix.1
    OPENBSD/man/man8/vps-deploy.8
    OPENBSD/man/man8/pub4-admin.8
  ].freeze

  BASE_SYSTEM_PAGES = %w[doas rcctl relayd].freeze

  def manual_paths
    Dir.glob(File.join(REPO, "{MASTER,OPENBSD}/man/man[1-9]/*.[1-9]"))
       .map { |path| path.delete_prefix("#{REPO}/") }.sort
  end

  def test_manual_inventory_is_complete
    assert_equal EXPECTED.sort, manual_paths
  end

  def test_manual_pages_have_required_mdoc_sections_and_matching_section_numbers
    manual_paths.each do |relative|
      path = File.join(REPO, relative)
      body = File.read(path)
      section = File.extname(relative).delete(".")

      assert_match(/^\.Dd .+$/m, body, "#{relative}: missing date")
      title = body.match(/^\.Dt\s+(\S+)\s+([1-9])\s*$/)
      refute_nil title, "#{relative}: missing title and section"
      assert_equal section, title[2], "#{relative}: section disagrees with file extension"
      assert_match(/^\.Os(?:\s|$)/, body, "#{relative}: missing OS macro")

      %w[NAME SYNOPSIS DESCRIPTION].each do |heading|
        assert_includes body, ".Sh #{heading}", "#{relative}: missing #{heading}"
      end
    end
  end

  def test_mandoc_lint_when_mandoc_is_available
    pages = manual_paths.map { |relative| File.join(REPO, relative) }
    begin
      Open3.capture2e("mandoc", "-V")
    rescue Errno::ENOENT
      skip "INCONCLUSIVE: mandoc is unavailable; run this check on OpenBSD"
    end

    pages.each do |page|
      # -Wwarning drops the STYLE tier, whose "referenced manual not found" depends on
      # the host manpath; test_cross_references_name_a_page_that_exists judges those.
      output, status = Open3.capture2e("mandoc", "-Tlint", "-Wwarning", page)
      assert status.success?, "#{page}: mandoc exited unsuccessfully: #{output}"
      assert_empty output, "#{page}: mandoc reported diagnostics: #{output}"
    end
  end

  def test_cross_references_name_a_page_that_exists
    ours = manual_paths.map { |path| File.basename(path).sub(/\.([1-9])\z/) { " #{Regexp.last_match(1)}" } }
    manual_paths.each do |relative|
      File.read(File.join(REPO, relative)).scan(/^\.Xr (\S+) (\d)/).each do |name, section|
        next if BASE_SYSTEM_PAGES.include?(name)

        assert_includes ours, "#{name} #{section}", "#{relative}: .Xr #{name} #{section} names no page in this repo"
      end
    end
  end

  def test_readmes_expose_local_manual_lookup
    master = File.read(File.join(REPO, "MASTER/README.md"))
    openbsd = File.read(File.join(REPO, "OPENBSD/README.md"))

    assert_includes master, 'MANPATH="$PWD/MASTER/man" man master'
    assert_includes openbsd, 'MANPATH="$PWD/OPENBSD/man" man vps-deploy'
  end
end
