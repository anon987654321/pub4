# frozen_string_literal: true

module DependencyMap
  DEFAULT_SCOPES = %i[runtime development test].freeze

  class << self
    def build(dependencies, scopes: DEFAULT_SCOPES)
      scopes = Array(scopes).map(&:to_sym)

      map = Hash.new { |h, k| h[k] = [] }

      Array(dependencies).each do |dep|
        next unless dep

        name = dep_name(dep)
        next if name.nil? || name.empty?

        next unless include_dep?(dep, scopes)

        Array(dep_children(dep)).each do |child|
          child_name = dep_name(child)
          next if child_name.nil? || child_name.empty?

          map[name] << child_name
        end
      end

      map
    end

    private

    def include_dep?(dep, scopes)
      dep_scope = dep_scope(dep)
      dep_scope.nil? || scopes.include?(dep_scope)
    end

    def dep_name(dep)
      if dep.respond_to?(:name)
        dep.name.to_s
      elsif dep.is_a?(Hash)
        (dep[:name] || dep["name"]).to_s
      else
        dep.to_s
      end
    end

    def dep_scope(dep)
      if dep.respond_to?(:type)
        dep.type&.to_sym
      elsif dep.respond_to?(:scope)
        dep.scope&.to_sym
      elsif dep.is_a?(Hash)
        (dep[:scope] || dep["scope"] || dep[:type] || dep["type"])&.to_sym
      end
    end

    def dep_children(dep)
      if dep.respond_to?(:dependencies)
        dep.dependencies
      elsif dep.respond_to?(:children)
        dep.children
      elsif dep.is_a?(Hash)
        dep[:dependencies] || dep["dependencies"] || dep[:children] || dep["children"]
      else
        nil
      end
    end
  end
end