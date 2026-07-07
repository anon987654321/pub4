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

    def master_apps(path: File.join(root, "DEPLOY", "master.json"))
      data = JSON.parse(File.read(path))
      data.fetch("apps").map do |entry|
        App.new(
          name: entry.fetch("name"),
          domain: entry["domain"],
          port: entry.fetch("port").to_i
        )
      end
    end

    private

    def load_apps
      data = YAML.safe_load(File.read(File.join(root, "DEPLOY", "rails", "apps.yml")))
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
  end
end
