# frozen_string_literal: true

module Master
  module Builder
    # O102: each boot phase is a dedicated Bootable class.
    module Bootable
      def self.run_all(root:, config: nil)
        config ||= Ground::Config.new(root)
        trace = BootTrace.new(root:, config:).call
        loop_c = BootLoop.new(root:, config:, bus: trace[:bus]).call
        reach = BootReach.new(root:, config:, bus: trace[:bus]).call
        ground = BootGround.new(root:, config:, homeostat: loop_c[:homeostat]).call
        trace.merge(loop_c).merge(reach).merge(ground)
      end

      class BootTrace
        def initialize(root:, config:)
          @root = root
          @config = config
        end

        def call
          Builder.boot_trace(root: @root, config: @config)
        end
      end

      class BootLoop
        def initialize(root:, config:, bus:)
          @root = root
          @config = config
          @bus = bus
        end

        def call
          Builder.boot_loop(root: @root, config: @config, bus: @bus)
        end
      end

      class BootReach
        def initialize(root:, config:, bus:)
          @root = root
          @config = config
          @bus = bus
        end

        def call
          Builder.boot_reach(root: @root, config: @config, bus: @bus)
        end
      end

      class BootGround
        def initialize(root:, config:, homeostat:)
          @root = root
          @config = config
          @homeostat = homeostat
        end

        def call
          Builder.boot_ground(root: @root, config: @config, homeostat: @homeostat)
        end
      end
    end
  end
end