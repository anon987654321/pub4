#!/usr/bin/env ruby
# frozen_string_literal: true

# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "uri"

module Pub4Openbsd
  class PtrOpenbsdAmsterdam
    IPV4_ENDPOINT = "http://ptr4.openbsd.amsterdam"
    IPV6_ENDPOINT = "http://ptr6.openbsd.amsterdam"

    def initialize(ip:, hostname:, apply: false)
      @ip = ip
      @hostname = hostname
      @apply = apply
    end

    def call
      validate!
      request = build_request

      unless apply
        puts JSON.pretty_generate(
          dry_run: true,
          endpoint: endpoint,
          ip: ip,
          hostname: hostname,
          method: request.method,
          note: "Set APPLY_PTR=1 to send this request."
        )
        return true
      end

      response = Net::HTTP.start(request.uri.hostname, request.uri.port, use_ssl: request.uri.scheme == "https") do |http|
        http.request(request)
      end

      puts response.body unless response.body.to_s.empty?
      response.is_a?(Net::HTTPSuccess)
    end

    private

    attr_reader :ip, :hostname, :apply

    def endpoint
      ip.include?(":") ? IPV6_ENDPOINT : IPV4_ENDPOINT
    end

    def build_request
      uri = URI(endpoint)
      uri.query = URI.encode_www_form(ip: ip, hostname: hostname)
      Net::HTTP::Post.new(uri)
    end

    def validate!
      raise ArgumentError, "hostname must end with a dotless DNS name" unless hostname.match?(/\A[a-z0-9.-]+\.[a-z]{2,}\z/i)
      raise ArgumentError, "ip must look like IPv4 or IPv6" unless ip.match?(/\A[0-9a-f:.]+\z/i)
      raise ArgumentError, "refusing localhost PTR" if ip.start_with?("127.") || ip == "::1"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = {
    apply: ENV["APPLY_PTR"] == "1",
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby OPENBSD/ptr_openbsd_amsterdam.rb --ipv4 IP --hostname NAME"
    opts.on("--ipv4 IP", "IPv4 address") { |value| options[:ip] = value }
    opts.on("--ipv6 IP", "IPv6 address") { |value| options[:ip] = value }
    opts.on("--hostname NAME", "PTR hostname, e.g. ns.brgen.no") { |value| options[:hostname] = value }
  end

  parser.parse!

  unless options[:ip] && options[:hostname]
    warn parser
    exit 64
  end

  ok = Pub4Openbsd::PtrOpenbsdAmsterdam.new(
    ip: options.fetch(:ip),
    hostname: options.fetch(:hostname),
    apply: options.fetch(:apply)
  ).call

  exit(ok ? 0 : 1)
end
