# frozen_string_literal: true

require "net/http"
require "socket"
require "yaml"
require_relative "../../../OPENBSD/lib/deploy_inventory"
require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../../MASTER/tools/crawl_support"
require_relative "../support/fleet"
require_relative "../support/page_inventory"

module Deploy
  # Server-side performance budget over the same guest GET crawl manifest the
  # page simulation uses. It measures what the server actually delivered:
  # response time and bytes, before browser work is involved.
  class ServerResponseBudgetGate
    ROOT = File.expand_path("../../..", __dir__)
    LIMITS = File.join(ROOT, "MASTER", "data", "limits.yml")
    DEFAULTS = { "p95_ms" => 1500, "p95_bytes" => 1_048_576 }.freeze

    def self.run = new.run

    def run
      @result = GateResult.new
      pages = Deploy::PageInventory.guest_liveable.group_by { |page| page[:app] }
      ports = Deploy::Inventory.new(root: ROOT).apps.to_h { |app| [app.name, app.port] }
      ports["master"] = 53_187

      pages.each do |app, app_pages|
        port = ports[app]
        unless port
          @result.fail("server_response_budget: #{app} has no port")
          next
        end
        unless port_open?(port)
          @result.inconclusive!("server_response_budget: #{app} port #{port} closed — server timing not measured")
          next
        end

        rows = app_pages.filter_map { |page| request(app, port, page) }
        judge(app, rows)
      end
      @result
    rescue StandardError => e
      @result.errored!("server_response_budget: #{e.class}: #{e.message.lines.first.to_s.strip}")
    end

    private

    def request(app, port, page)
      path = page[:path].to_s
      uri = URI("http://127.0.0.1:#{port}#{path}")
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Host"] = page[:host] || Fleet.public_host(app)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 15) { |http| http.request(req) }
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
      bytes = response.body.to_s.bytesize

      unless response.code.to_i.between?(200, 399)
        @result.fail("server_response_budget: #{app} #{path} returned HTTP #{response.code}")
        return nil
      end

      @result.checked!(1)
      { path:, ms: elapsed, bytes: }
    rescue StandardError => e
      @result.fail("server_response_budget: #{app} #{path} #{e.class}: #{e.message.lines.first.to_s.strip}")
      nil
    end

    def judge(app, rows)
      return @result.inconclusive!("server_response_budget: #{app} produced no measurable guest responses") if rows.empty?

      budget = limits
      p95_ms = percentile(rows.map { |row| row[:ms] })
      p95_bytes = percentile(rows.map { |row| row[:bytes] })

      @result.fail("server_response_budget: #{app} p95=#{p95_ms.round}ms over #{budget.fetch("p95_ms")}ms") if p95_ms > budget.fetch("p95_ms")
      @result.fail("server_response_budget: #{app} p95=#{p95_bytes}B over #{budget.fetch("p95_bytes")}B") if p95_bytes > budget.fetch("p95_bytes")

      slow = rows.max_by { |row| row[:ms] }
      large = rows.max_by { |row| row[:bytes] }
      @result.warn(
        "server_response_budget: #{app} n=#{rows.size} p95=#{p95_ms.round}ms/#{p95_bytes}B "         "max=#{slow[:path]} #{slow[:ms].round}ms, largest=#{large[:path]} #{large[:bytes]}B"
      )
    end

    def percentile(values)
      sorted = values.sort
      sorted.fetch([(sorted.length * 0.95).ceil - 1, sorted.length - 1].min)
    end

    def limits
      data = YAML.safe_load_file(LIMITS) || {}
      DEFAULTS.merge(data.fetch("server_response_budget", {}))
    rescue StandardError => e
      @result.fail("server_response_budget: #{LIMITS} could not be read: #{e.class}: #{e.message}")
      DEFAULTS
    end

    def port_open?(port)
      socket = TCPSocket.new("127.0.0.1", port)
      socket.close
      true
    rescue SystemCallError
      false
    end
  end
end
