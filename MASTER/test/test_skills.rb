# frozen_string_literal: true

require "fileutils"
require_relative "test_helper"

class TestSkills < Minitest::Test
  def test_frontmatter_parses_skill_metadata
    parsed = Master::Ground::Frontmatter.parse(<<~MD)
      ---
      name: alpha
      description: first skill
      ---
      body
    MD

    assert_equal "alpha", parsed[:meta]["name"]
    assert_equal "first skill", parsed[:meta]["description"]
    assert_equal "body", parsed[:body]
  end

  def test_discover_loads_registry_skills
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        ---
        skills_registry:
          skills:
            - name: alpha
              description: first skill
              triggers: ["alpha"]
              body: alpha body
            - name: beta
              description: second skill
              triggers: ["beta"]
              body: beta body
      YAML

      skills = Master::CLI::Skills.new(root:)
      loaded = skills.discover!

      assert_equal %w[alpha beta], loaded.map { |skill| skill[:name] }
      assert_equal "alpha body", skills.body_for("alpha")
    end
  end

  def test_discover_ignores_legacy_skill_markdown
    Dir.mktmpdir do |root|
      skills_dir = File.join(root, "data", "skills")
      FileUtils.mkdir_p(skills_dir)
      File.write(File.join(skills_dir, "scan.md"), <<~MD)
        ---
        name: scan
        description: scan files and directories
        ---
      MD
      File.write(File.join(root, "data", "patterns.yml"), <<~YAML)
        ---
        skills_registry:
          skills:
            - name: registry_only
              description: registry authority
              triggers: ["registry"]
              body: from registry
      YAML

      skills = Master::CLI::Skills.new(root:)
      loaded = skills.discover!

      assert_equal ["registry_only"], loaded.map { |skill| skill[:name] }
    end
  end

  def test_recently_used_skills_sort_first
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        ---
        skills_registry:
          skills:
            - name: alpha
              description: alpha
              triggers: ["alpha"]
            - name: beta
              description: beta
              triggers: ["beta"]
      YAML

      skills = Master::CLI::Skills.new(root:)
      skills.discover!
      skills.record_used("beta")
      reloaded = Master::CLI::Skills.new(root:)

      assert_equal "beta", reloaded.discover!.first[:name]
    end
  end
end
