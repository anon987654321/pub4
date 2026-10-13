# frozen_string_literal: true

module Contracts
  module Rails
    ROOT = File.expand_path("../../RAILS", __dir__).freeze

    module_function

    def root
      ROOT
    end

    # The master-side adapter is read-only. Writes still need a tree manifest
    # granting write access; an adapter cannot silently promote its caller.
    def read(relative_path)
      path = File.expand_path(relative_path.to_s, ROOT)
      raise ArgumentError, "path escapes RAILS boundary" unless path.start_with?(ROOT + File::SEPARATOR)
      raise ArgumentError, "path is not a regular file" unless File.file?(path) && !File.symlink?(path)

      real = File.realpath(path)
      raise ArgumentError, "resolved path escapes RAILS boundary" unless real.start_with?(File.realpath(ROOT) + File::SEPARATOR)

      File.binread(real)
    end
  end
end
