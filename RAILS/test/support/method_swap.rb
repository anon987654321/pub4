# frozen_string_literal: true

# Swap a singleton method for the duration of a block.
#
# The gate tests need to decide what the machine looks like — no Chrome, no
# listening port, this HTML from that surface — because the point of a
# third-state assertion is that it holds when the precondition is absent, and a
# test that can only run on a machine without Chrome runs nowhere.
#
# minitest/mock is not in the bundled Minitest these standalone tests run
# under, and RAILS/test/fediverse_ssrf_test.rb already does this by hand. This
# is that idiom, named once, with the restore in an ensure so a raising block
# cannot leave a stub behind for the rest of the file.
#
# Restores by removing rather than re-aliasing when the method was not defined
# on the singleton class itself. CdpSession.available? arrives through `extend
# ChromeProcess::Discovery`, so re-defining it would leave a permanent
# singleton copy shadowing the module the gates actually ask.
module MethodSwap
  def swap(receiver, name, replacement)
    meta = receiver.singleton_class
    own = meta.instance_methods(false).include?(name)
    original = meta.instance_method(name) if own
    meta.send(:define_method, name, replacement)
    yield
  ensure
    own ? meta.send(:define_method, name, original) : meta.send(:remove_method, name)
  end

  # The common case: one fixed answer, whatever the arguments.
  def swap_value(receiver, name, value, &block)
    swap(receiver, name, ->(*_args, **_kwargs) { value }, &block)
  end
end
