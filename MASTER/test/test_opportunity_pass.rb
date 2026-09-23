# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"

class OpportunityPassTest < Minitest::Test
  def test_dead_rake_globs_are_real_findings
    Dir.mktmpdir do |root|
      master = File.join(root, "MASTER")
      Dir.mkdir(master)
      rakefile = File.join(master, "Rakefile")
      File.write(rakefile, 'files = FileList["test/**/*_spec.rb"]' + "\n")

      result = Master::Fix::OpportunityPass.new(root:).run(target: master, files: [])
      findings = result.value.fetch(:findings)

      assert_equal 1, findings.size
      assert_includes findings.first[:message], "dead Rake glob"
      assert_equal Master::Fix::OpportunityPass::RULE_ID, findings.first[:rule]
    end
  end

  def test_parallel_tool_operator_implementations_are_real_findings
    Dir.mktmpdir do |root|
      master = File.join(root, "MASTER")
      tool = File.join(master, "tools")
      operator = File.join(master, "lib", "operator")
      FileUtils.mkdir_p(tool)
      FileUtils.mkdir_p(operator)
      File.write(File.join(tool, "example.rb"), ("x = 1\n" * 81))
      File.write(File.join(operator, "example.rb"), "module Operator; end\n")

      result = Master::Fix::OpportunityPass.new(root:).run(target: master, files: [])
      findings = result.value.fetch(:findings)

      assert findings.any? { |finding| finding[:message].include?("parallel tool/operator") }
    end
  end
  def test_subtree_fix_does_not_surface_outside_files
    Dir.mktmpdir do |root|
      rails = File.join(root, "RAILS")
      amber = File.join(rails, "amber")
      brgen = File.join(rails, "brgen")
      FileUtils.mkdir_p([amber, brgen])
      amber_file = File.join(amber, "view.html.erb")
      brgen_file = File.join(brgen, "view.html.erb")
      File.write(amber_file, "<p>RAILS/brgen/missing.html.erb</p>\n")
      File.write(brgen_file, "<p>ok</p>\n")

      result = Master::Fix::OpportunityPass.new(root:).run(target: amber, files: [amber_file])
      findings = result.value.fetch(:findings)

      assert findings.all? { |finding| finding[:file] == amber_file }
      refute findings.any? { |finding| finding[:file] == brgen_file }
    end
  end

end
