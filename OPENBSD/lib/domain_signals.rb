# frozen_string_literal: true

# Read-only domain skew for operator status and domain-ghosts.
# No network. Missing files → empty signals (never raise into status).

require "yaml"

module DomainSignals
  module_function

  BRGEN_VERTICALS = %w[tv dating radio takeaway markedsplass maps messenger].freeze

  # Returns a hash; blank arrays mean "say nothing on status".
  def scan(root)
    root = File.expand_path(root)
    inv_path = File.join(root, "OPENBSD/data/domain_inventory.yml")
    apps_path = File.join(root, "RAILS/apps.yml")
    relayd_path = File.join(root, "OPENBSD/etc/relayd.conf")

    inv = load_yaml_hash(inv_path)
    apps = load_yaml_hash(apps_path)
    owned = Array(apps["owned_domains"]).map(&:to_s)

    available = inv.select { |_, v| v.is_a?(Hash) && v["state"].to_s == "available" }.keys.map(&:to_s).sort
    registered = inv.select { |_, v| v.is_a?(Hash) && v["state"].to_s == "registered" }.keys.map(&:to_s).sort
    owned_missing = (owned - inv.keys.map(&:to_s)).sort
    registered_not_owned = (registered - owned).sort

    relay_hosts = []
    if File.file?(relayd_path)
      File.foreach(relayd_path, encoding: "UTF-8", invalid: :replace, replace: "") do |line|
        relay_hosts << Regexp.last_match(1) if line =~ /match request header "Host" value "([^"]+)"/
      end
    end
    relay_hosts = relay_hosts.uniq.sort

    known = owned.dup
    owned.each { |d| known << "www.#{d}" }
    known << "ai.brgen.no"
    BRGEN_VERTICALS.each { |v| known << "#{v}.brgen.no" }
    relay_residual = (relay_hosts - known).sort

    {
      available: available,
      registered: registered,
      owned: owned,
      owned_missing_from_inventory: owned_missing,
      registered_not_owned: registered_not_owned,
      relay_hosts: relay_hosts,
      relay_residual: relay_residual
    }
  rescue StandardError
    {
      available: [],
      registered: [],
      owned: [],
      owned_missing_from_inventory: [],
      registered_not_owned: [],
      relay_hosts: [],
      relay_residual: []
    }
  end

  # Factual status lines only when something is skewed. Empty array = silence.
  def status_lines(root)
    s = scan(root)
    lines = []
    unless s[:registered_not_owned].empty?
      list = s[:registered_not_owned].join(", ")
      lines << "domains: registered but not owned: #{list}"
    end
    unless s[:owned_missing_from_inventory].empty?
      list = s[:owned_missing_from_inventory].join(", ")
      lines << "domains: owned missing from inventory: #{list}"
    end
    unless s[:relay_residual].empty?
      list = s[:relay_residual].join(", ")
      lines << "relay: residual Host #{list}"
    end
    lines
  end

  def load_yaml_hash(path)
    return {} unless File.file?(path)

    data = YAML.safe_load_file(path)
    data.is_a?(Hash) ? data : {}
  end
end
