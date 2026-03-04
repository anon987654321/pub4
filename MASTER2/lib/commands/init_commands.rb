# frozen_string_literal: true

require "fileutils"
require "pathname"

module Commands
  class InitCommands
    DEFAULT_PROJECT_DIRNAME = "axiom_project"
    DEFAULT_CONFIG_FILENAME = "axiom.yml"

    DEFAULT_AXIOM_LIST = [
      "prefer_small_interfaces",
      "avoid_global_state",
      "fail_fast"
    ].freeze

    def initialize(file_system: FileUtils)
      @file_system = file_system
    end

    def init(target_directory: Dir.pwd, project_name: DEFAULT_PROJECT_DIRNAME)
      project_root = Pathname(target_directory).join(project_name)

      created_paths = []
      created_paths.concat(create_directory_structure(project_root))
      created_paths.concat(create_default_config(project_root))
      created_paths.concat(create_readme(project_root))

      {
        project_root: project_root.to_s,
        created_paths: created_paths.uniq.sort,
        violation_count: 0
      }
    end

    def validate_config(config_hash)
      axiom_list = Array(config_hash.fetch("axioms", []))
      cost_ratio = compute_cost_ratio(config_hash)

      violation_count = 0
      violation_count += 1 if axiom_list.empty?
      violation_count += 1 if cost_ratio <= 0

      {
        axiom_list: axiom_list,
        cost_ratio: cost_ratio,
        violation_count: violation_count
      }
    end

    private

    attr_reader :file_system

    def create_directory_structure(project_root)
      created_paths = []

      [
        project_root,
        project_root.join("lib"),
        project_root.join("spec")
      ].each do |directory_path|
        next if directory_path.exist?

        file_system.mkdir_p(directory_path)
        created_paths << directory_path.to_s
      end

      created_paths
    end

    def create_default_config(project_root)
      config_path = project_root.join(DEFAULT_CONFIG_FILENAME)
      return [] if config_path.exist?

      config_contents = <<~YAML
        axioms:
      YAML

      DEFAULT_AXIOM_LIST.each do |axiom_name|
        config_contents << "  - #{axiom_name}\n"
      end

      config_contents << <<~YAML

        cost_ratio: 1.0
      YAML

      file_system.write(config_path, config_contents)
      [config_path.to_s]
    end

    def create_readme(project_root)
      readme_path = project_root.join("README.md")
      return [] if readme_path.exist?

      readme_contents = <<~MD
        # #{project_root.basename}

        ## Getting started

        - Edit `#{DEFAULT_CONFIG_FILENAME}` to define your axioms.
      MD

      file_system.write(readme_path, readme_contents)
      [readme_path.to_s]
    end

    def compute_cost_ratio(config_hash)
      raw_cost_ratio = config_hash.fetch("cost_ratio", 1.0)
      Float(raw_cost_ratio)
    rescue ArgumentError, TypeError
      0.0
    end
  end
end