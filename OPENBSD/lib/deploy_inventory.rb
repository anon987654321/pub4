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

    def master_apps(path: File.join(root, "OPENBSD", "master.json"))
      data = JSON.parse(File.read(path))
      data.fetch("apps").map { |entry| app_from_json(entry) }
    end

    def standalone_apps(path: File.join(root, "OPENBSD", "master.json"))
      data = JSON.parse(File.read(path))
      Array(data["standalone_apps"]).map { |entry| app_from_json(entry) }
    end

    def all_deploy_apps(path: File.join(root, "OPENBSD", "master.json"))
      master_apps(path: path) + standalone_apps(path: path)
    end

    private

    def load_apps
      data = YAML.safe_load(File.read(File.join(root, "RAILS", "apps.yml")))
      data.fetch("apps").map do |name, metadata|
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
