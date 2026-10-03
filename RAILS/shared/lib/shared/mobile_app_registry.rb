# frozen_string_literal: true

require "yaml"

module Shared
  module MobileAppRegistry
    App = Data.define(
      :key,
      :name,
      :host,
      :url,
      :kind,
      :vertical,
      :android_package,
      :android_certificate_env,
      :ios_bundle_id,
      :ios_team_id_env
    )

    ROOT = File.expand_path("../../..", __dir__)
    CONFIG = File.join(ROOT, "mobile", "apps.yml")

    module_function

    def all
      @all ||= YAML.safe_load_file(CONFIG, aliases: false).fetch("apps").map do |key, raw|
        App.new(
          key.to_sym,
          raw.fetch("name"),
          raw.fetch("host"),
          raw.fetch("url"),
          raw.fetch("kind").to_sym,
          raw["vertical"]&.to_sym,
          raw.fetch("android").fetch("package"),
          raw.fetch("android").fetch("certificate_env"),
          raw.fetch("ios").fetch("bundle_id"),
          raw.fetch("ios").fetch("team_id_env")
        )
      end.freeze
    end

    def for_host(host)
      normalized = host.to_s.downcase.split(":", 2).first.to_s.delete_suffix(".")
      all.find { |app| app.host == normalized }
    end

    def fetch(key)
      all.find { |app| app.key == key.to_sym } || raise(KeyError, "unknown mobile app: #{key}")
    end

    def assetlinks_json(host)
      app = for_host(host)
      return "[]\n" unless app

      fingerprints = ENV.fetch(app.android_certificate_env, "")
        .split(",")
        .map(&:strip)
        .reject(&:empty?)

      return "[]\n" if fingerprints.empty?

      require "json"
      JSON.pretty_generate([
        {
          "relation" => ["delegate_permission/common.handle_all_urls"],
          "target" => {
            "namespace" => "android_app",
            "package_name" => app.android_package,
            "sha256_cert_fingerprints" => fingerprints
          }
        }
      ]) + "\n"
    end

    def apple_app_site_association(host)
      app = for_host(host)
      return empty_apple_association unless app

      team_id = ENV.fetch(app.ios_team_id_env, "").strip
      return empty_apple_association if team_id.empty?

      require "json"
      JSON.pretty_generate(
        "applinks" => {
          "apps" => [],
          "details" => [
            {
              "appID" => "#{team_id}.#{app.ios_bundle_id}",
              "paths" => ["*"]
            }
          ]
        }
      ) + "\n"
    end

    def empty_apple_association
      '{"applinks":{"apps":[],"details":[]}}' + "\n"
    end
  end
end
