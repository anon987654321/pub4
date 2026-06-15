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

  def test_discover_refreshes_loaded_skills_without_duplicates
    Dir.mktmpdir do |root|
      skills_dir = File.join(root, "skills")
      FileUtils.mkdir_p(File.join(skills_dir, "alpha"))
      File.write(File.join(skills_dir, "alpha", "SKILL.md"), <<~MD)
        ---
        name: alpha
        description: first skill
        ---
      MD

      skills = Master::Now::Skills.new(root: root)
      first = skills.discover!
      assert_equal ["alpha"], first.map { |skill| skill[:name] }

      FileUtils.mkdir_p(File.join(skills_dir, "beta"))
      File.write(File.join(skills_dir, "beta", "SKILL.md"), <<~MD)
        ---
        name: beta
        description: second skill
        ---
      MD

      second = skills.discover!
      assert_equal ["alpha", "beta"], second.map { |skill| skill[:name] }
    end
  end

  def test_discover_loads_flat_skill_docs
    Dir.mktmpdir do |root|
      skills_dir = File.join(root, "data", "skills")
      FileUtils.mkdir_p(skills_dir)
      File.write(File.join(skills_dir, "scan.md"), <<~MD)
        ---
        name: scan
        description: scan files and directories
        ---
      MD

      skills = Master::Now::Skills.new(root: root)
      loaded = skills.discover!

      assert_equal ["scan"], loaded.map { |skill| skill[:name] }
      assert_equal "scan files and directories", loaded.first[:description]
    end
  end
end
