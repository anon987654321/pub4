# frozen_string_literal: true

module Master
  module Orders
    # Standing-order callables. Subclass and implement `call`. Returning a
    # Master::Result::Ok marks the order done; Result::Err marks it errored.
    class Base
      def initialize(container:)
        @container = container
      end

      def bus = @container[:bus]
      def root = @container[:root]

      def call
        raise NotImplementedError, "#{self.class}#call not implemented"
      end
    end
  end
end
