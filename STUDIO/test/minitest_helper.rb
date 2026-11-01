# frozen_string_literal: true

# Minitest 5 with its mock, for the tests here that stub. Minitest 6 is the
# default gem on this Ruby and no longer ships minitest/mock, so `.stub` raised
# NoMethodError in every such test. Plugins are off because an installed
# railties registers one that cannot load outside a Rails app.
# tool_test_helper.rb pins the same way for the tool suites.
ENV["MT_NO_PLUGINS"] = "1"

begin
  gem "minitest", "~> 5.25"
  require "minitest/autorun"
  require "minitest/mock"
rescue Gem::LoadError, LoadError
  # Rubies where minitest 5 cannot be installed (Ruby >= 4.0 ships minitest 6
  # only) fall back to minitest 6 autorun plus the Object#stub shim below, so
  # the same `.stub` calls keep working there. The shim forwards the stubbed
  # call's arguments to a callable, like minitest 5's own mock does.
  require "minitest/autorun"

  module MinitestStub
    def stub(name, value_or_callable)
      name = name.to_sym
      holder = self
      had_singleton = holder.singleton_class.method_defined?(name)
      alias_name = :"__studio_stub_orig_#{name}"
      holder.singleton_class.send(:alias_method, alias_name, name) if had_singleton
      holder.define_singleton_method(name) do |*args, **kwargs, &block|
        if value_or_callable.respond_to?(:call)
          value_or_callable.call(*args, **kwargs, &block)
        else
          value_or_callable
        end
      end
      yield
    ensure
      if had_singleton
        holder.singleton_class.send(:alias_method, name, alias_name)
        holder.singleton_class.send(:remove_method, alias_name)
      else
        begin
          holder.singleton_class.send(:remove_method, name)
        rescue NameError
          nil
        end
      end
    end
  end

  Object.include(MinitestStub)
end
