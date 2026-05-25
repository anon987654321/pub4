# frozen_string_literal: true

require "json"
require "time"
require_relative "../master_paths"

module Scope
  Event = Struct.new(:timestamp, :requested_scope, :inferred_scope, :touched_paths, :command_class, :network, :secret_risk, :destructive, keyword_init: true) do
    def to_h
      {
        timestamp: timestamp,
        requested_scope: requested_scope,
        inferred_scope: inferred_scope,
        touched_paths: touched_paths,
        command_class: command_class,
        network: network,
        secret_risk: secret_risk,
        destructive: destructive
      }
    end
  end

  class Ledger
    DESTRUCTIVE = /\b(rm|mv|chmod|chown|truncate|dd|git\s+reset|git\s+clean|git\s+push|delete|trash)\b/i
    NETWORK = /\b(curl|wget|ssh|scp|rsync|git\s+clone|bundle\s+install|npm|pnpm|yarn|gem\s+install)\b/i
    SECRET = /\b(secret|token|api[_-]?key|password|private[_-]?key|\.env)\b/i

    attr_reader :events

    def initialize(requested_scope: [], path: MasterPaths.state("scope_ledger.jsonl"))
      @requested_scope = Array(requested_scope)
      @path = path
      @events = []
    end

    def record(command:, touched_paths: [], inferred_scope: nil)
      event = Event.new(
        timestamp: Time.now.utc.iso8601,
        requested_scope: @requested_scope,
        inferred_scope: inferred_scope || infer_scope(touched_paths),
        touched_paths: touched_paths,
        command_class: classify(command),
        network: command.match?(NETWORK),
        secret_risk: command.match?(SECRET) || touched_paths.any? { |path| path.match?(SECRET) },
        destructive: command.match?(DESTRUCTIVE)
      )
      @events << event
      persist(event)
      event
    end

    def violations
      events.filter do |event|
        next false if @requested_scope.empty?
        event.touched_paths.any? { |path| @requested_scope.none? { |scope| path.start_with?(scope) } }
      end
    end

    private

    def classify(command)
      return "destructive" if command.match?(DESTRUCTIVE)
      return "network" if command.match?(NETWORK)
      "read_or_compute"
    end

    def infer_scope(paths)
      Array(paths).map { |path| path.to_s.split("/").first }.compact.uniq.sort
    end

    def persist(event)
      FileUtils.mkdir_p(File.dirname(@path))
      File.open(@path, "a") { |file| file.puts(JSON.generate(event.to_h)) }
    end
  end
end
