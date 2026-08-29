# frozen_string_literal: true

require "yaml"

# The fleet, read from apps.yml, for anything that needs a port or a local URL.
#
# port_inventory exists because a file that restates the whole fleet is a second
# inventory, and this repo has shipped the outage that follows from one drifting.
# Its own message offers two remedies — read them from apps.yml, or register the
# file — and until now only the second was possible: apps.yml had a *validator*
# and no reader, so every consumer that wanted a port wrote its own map. Three
# did, and all three were flagged on the same run.
#
# So this is the missing half. It is deliberately dependency-free — no
# GateResult, no bundle — because its callers include probes and the standalone
# RAILS/test suite, which run under bare ruby outside any app bundle.
#
# MASTER's face is here too. It is not a Rails app and has no apps.yml row, so
# every consumer that wanted all four surfaces had to add the fourth by hand;
# stating it once here is what makes `local_urls` complete enough to replace the
# hand-written maps rather than merely shorten them.
module Fleet
  ROOT = File.expand_path("../..", __dir__)
  APPS_YML = File.join(ROOT, "apps.yml")

  MASTER_NAME = "master"
  MASTER_PORT = 53_187
  LOOPBACK = "127.0.0.1"

  module_function

  # Every app in apps.yml that declares a port, keyed by app name.
  def app_ports
    data = YAML.safe_load_file(APPS_YML, permitted_classes: [Symbol])
    apps = data.fetch("apps", {})
    raise "apps.yml: 'apps' is not a mapping" unless apps.is_a?(Hash)

    apps.each_with_object({}) do |(name, meta), out|
      next unless meta.is_a?(Hash)

      port = meta["port"]
      out[name.to_s] = port.to_i if port
    end
  end

  # The three apps plus MASTER's face, which is the set the browser probes walk.
  def ports
    app_ports.merge(MASTER_NAME => MASTER_PORT)
  end

  def port(name)
    ports.fetch(name.to_s) { raise KeyError, "no port for #{name.inspect} in apps.yml" }
  end

  def origin(name)
    "http://#{LOOPBACK}:#{port(name)}"
  end

  # Every surface's root URL on the loopback, keyed by name.
  def local_urls
    ports.transform_values { |p| "http://#{LOOPBACK}:#{p}/" }
  end

  # A named map of surface → URL, where each value is a path appended to that
  # surface's origin. Written this way so a caller states routes rather than
  # numbers: { "brgen home" => ["brgen", "/"] } and never a literal port.
  def urls(routes)
    routes.transform_values do |(name, path)|
      "#{origin(name)}#{path}"
    end
  end
end
