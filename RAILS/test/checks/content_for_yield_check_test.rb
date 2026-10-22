# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "check_probe_harness"
require_relative "../../../MASTER/checks/lib/source/content_for_yield"

class ContentForYieldCheckTest < Minitest::Test
  include CheckProbe

  CHECK = Deploy::ContentForYieldCheck

  def tree(view:, layout:)
    Dir.mktmpdir("content-for-yield") do |root|
      FileUtils.mkdir_p(File.join(root, "RAILS/brgen/app/views/layouts"))
      FileUtils.mkdir_p(File.join(root, "RAILS/brgen/app/views"))
      File.write(File.join(root, "RAILS/brgen/app/views/layouts/application.html.erb"), layout)
      File.write(File.join(root, "RAILS/brgen/app/views/home.html.erb"), view)
      with_const(CHECK, :ROOT, root) { yield root }
    end
  end

  def test_a_content_slot_with_a_layout_yield_passes
    tree(
      view: "<% content_for :head do %>x<% end %>\n",
      layout: "<%= yield :head %>\n"
    ) do
      result = CHECK.run
      assert result.ok?, result.failures.join(" | ")
      assert_empty result.unchecked
    end
  end

  def test_a_content_slot_with_no_consumer_fails
    tree(
      view: "<% content_for :widgets do %>x<% end %>\n",
      layout: "<%= yield :head %>\n"
    ) do
      result = CHECK.run
      refute result.ok?
      assert_match(/brgen produces :widgets but no layout consumes it/, result.failures.join(" | "))
    end
  end

  def test_content_for_can_be_consumed_with_content_for_reader
    tree(
      view: "<% content_for :description, \"x\" %>\n",
      layout: "<%= content_for(:description) %>\n"
    ) do
      result = CHECK.run
      assert result.ok?, result.failures.join(" | ")
    end
  end
end
