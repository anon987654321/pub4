# frozen_string_literal: true

require "json"
require "yaml"

module Deploy
  class Inventory
    App = Struct.new(:name, :title, :domain, :port, :deploy_script, :deploy_root, :public, keyword_init: true)

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

    def standalone_apps(path: File.join(root, "OPENBSD", "deploy_inventory.json"))
      data = JSON.parse(File.read(path))
      Array(data["standalone_apps"]).map { |entry| app_from_json(entry) }
    end

    def all_deploy_apps(path: File.join(root, "OPENBSD", "deploy_inventory.json"))
      master_apps(path: path) + standalone_apps(path: path)
    end

    private

    REQUIRED_APP_KEYS = %w[domain port deploy_script deploy_root].freeze

    # apps.yml is the fleet's source of truth and is edited by hand, so a missing
    # key has to say which app and which key. It used to raise a bare
    # `KeyError: key not found: "deploy_root"` six frames inside a gate, which reads
    # as a broken gate rather than an incomplete entry — every gate that reads the
    # inventory died the same anonymous way.
    def load_apps
      path = File.join(root, "RAILS", "apps.yml")
      data = YAML.safe_load(File.read(path))
      data.fetch("apps").map do |name, metadata|
        missing = REQUIRED_APP_KEYS.reject { |key| metadata.is_a?(Hash) && metadata.key?(key) }
        unless missing.empty?
          raise KeyError, "RAILS/apps.yml: app #{name.inspect} is missing #{missing.join(', ')} " \
                          "(every app needs #{REQUIRED_APP_KEYS.join(', ')})"
        end

        App.new(
          name: name,
          title: metadata["title"],
          domain: metadata.fetch("domain"),
          port: metadata.fetch("port").to_i,
          deploy_script: metadata.fetch("deploy_script"),
          deploy_root: metadata.fetch("deploy_root"),
          public: metadata.fetch("public", false)
        )
      end
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
