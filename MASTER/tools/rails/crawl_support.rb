# frozen_string_literal: true

require "json"
require "yaml"
require_relative "../../checks/support/crawl_support"

module CrawlSupport
  ROOT = File.expand_path("../../..", __dir__)
  MANIFEST = File.join(ROOT, "RAILS", "crawl_manifest.yml")
  APPS_YML = File.join(ROOT, "RAILS", "apps.yml")
  DEPLOY_INVENTORY = File.join(ROOT, "OPENBSD", "deploy_inventory.json")

  module_function

  # Preserve the CLI crawler's diagnostic policy without duplicating socket
  # handling used by live checks. A failed diagnostic must never mask the probe.
  def crawler_port_open?(host, port, timeout: 0.4)
    port_open?(
      host, port, timeout:,
      on_error: ->(error) { Master::Ground::Swallow.log(error, context: __FILE__) }
    )
  end

  def sync_inventory_failures
    out = []
    yml = load_apps_yml
    json_apps = load_master_json.fetch("apps", [])
    json_by_name = json_apps.to_h { |row| [row["name"].to_s, row] }

    json_by_name.each do |name, row|
      meta = yml[name]
      unless meta
        out << "inventory: #{name} in deploy_inventory.json but missing from apps.yml"
        next
      end
      out << "inventory: #{name} port mismatch json=#{row["port"]} yml=#{meta["port"]}" if row["port"].to_i != meta["port"].to_i
      out << "inventory: #{name} domain mismatch json=#{row["domain"]} yml=#{meta["domain"]}" if row["domain"].to_s != meta["domain"].to_s
    end

    yml.each_key do |name|
      next if json_by_name.key?(name)
      next if %w[aight_production_ai multimedia_tts].include?(name)
      out << "inventory: #{name} in apps.yml but missing from deploy_inventory.json"
    end
    out
  end

  def crawl_target(name, base_url, paths, failures)
    paths.each do |spec|
      path = spec.fetch("path")
      url = "#{base_url}#{path}"
      begin
        res = fetch(url)
        code = res.code.to_i
        unless status_ok?(code, spec.fetch("expect_status", 200))
          failures << "#{name} #{path}: HTTP #{code} (want #{spec.fetch("expect_status", 200)})"
          next
        end
        failures << "#{name} #{path}: body missing #{spec["expect_body"].inspect}" unless body_ok?(res.body, spec["expect_body"])
      rescue StandardError => e
        failures << "#{name} #{path}: #{e.class}: #{e.message}"
      end
    end
  end

  def base_url(name, port, apps, public:)
    if public && apps[name]
      "https://#{apps[name]["domain"]}"
    else
      "http://127.0.0.1:#{port}"
    end
  end

  def status_ok?(code, expected)
    Array(expected).map(&:to_i).include?(code.to_i)
  end

  def body_ok?(body, expected)
    return true if expected.nil? || expected.to_s.empty?

    text = body.to_s
    if expected.start_with?("regex:")
      Regexp.new(expected.delete_prefix("regex:")).match?(text)
    else
      text.include?(expected)
    end
  end

  def load_manifest
    YAML.safe_load(File.read(MANIFEST)) || {}
  end

  def load_apps_yml
    YAML.safe_load(File.read(APPS_YML)).fetch("apps")
  end

  def load_master_json
    JSON.parse(File.read(DEPLOY_INVENTORY))
  end

end
