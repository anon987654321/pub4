# frozen_string_literal: true

module Ports
  class ExploreAssistant
    def self.summarize(port)
      new(port).summarize
    end

    def initialize(port)
      @port = port
    end

    def summarize
      lines = []
      lines << "#{port.name} (#{port.version}) in #{port.category&.name} — #{port.comment.presence || 'no comment recorded'}."
      lines << "Maintainer: #{port.maintainer.presence || 'unknown'}."
      lines << "Pkgpath: #{port.pkgpath}."
      lines << dependency_summary
      lines << advisory_summary
      lines << exploration_hint
      lines.compact.join(" ")
    end

    private

    attr_reader :port

    def dependency_summary
      deps = port.dependencies.includes(:depends_on)
      return "No recorded dependencies." if deps.empty?

      runtime = deps.select { |dep| dep.dep_type == "run" }.map { |dep| dep.depends_on.name }
      build = deps.select { |dep| dep.dep_type == "build" }.map { |dep| dep.depends_on.name }
      parts = []
      parts << "Runtime deps: #{runtime.first(6).join(', ')}" if runtime.any?
      parts << "Build deps: #{build.first(4).join(', ')}" if build.any?
      parts.join(". ")
    end

    def advisory_summary
      advisories = port.security_advisories.recent.limit(3)
      return "No recent security advisories in local DB." if advisories.empty?

      "Security notes: #{advisories.map { |adv| "#{adv.identifier} (#{adv.severity})" }.join(', ')}."
    end

    def exploration_hint
      reverse = port.reverse_deps.limit(3).map(&:name)
      return if reverse.empty?

      "Other ports depending on this: #{reverse.join(', ')}."
    end
  end
end