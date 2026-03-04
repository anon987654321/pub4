# frozen_string_literal: true

module AxiomResolver
  AXIOM_NAMESPACE = "Axiom"

  class Resolver
    def initialize(container: Object)
      @container = container
    end

    def resolve(name)
      normalized = normalize_name(name)
      return nil if normalized.empty?

      begin
        constantize(normalized)
      rescue NameError
        nil
      end
    end

    private

    def normalize_name(name)
      name.to_s.strip
    end

    def constantize(path)
      path.split("::").reduce(@container) do |context, const_name|
        context.const_get(const_name)
      end
    end
  end
end