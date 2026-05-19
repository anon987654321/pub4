# frozen_string_literal: true

module Master
  module Ground
  module Orders
    # Maps standing-order callable: keys to Order subclasses. Decouples the yaml
    # from class names — `callable: autocommit` is stable even if the class moves.
    module Registry
      def self.lookup(key)
        table[key.to_s]
      end

      def self.table
        @table ||= {
          "autocommit" => Autocommit,
          "restart_master" => RestartMaster,
          "architecture_audit" => ArchitectureAudit,
          "constitution_drift" => ConstitutionDrift
        }
      end

      def self.register(key, klass)
        table[key.to_s] = klass
      end
    end
  end
  end
end
