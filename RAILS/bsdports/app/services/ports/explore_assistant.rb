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
      lines << "#{port.name} (#{port.version}) in #{category_name} — #{port.comment.presence || 'no comment recorded'}."
      lines << "Maintainer: #{maintainer_label}."
      lines << "Pkgpath: #{port.pkgpath}."
      lines << dependency_summary
      lines << advisory_summary
      lines << exploration_hint
      lines.compact.join(" ")
    end

    private

    attr_reader :port

    def category_name
      # Prefer preloaded association; fall back without raising under strict_loading.
      if port.association(:category).loaded?
        port.category&.name || "uncategorized"
      else
        Category.where(id: port.category_id).pick(:name) || "uncategorized"
      end
    end

    def maintainer_label
      if port.association(:maintainer).loaded?
        port.maintainer.presence || "unknown"
      elsif port.maintainer_id.present?
        Maintainer.where(id: port.maintainer_id).pick(:name) || "unknown"
      else
        "unknown"
      end
    end

    def dependency_summary
      deps = Dependency.where(port_id: port.id).includes(:depends_on).to_a
      return "No recorded dependencies." if deps.empty?

      runtime = deps.select { |dep| dep.dep_type == "run" }.filter_map { |dep| dep.depends_on&.name }
      build = deps.select { |dep| dep.dep_type == "build" }.filter_map { |dep| dep.depends_on&.name }
      parts = []
      parts << "Runtime deps: #{runtime.first(6).join(', ')}" if runtime.any?
      parts << "Build deps: #{build.first(4).join(', ')}" if build.any?
      parts.join(". ").presence || "No recorded dependencies."
    end

    def advisory_summary
      advisories = SecurityAdvisory.where(port_id: port.id).order(created_at: :desc).limit(3).to_a
      return "No recent security advisories in local DB." if advisories.empty?

      "Security notes: #{advisories.map { |adv| "#{adv.identifier} (#{adv.severity})" }.join(', ')}."
    end

    def exploration_hint
      reverse_ids = Dependency.where(depends_on_id: port.id).limit(3).pluck(:port_id)
      return if reverse_ids.empty?

      names = Port.where(id: reverse_ids).pluck(:name)
      return if names.empty?

      "Other ports depending on this: #{names.join(', ')}."
    end
  end
end
