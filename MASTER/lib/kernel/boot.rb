# frozen_string_literal: true

require 'yaml'
require_relative '../events/bus'
require_relative '../actors/registry'

module MASTER
  module Kernel
    # Microkernel Boot - 100-line supervisor (Microkernel #2)
    # Orchestrates system initialization with minimal core
    class << self
      attr_reader :event_bus, :actor_registry, :config

      def boot(verbose: false)
        @boot_time = Time.now
        @verbose = verbose
        
        log "🚀 MASTER Microkernel v#{MASTER::VERSION} booting..."
        
        # Phase 1: Load configuration
        load_config
        
        # Phase 2: Start event bus
        start_event_bus
        
        # Phase 3: Register actors
        register_actors
        
        # Phase 4: Load modules (if feature enabled)
        load_modules if feature_enabled?(:dynamic_loading)
        
        # Phase 5: System ready
        emit(:system_ready, boot_time: @boot_time, version: MASTER::VERSION)
        
        boot_duration = ((Time.now - @boot_time) * 1000).round
        log "✅ Microkernel boot complete in #{boot_duration}ms"
        
        {
          event_bus: @event_bus,
          actor_registry: @actor_registry,
          config: @config,
          boot_time: @boot_time,
          boot_duration_ms: boot_duration
        }
      end

      def emit(event_type, data = {})
        @event_bus&.publish(event_type, data)
      end

      def feature_enabled?(feature)
        @config&.dig('features', feature.to_s) == true
      end

      private

      def log(message)
        puts message if @verbose
      end

      def load_config
        config_path = File.join(MASTER::ROOT, 'config', 'system.yml')
        if File.exist?(config_path)
          @config = YAML.safe_load(File.read(config_path))
          log "📄 Configuration loaded from #{config_path}"
        else
          @config = {}
          log "⚠️  No configuration file found, using defaults"
        end
      end

      def start_event_bus
        @event_bus = MASTER::Events::Bus.new
        
        # Log all events if verbose
        if @verbose
          @event_bus.subscribe(:all) do |event|
            log "📡 Event: #{event.type} (#{event.id})"
          end
        end
        
        log "📡 Event bus started"
      end

      def register_actors
        @actor_registry = MASTER::Actors::Registry.new(@event_bus)
        
        # Actors will be registered here in later phases
        # For now, just set up the registry
        
        log "🎭 Actor registry initialized"
      end

      def load_modules
        # Phase 11 will implement dynamic module loading from config
        # For now, this is a placeholder
        log "📦 Module loading (placeholder - will be implemented in Phase 11)"
      end
    end
  end
end
