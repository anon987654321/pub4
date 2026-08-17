# frozen_string_literal: true

require "English"
require "yaml"
require_relative "../../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class PortInventoryGate
    ROOT = File.expand_path("../../../..", __dir__)
    DEPLOY_INVENTORY = ENV.fetch("DEPLOY_INVENTORY", File.join(ROOT, "OPENBSD", "deploy_inventory.json"))
    OPENBSD_DEPLOY = File.join(ROOT, "OPENBSD", "OPERATOR.sh")
    APPS_YML = File.join(ROOT, "RAILS", "apps.yml")
    RAILS_README = File.join(ROOT, "RAILS", "README.md")
    PWA_BUILDER = File.join(ROOT, "RAILS", "tools", "build_workbox.mjs")
    RELAYD_CONF = File.join(ROOT, "OPENBSD", "etc", "relayd.conf")
    CRAWL_MANIFEST = File.join(ROOT, "RAILS", "crawl_manifest.yml")
    # Health probes that name a loopback port. They must never probe a port no
    # app listens on: a retired port here does not fail loudly, it reports the
    # app down forever, or reports a different app's health under this app's
    # name once the number is reused.
    SMOKE_SCRIPTS = [
      "OPENBSD/bin/smoke-apps.sh",
      "OPENBSD/bin/deploy-smoke.sh",
      "OPENBSD/vps_production_push.sh",
    ].freeze

    # MASTER's face is not a Rails app and has no apps.yml row.
    MASTER_PORT = 53_187

    # Every file that states two or more app ports, and why it is allowed to.
    #
    # A file naming one port is using a number; a file naming the whole fleet is
    # a second inventory, and this repo has shipped the failure that follows
    # from an unchecked one. The rule is not "do not restate the ports" — five
    # of these must restate them to do their job — it is that restating them
    # without being checked against apps.yml is what fails. So each row below is
    # either machine-checked by a method in this class, or carries the reason it
    # cannot be. A new fleet inventory that appears in neither fails the gate.
    #
    # Two entries left this list on 2026-08-10: page_simulation.rb and
    # domain_alignment.rb each held a literal three-app port map. The second one
    # was the gate that exists to prove the fleet agrees, restating the fleet
    # instead of reading it.
    FLEET_INVENTORIES = {
      "RAILS/apps.yml" => "source of truth",
      "OPENBSD/deploy_inventory.json" => "checked: check_master_json",
      "OPENBSD/OPERATOR.sh" => "checked: check_openbsd_ports",
      "OPENBSD/etc/relayd.conf" => "checked: check_relayd_ports",
      "RAILS/crawl_manifest.yml" => "checked: check_crawl_manifest",
      "RAILS/README.md" => "checked: check_readmes",
      "OPENBSD/bin/smoke-apps.sh" => "checked: check_smoke_probes",
      "OPENBSD/bin/deploy-smoke.sh" => "checked: check_smoke_probes",
      "OPENBSD/vps_production_push.sh" => "checked: check_smoke_probes",
      "RAILS/test/deploy_smoke_contract_test.rb" => "asserts the smoke scripts' own content",
      "RAILS/CLAUDE.md" => "prose: the shed-vs-outage triage note",
      "OPENBSD/CLAUDE.md" => "prose: same triage note",
      "OPENBSD/RUNBOOK.md" => "prose: operator reference",
      "OPENBSD/data/debt.yml" => "prose: dated incident records, deliberately frozen",
      "RAILS/gates/data/PAGE_SIM.md" => "generated report",
    }.freeze

    FLEET_SCAN_GLOB = "{RAILS,OPENBSD,MASTER,bin}/**/*.{rb,sh,yml,yaml,json,conf,mjs,js,md,erb,exp}"
    # .master/ is runtime cache and never committed; knowledge/ and output/ are
    # generated. Scanning them reports the model's own transcript as an inventory.
    FLEET_SCAN_SKIP = %r{/(\.git|node_modules|\.master|knowledge|output|public/assets|tmp|log|storage)/}

    RETIRED_ACTIVE_PATHS = [
      "OPENBSD/vps_console_install.exp",
      "OPENBSD/vps_console_poll_install.exp",
      "OPENBSD/usr/local/bin/relayd-watchdog",
      "RAILS/env.sample",
      "RAILS/tools/build_workbox.mjs",
    ].freeze
    # The config files a retired app leaves itself in. This list used to be
    # RETIRED_ACTIVE_PATHS alone — five scripts — and none of them was where the
    # leftover references actually lived. On 2026-08-12, two months after DECISIONS.md
    # recorded "baibl + blognet removed — apps, relayd, acme, nsd, litestream,
    # rc.d, inventories", vm23 still had both users, both home directories
    # (547M and 553M), both rc.d scripts, both /etc/*.env files, both login
    # classes, both certificate symlinks, both DNS zones, and blognet in
    # litestream.yml. The decision was written and half executed, and nothing
    # compared the two.
    RETIRED_CONFIG_PATHS = [
      "OPENBSD/etc/rc.conf.local",
      "OPENBSD/etc/login.conf",
      "OPENBSD/etc/litestream.yml",
      "OPENBSD/etc/relayd.conf",
      "OPENBSD/etc/acme-client.conf",
      "OPENBSD/data/dns.yml",
      "OPENBSD/var/nsd/etc/nsd.conf",
    ].freeze

    RETIRED_APP_NAMES = %w[baibl blognet hjerterom].freeze

    def self.run
      new.run
    end

    def run
      inventory = Inventory.new(root: ROOT)
      apps = inventory.apps
      result = GateResult.new

      check_uniques(result, apps, :name)
      check_uniques(result, apps, :domain)
      check_uniques(result, apps, :port)
      check_ports(result, apps)
      check_master_json(result, apps)
      check_deploy_scripts(result, apps)
      check_openbsd_ports(result, apps)
      check_relayd_ports(result, apps)
      check_crawl_manifest(result, apps)
      check_smoke_probes(result, apps)
      check_fleet_inventories(result, apps)
      check_pwa_builder(result, apps)
      check_readmes(result, apps)
      check_retired_names_not_active(result)
      result
    end

    private

    # relayd is the only one of these mirrors that carries live traffic, and it
    # was the only one nothing checked. Changing a port in apps.yml updates the
    # deploy script, OPERATOR.sh, deploy_inventory.json, the README and the
    # Workbox list — all five verified above — while relayd keeps forwarding to
    # the old number. The gate passes, the deploy succeeds, rcctl reports the
    # app running, and the site serves 502 from the one file no check read.
    def check_relayd_ports(result, apps)
      unless File.file?(RELAYD_CONF)
        result.fail("missing OPENBSD/etc/relayd.conf")
        return
      end

      body = File.read(RELAYD_CONF)
      forwards = body.scan(/forward\s+to\s+<([a-z0-9_]+)>\s+port\s+(\d+)/i)
        .to_h { |name, port| [name, port.to_i] }
      hosts = body.scan(/value\s+"([^"]+)"\s+forward\s+to\s+<([a-z0-9_]+)>/i)
        .each_with_object({}) { |(host, table), acc| acc[host] = table }

      apps.each do |app|
        unless forwards.key?(app.name)
          result.fail("relayd.conf has no `forward to <#{app.name}> port` line")
          next
        end

        actual = forwards.fetch(app.name)
        next if actual == app.port

        result.fail("#{app.name}: relayd.conf forwards to port #{actual}, apps.yml says #{app.port}")
      end

      apps.each do |app|
        table = hosts[app.domain]
        if table.nil?
          result.fail("#{app.name}: relayd.conf does not route Host #{app.domain}")
        elsif table != app.name
          result.fail("#{app.name}: relayd.conf routes #{app.domain} to <#{table}>")
        end
      end
    end

    def check_crawl_manifest(result, apps)
      unless File.file?(CRAWL_MANIFEST)
        result.fail("missing RAILS/crawl_manifest.yml")
        return
      end

      manifest = YAML.safe_load(File.read(CRAWL_MANIFEST), aliases: true)
      declared = manifest.fetch("apps", {})
      apps.each do |app|
        entry = declared[app.name]
        if entry.nil?
          result.fail("crawl_manifest.yml has no target for #{app.name}")
        elsif entry["port"].to_i != app.port
          result.fail("#{app.name}: crawl_manifest.yml port #{entry['port']} must mirror apps.yml #{app.port}")
        end
      end
    end

    # These scripts write a port two ways -- `http://127.0.0.1:38182/up` and a
    # bare `smoke brgen 38182` argument -- so matching only the URL form reads
    # one of them and calls the file checked. Both forms are five digits, which
    # is what makes a plain number scan safe here: a four-digit year or a
    # `-m 5` timeout cannot collide with it.
    PORT_TOKEN = /(?<![\d.])(\d{5})(?![\d])/

    def check_smoke_probes(result, apps)
      by_name = apps.to_h { |app| [app.name, app.port] }
      known = by_name.values + [MASTER_PORT]

      SMOKE_SCRIPTS.each do |relative|
        path = File.join(ROOT, relative)
        unless File.file?(path)
          result.fail("missing smoke script #{relative}")
          next
        end

        File.readlines(path).each_with_index do |line, index|
          numbers = line.scan(PORT_TOKEN).flatten.map(&:to_i).uniq
          next if numbers.empty?

          named = by_name.keys.select { |name| line.include?(name) }
          allowed = named.empty? ? known : named.map { |name| by_name.fetch(name) } + [MASTER_PORT]

          (numbers - allowed).each do |port|
            result.fail(
              "#{relative}:#{index + 1} probes port #{port}, which no app in apps.yml listens on" \
              "#{named.empty? ? '' : " (line names #{named.join(', ')})"}",
            )
          end
        end
      end
    end

    # Tracked files plus untracked ones git would not ignore. That is the right
    # scope as well as the fast one: gitignored trees cannot carry a committed
    # second inventory, and globbing them measured 44,831 files and 40 seconds,
    # almost all of it node_modules and asset builds inside the three app trees.
    # --others is what makes the gate catch a new inventory on the run before it
    # is committed rather than the run after. Falls back to the glob where there
    # is no git — the copy-tree on vm23 is not a checkout.
    def fleet_scan_paths
      tracked = IO.popen(
        ["git", "-C", ROOT, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        &:read
      )
      raise "git unavailable" unless $CHILD_STATUS&.success?

      paths = tracked.split("\0").grep(/\.(rb|sh|ya?ml|json|conf|mjs|js|md|erb|exp)\z/)
      raise "empty tree" if paths.empty?

      paths
    rescue StandardError
      Dir.glob(File.join(ROOT, FLEET_SCAN_GLOB)).map { |path| path.delete_prefix("#{ROOT}/") }
    end

    def check_fleet_inventories(result, apps)
      ports = apps.map { |app| app.port.to_s }
      fleet_scan_paths.each do |relative|
        next if "/#{relative}" =~ FLEET_SCAN_SKIP
        next if FLEET_INVENTORIES.key?(relative)

        path = File.join(ROOT, relative)
        next unless File.file?(path)

        body = begin
          File.read(path)
        rescue StandardError
          next
        end
        next if ports.count { |port| body.include?(port) } < 2

        result.fail(
          "#{relative} states two or more app ports but is not in " \
          "PortInventoryGate::FLEET_INVENTORIES. Either read them from apps.yml, " \
          "or add a row saying which check covers this file — an undeclared " \
          "second inventory is how relayd.conf drifted unnoticed.",
        )
      end
    end

    def check_uniques(result, apps, field)
      apps.group_by { |app| app.public_send(field) }.each do |value, grouped|
        next if grouped.size == 1

        result.fail("#{field} collision #{value}: #{grouped.map(&:name).join(', ')}")
      end
    end

    def check_ports(result, apps)
      apps.each do |app|
        unless app.port.between?(1, 65_535)
          result.fail("#{app.name}: port #{app.port.inspect} must be between 1 and 65535")
        end
      end
    end

    def check_master_json(result, apps)
      unless File.file?(DEPLOY_INVENTORY)
        result.fail("missing OPENBSD/deploy_inventory.json mirror: #{DEPLOY_INVENTORY}")
        return
      end

      master = Inventory.new(root: ROOT).master_apps(path: DEPLOY_INVENTORY)
      expected = apps.sort_by(&:name).map { |app| [app.name, app.domain, app.port] }
      actual = master.sort_by(&:name).map { |app| [app.name, app.domain, app.port] }
      result.fail("OPENBSD/deploy_inventory.json must mirror RAILS/apps.yml active apps") unless actual == expected
    end

    def check_deploy_scripts(result, apps)
      apps.each do |app|
        path = File.join(ROOT, app.deploy_script)
        unless File.file?(path)
          result.fail("#{app.name}: missing deploy script #{app.deploy_script}")
          next
        end

        text = File.read(path)
        {
          "APP_NAME=#{app.name}" => "APP_NAME",
          "APP_DOMAIN=#{app.domain}" => "APP_DOMAIN",
          "APP_PORT=#{app.port}" => "APP_PORT"
        }.each do |needle, label|
          result.fail("#{app.name}: deploy script #{label} must mirror apps.yml") unless text.include?(needle)
        end
      end
    end

    def openbsd_ports
      body = File.read(OPENBSD_DEPLOY)
      match = body.match(/typeset -A APP_PORTS=\(\n(?<ports>.*?)\n\)/m)
      return {} unless match

      match[:ports].lines.each_with_object({}) do |line, ports|
        entry = line.match(/\A\s*(?<name>[a-z0-9_]+)\s+(?<port>\d+)\s*(?:#.*)?\z/i)
        next unless entry

        ports[entry[:name]] = entry[:port].to_i
      end
    end

    def check_openbsd_ports(result, apps)
      unless File.file?(OPENBSD_DEPLOY)
        result.fail("missing OpenBSD deploy script: #{OPENBSD_DEPLOY}")
        return
      end

      ports = openbsd_ports
      result.fail("OPENBSD/OPERATOR.sh missing APP_PORTS map") if ports.empty?
      apps.each do |app|
        result.fail("#{app.name}: missing fixed OpenBSD APP_PORTS entry") unless ports.key?(app.name)
        next unless ports.key?(app.name) && ports.fetch(app.name) != app.port

        result.fail("#{app.name}: OpenBSD APP_PORTS #{ports.fetch(app.name)} must mirror apps.yml #{app.port}")
      end
    end

    def check_pwa_builder(result, apps)
      unless File.file?(PWA_BUILDER)
        result.fail("missing Workbox builder: #{PWA_BUILDER}")
        return
      end

      body = File.read(PWA_BUILDER)
      match = body.match(/const APPS = \[(?<apps>.*?)\]/)
      unless match
        result.fail("RAILS/tools/build_workbox.mjs must expose const APPS")
        return
      end

      actual = match[:apps].scan(/"([^"]+)"/).flatten.sort
      expected = apps.map(&:name).sort
      result.fail("Workbox APPS must mirror RAILS/apps.yml active apps") unless actual == expected
    end

    def check_readmes(result, apps)
      root_readme = File.read(RAILS_README)
      result.fail("RAILS/README.md active app count must mirror apps.yml") unless root_readme.include?("#{apps.size} active production Rails")

      apps.each do |app|
        readme_path = File.join(ROOT, app.deploy_root, "README.md")
        unless File.file?(readme_path)
          result.fail("#{app.name}: missing README.md")
          next
        end

        readme = File.read(readme_path)
        result.fail("#{app.name}: README must point humans to apps.yml feature matrix") unless readme.include?("apps.yml")
        result.fail("#{app.name}: README deploy command must mirror apps.yml") unless readme.include?(app.deploy_script)
        result.fail("#{app.name}: README health check must mirror apps.yml port") unless readme.include?("127.0.0.1:#{app.port}/up")
      end
    end

    def check_retired_names_not_active(result)
      (RETIRED_ACTIVE_PATHS + RETIRED_CONFIG_PATHS).each do |relative|
        path = File.join(ROOT, relative)
        next unless File.file?(path)

        # Comments are exempt. A retired name in a line explaining why it was
        # removed is the record of the removal; a retired name in a directive is
        # the removal not having happened. Matching both would push people to
        # delete the explanation, which is the half worth keeping.
        body = File.read(path, encoding: "UTF-8").lines.reject { |line| line.match?(/\A\s*[#;]/) }.join

        RETIRED_APP_NAMES.each do |name|
          next unless body.match?(/\b#{Regexp.escape(name)}\b/)

          result.fail("#{relative}: retired app #{name} must not appear in active deploy tooling")
        end
      end
    end
  end
end
