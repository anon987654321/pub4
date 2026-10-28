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

  def test_trigger_for_non_string_input_returns_no_match
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: alpha
              description: first skill
              triggers: ["alpha"]
              body: alpha body
      YAML

      skills = Master::CLI::Skills.new(root:)
      skills.discover!

      assert_empty skills.trigger_for(nil)
      assert_empty skills.trigger_for(Object.new)
    end
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
      assert_match(/\A[0-9a-f]{64}\z/, skills.find("alpha")[:revision])
      refute_equal skills.find("alpha")[:revision], skills.find("beta")[:revision]
    end
  end

  # The three design skills live in the real registry, not a fixture: the
  # routing and the house prohibitions are properties of the shipped text.
  DESIGN_SKILLS = {
    "algorithmic-art" => [
      "make a flow field from the git log", "generative art for the cover",
      "create a procedural sketch", "show me a particle system",
    ],
    "brand" => [
      "is this on-brand", "update the visual identity", "apply our branding",
      "follow the brand guidelines",
    ],
    "canvas" => [
      "design a poster for the release", "an og image for the post",
      "make album cover art", "prepare a print design",
    ],
  }.freeze

  def registry = Master.load_yaml(File.join(Master::ROOT, "data", "patterns.yml")).fetch("skills_registry")

  def shipped_skills = @shipped_skills ||= Master::CLI::Skills.new(root: Master::ROOT).tap(&:discover!)

  def test_design_skills_route_from_plain_requests
    DESIGN_SKILLS.each do |name, requests|
      requests.each do |request|
        assert_includes shipped_skills.trigger_for(request).map { |skill| skill[:name] }, name, request
      end
    end
  end

  # body_for cuts at 4000 characters, so the registry text is what must fit.
  def test_design_skill_bodies_fit_the_injection_and_keep_the_house_prohibitions
    DESIGN_SKILLS.each_key do |name|
      body = registry.fetch("skills").find { |skill| skill["name"] == name }.fetch("body")
      assert_operator body.length, :<=, 4000, "#{name} is cut by the injection"
      refute_match(/poppins|lora|georgia|times/i, body, "#{name} names a face the house forbids")
    end
  end

  def test_registry_count_matches_the_skills_it_lists
    assert_equal registry.dig("meta", "count"), registry.fetch("skills").size
  end

  # data/ holds no markdown but SOUL, CANON, IDENTITY and principles/, and
  # RUNTIME_DOCS_YAML refuses the rest at error severity, so a skill written as
  # data/skills/*.md or data/skills/*/SKILL.md is not a skill.
  def test_discover_ignores_skill_markdown_under_data
    Dir.mktmpdir do |root|
      skills_dir = File.join(root, "data", "skills")
      FileUtils.mkdir_p(File.join(skills_dir, "lint"))
      File.write(File.join(skills_dir, "scan.md"), <<~MD)
        ---
        name: scan
        description: scan files and directories
        ---
      MD
      File.write(File.join(skills_dir, "lint", "SKILL.md"), <<~MD)
        ---
        name: lint
        description: lint staged lines
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
  def test_malformed_trigger_does_not_disable_valid_trigger
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: bad
              description: bad trigger
              triggers: ["["]
              body: bad
            - name: good
              description: good trigger
              triggers: ["alpha"]
              body: good
      YAML

      bus = Class.new do
        attr_reader :events
        def initialize = @events = []
        def publish(name, payload = {}) = @events << [name, payload]
      end.new

      skills = Master::CLI::Skills.new(root:, event_bus: bus)
      skills.discover!
      matches = skills.trigger_for("alpha")

      assert_equal ["good"], matches.map { |skill| skill[:name] }
      event = bus.events.find { |name, _| name == "skills:trigger_invalid" }
      refute_nil event
      assert_equal "bad", event.last[:skill]
      assert_equal "[", event.last[:trigger]
    end
  end

  def test_trigger_emits_revision
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: alpha
              description: alpha
              triggers: ["alpha"]
              body: alpha body
      YAML

      bus = Class.new do
        attr_reader :events
        def initialize = @events = []
        def publish(name, payload = {}) = @events << [name, payload]
      end.new

      skills = Master::CLI::Skills.new(root:, event_bus: bus)
      skills.discover!
      skills.trigger_for("alpha")
      event = bus.events.find { |name, _| name == "skills:triggered" }
      assert_equal "alpha", event.last[:skill]
      assert_match(/\A[0-9a-f]{64}\z/, event.last[:revision])
    end
  end

  def test_execution_contract_changes_skill_revision
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      path = File.join(data_dir, "patterns.yml")
      common = <<~YAML
        skills_registry:
          skills:
            - name: alpha
              description: alpha
              triggers: ["alpha"]
              body: alpha body
              execution_contract:
                schema_version: 1
                version: "1.0.0"
                status: candidate
                risk: low
                required_capabilities: [read]
                laws: [ROBUSTNESS]
                fixtures: [test/test_skills.rb]
      YAML
      File.write(path, common)
      approval_path = File.join(root, "skill_approvals.yml")
      first = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!).find("alpha")

      File.write(path, common.sub('version: "1.0.0"', 'version: "1.0.1"'))
      second = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!).find("alpha")

      refute_equal first[:revision], second[:revision]
      assert_equal :candidate, first[:contract].status
      assert_predicate first[:contract], :promotable?
      assert_equal ["ROBUSTNESS"], first[:contract].law_ids
      assert_equal ["test/test_skills.rb"], first[:contract].fixture_refs
      refute_predicate first[:contract], :permitted_for_trigger?
      skills = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!)
      refute_includes skills.trigger_for("alpha").map { |skill| skill[:name] }, "alpha"
      assert_nil skills.body_for("alpha")
    end
  end

  def test_blocked_skill_contract_prevents_trigger_and_body_injection
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: blocked_skill
              description: blocked
              triggers: ["blocked phrase"]
              body: private skill instructions
              execution_contract:
                schema_version: 1
                version: "1.0.0"
                status: blocked
                risk: high
                required_capabilities: [write]
                laws: [ROBUSTNESS]
                fixtures: [test/test_skills.rb]
      YAML

      bus = Class.new do
        attr_reader :events
        def initialize = @events = []
        def publish(name, payload = {}) = @events << [name, payload]
      end.new
      skills = Master::CLI::Skills.new(root:, event_bus: bus)
      skills.discover!

      assert_empty skills.trigger_for("please use blocked phrase")
      assert_nil skills.body_for("blocked_skill")
      assert_equal :blocked, skills.contract_for("blocked_skill")[:status]
      event = bus.events.find { |name, _| name == "skills:contract_refused" }
      refute_nil event
      assert_equal :blocked, event.last[:status]
      refute_includes bus.events.inspect, "private skill instructions"
    end
  end

  def test_invalid_skill_contract_is_quarantined_explicitly
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: malformed
              description: malformed metadata
              triggers: ["quarantined phrase"]
              body: should not inject
              execution_contract:
                version: "not-a-version"
                status: self_approved
                mystery_field: value
      YAML

      bus = Class.new do
        attr_reader :events
        def initialize = @events = []
        def publish(name, payload = {}) = @events << [name, payload]
      end.new
      skills = Master::CLI::Skills.new(root:, event_bus: bus)
      skills.discover!

      assert_equal :invalid, skills.contract_for("malformed")[:status]
      assert_empty skills.trigger_for("quarantined phrase")
      assert_nil skills.body_for("malformed")
      assert bus.events.any? { |name, _| name == "skills:contract_invalid" }
    end
  end


  def test_declared_skill_requires_exact_external_revision_approval
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      registry_path = File.join(data_dir, "patterns.yml")
      approval_path = File.join(root, "operator", "skill_approvals.yml")
      registry = <<~YAML
        skills_registry:
          skills:
            - name: alpha
              description: alpha
              triggers: ["alpha"]
              body: alpha body
              execution_contract:
                schema_version: 1
                version: "1.0.0"
                status: candidate
                risk: low
                required_capabilities: [read]
                laws: [ROBUSTNESS]
                fixtures: [test/test_skills.rb]
      YAML
      File.write(registry_path, registry)

      bus = Class.new do
        attr_reader :events
        def initialize = @events = []
        def publish(name, payload = {}) = @events << [name, payload]
      end.new
      unapproved = Master::CLI::Skills.new(root:, event_bus: bus, approval_path:)
      skill = unapproved.discover!.fetch(0)
      assert_empty unapproved.trigger_for("alpha")
      assert_nil unapproved.body_for("alpha")
      inspection = unapproved.contract_for("alpha")
      refute inspection[:operator_approved]
      refute inspection[:active_for_trigger]
      assert_equal "revision_not_approved", bus.events.find { |name, _| name == "skills:contract_refused" }.last[:reason]

      FileUtils.mkdir_p(File.dirname(approval_path))
      File.write(approval_path, <<~YAML)
        schema_version: 1
        approvals:
          - name: alpha
            revision: "#{skill[:revision]}"
            approved_by: test-operator
            approved_at: "2026-10-26T12:00:00Z"
      YAML
      approved = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!)
      assert_equal ["alpha"], approved.trigger_for("alpha").map { |row| row[:name] }
      assert_equal "alpha body", approved.body_for("alpha")
      inspection = approved.contract_for("alpha")
      assert inspection[:operator_approved]
      assert inspection[:active_for_trigger]
      assert_equal "test-operator", inspection.dig(:approval, :approved_by)
      assert_equal "2026-10-26T12:00:00Z", inspection.dig(:approval, :approved_at)
      assert_equal "alpha", approved.contract_inventory.fetch(0)[:name]

      File.write(registry_path, registry.sub("body: alpha body", "body: changed content"))
      changed = Master::CLI::Skills.new(root:, approval_path:).tap(&:discover!)
      refute_equal skill[:revision], changed.find("alpha")[:revision]
      assert_empty changed.trigger_for("alpha"), "a changed revision requires a fresh operator approval"
    end
  end

  def test_invalid_operator_approval_manifest_fails_closed_for_declared_skills
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: alpha
              description: alpha
              triggers: ["alpha"]
              body: alpha body
              execution_contract:
                version: "1.0.0"
                status: candidate
                risk: low
                required_capabilities: [read]
                laws: [ROBUSTNESS]
                fixtures: [test/test_skills.rb]
      YAML
      approval_path = File.join(root, "skill_approvals.yml")
      File.write(approval_path, "schema_version: 9\napprovals: []\n")
      bus = Class.new do
        attr_reader :events
        def initialize = @events = []
        def publish(name, payload = {}) = @events << [name, payload]
      end.new

      skills = Master::CLI::Skills.new(root:, event_bus: bus, approval_path:)
      skills.discover!
      assert_empty skills.trigger_for("alpha")
      assert bus.events.any? { |name, _| name == "skills:approval_manifest_invalid" }
    end
  end


  def test_symlinked_operator_approval_manifest_fails_closed
    Dir.mktmpdir do |root|
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)
      File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
        skills_registry:
          skills:
            - name: alpha
              description: alpha
              triggers: ["alpha"]
              body: alpha body
              execution_contract:
                version: "1.0.0"
                status: candidate
                risk: low
                required_capabilities: [read]
                laws: [ROBUSTNESS]
                fixtures: [test/test_skills.rb]
      YAML
      valid_path = File.join(root, "valid-approvals.yml")
      File.write(valid_path, "schema_version: 1\napprovals: []\n")
      link_path = File.join(root, "skill_approvals.yml")
      File.symlink(valid_path, link_path)
      bus = Class.new do
        attr_reader :events
        def initialize = @events = []
        def publish(name, payload = {}) = @events << [name, payload]
      end.new

      skills = Master::CLI::Skills.new(root:, event_bus: bus, approval_path: link_path)
      skills.discover!
      assert_empty skills.trigger_for("alpha")
      assert(bus.events.any? do |name, payload|
        name == "skills:approval_manifest_invalid" && payload[:reason] == "symlink"
      end)
    end
  end


end
