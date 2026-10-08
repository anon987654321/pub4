# frozen_string_literal: true

module Ports
  class ExploreAssistant
    SCOPE = "ports.explore_assistant"

    def self.summarize(port)
      new(port).summarize
    end

    def initialize(port)
      @port = port
    end

    def summarize
      lines = []
      lines << t(:identity, name: port.name, version: port.version, category: category_name,
                            comment: port.comment.presence || t(:no_comment))
      lines << t(:maintainer, name: maintainer_label)
      lines << t(:pkgpath, pkgpath: port.pkgpath)
      lines << dependency_summary
      lines << advisory_summary
      lines << exploration_hint
      lines.compact.join(" ")
    end

    private

    attr_reader :port

    def t(key, **options) = I18n.t(key, scope: SCOPE, **options)

    def category_name
      # Prefer preloaded association; fall back without raising under strict_loading.
      name = if port.association(:category).loaded?
        port.category&.name
      else
        Category.where(id: port.category_id).pick(:name)
      end
      name || t(:uncategorized)
    end

    # The name, not the record: interpolating a Maintainer printed its inspect string.
    def maintainer_label
      name = if port.association(:maintainer).loaded?
        port.maintainer&.name
      elsif port.maintainer_id.present?
        Maintainer.where(id: port.maintainer_id).pick(:name)
      end
      name.presence || t(:unknown)
    end

    def dependency_summary
      deps = Dependency.where(port_id: port.id).includes(:depends_on).to_a
      return t(:no_dependencies) if deps.empty?

      runtime = deps.select { |dep| dep.dep_type == "run" }.filter_map { |dep| dep.depends_on&.name }
      build = deps.select { |dep| dep.dep_type == "build" }.filter_map { |dep| dep.depends_on&.name }
      parts = []
      parts << t(:runtime_deps, names: runtime.first(6).join(", ")) if runtime.any?
      parts << t(:build_deps, names: build.first(4).join(", ")) if build.any?
      parts.join(". ").presence || t(:no_dependencies)
    end

    def advisory_summary
      advisories = SecurityAdvisory.where(port_id: port.id).order(created_at: :desc).limit(3).to_a
      return t(:no_advisories) if advisories.empty?

      t(:advisories, list: advisories.map { |adv| "#{adv.identifier} (#{adv.severity})" }.join(", "))
    end

    def exploration_hint
      reverse_ids = Dependency.where(depends_on_id: port.id).limit(3).pluck(:port_id)
      return if reverse_ids.empty?

      names = Port.where(id: reverse_ids).pluck(:name)
      return if names.empty?

      t(:reverse_deps, names: names.join(", "))
    end
  end
end
