# frozen_string_literal: true

module Master
  # JE-style plugin registry. Each plugin is a module with optional
  # ClassMethods / InstanceMethods sub-modules and a configure hook.
  #
  #   Master.plugin :judge
  #   Master.plugin :reach, timeout: 30
  #
  # Plugin files live in lib/plugins/<name>.rb and define
  # Master::Plugins::<Name>. A plugin may expose configure(base, **opts) for
  # the mixin API and subsystem-specific boot/build methods for Builder.
  module Plugin
    @registry = {}
    @mutex    = Mutex.new

    def self.register(name, mod)
      @mutex.synchronize { @registry[name.to_sym] = mod }
    end

    def self.load(name)
      sym = name.to_sym
      @mutex.synchronize { return @registry[sym] } if @mutex.synchronize { @registry.key?(sym) }
      require_relative "plugins/#{name}"
      @mutex.synchronize { @registry[sym] }
    rescue LoadError => e
      raise ArgumentError, "plugin :#{name} not found (#{e.message})"
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def plugin(name, **opts)
        mod = Master::Plugin.load(name)
        extend(mod::ClassMethods)   if mod.const_defined?(:ClassMethods, false)
        include(mod::InstanceMethods) if mod.const_defined?(:InstanceMethods, false)
        mod.configure(self, **opts) if mod.respond_to?(:configure)
        mod
      end
    end
  end
end
