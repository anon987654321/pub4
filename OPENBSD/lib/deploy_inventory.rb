# frozen_string_literal: true

require "json"
require "yaml"

module Deploy
  class Inventory
    # Single canonical inventory implementation. MASTER's support path is a
    # require-only adapter into this file, so both toolchains share behavior.
    App = Struct.new(:name, :title, :domain, :port, :deploy_script, :deploy_root, :public, keyword_init: true) unless defined?(App)

    attr_reader :root

    def initialize(root:)
      @root = root
    end

    def apps
      @apps ||= load_apps
    end

    def app_names
      apps.map(&:name)
    end

    def master_apps(path: File.join(root, "OPENBSD", "deploy_inventory.json"))
      data = JSON.parse(File.read(path))
      data.fetch("apps").map { |entry| app_from_json(entry) }
    end

    # One tree's `## <tree>` section of the root TREE_CONTRACTS.md, or nil.
    # MASTER/web has no README: this section is its human entry, and replaced
    # MASTER/web/CLAUDE.md when the tree contracts were folded (2b168b77f2).
    def tree_contract(tree)
      path = File.join(root, "TREE_CONTRACTS.md")
      return unless File.file?(path)

      File.read(path, encoding: "UTF-8")[/^## #{Regexp.escape(tree)}\n.*?(?=^## |\z)/m]
    end

    private

    REQUIRED_APP_KEYS = %w[domain port deploy_script deploy_root].freeze unless defined?(REQUIRED_APP_KEYS)

    # apps.yml is the fleet's source of truth and is edited by hand, so a missing
    # key has to say which app and which key. It used to raise a bare
    # `KeyError: key not found: "deploy_root"` six frames inside a check, which reads
    # as a broken check rather than an incomplete entry — every check that reads the
    # inventory died the same anonymous way.
    # `deployed: false` marks an app that lives in the tree and runs CI but has no
    # host, port lane or rc.d script yet; the deploy inventory is what vm23 serves.
    def load_apps
      path = File.join(root, "RAILS", "apps.yml")

      data = YAML.safe_load(File.read(path))
      deployable = data.fetch("apps").reject { |_name, meta| meta.is_a?(Hash) && meta["deployed"] == false }
      deployable.map { |name, metadata| app_from_yaml(name, metadata) }
    end

    def app_from_yaml(name, metadata)
      missing = REQUIRED_APP_KEYS.reject { |key| metadata.is_a?(Hash) && metadata.key?(key) }
      unless missing.empty?
        raise KeyError, "RAILS/apps.yml: app #{name.inspect} is missing #{missing.join(', ')} " \
                        "(every app needs #{REQUIRED_APP_KEYS.join(', ')})"
      end

      App.new(
        name:,
        title: metadata["title"],
        domain: metadata.fetch("domain"),
        port: metadata.fetch("port").to_i,
        deploy_script: metadata.fetch("deploy_script"),
        deploy_root: metadata.fetch("deploy_root"),
        public: metadata.fetch("public", false)
      )
    end

    def app_from_json(entry)
      App.new(
        name: entry.fetch("name"),
        title: entry["title"],
        domain: entry.fetch("domain"),
        port: entry.fetch("port").to_i,
        deploy_script: entry["deploy_script"],
        deploy_root: entry["deploy_root"]
      )
    end
  end
end
