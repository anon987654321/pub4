# frozen_string_literal: true

module Master
  module Runtime
    module Box
      class Unavailable < StandardError; end

      module_function

      def present?
        defined?(::Ruby::Box) &&
          ::Ruby::Box.respond_to?(:new) &&
          ::Ruby::Box.respond_to?(:enabled?)
      end

      def enabled?
        present? && ::Ruby::Box.enabled?
      rescue StandardError
        false
      end

      def available?
        present? && enabled?
      end

      def startup_required?
        true
      end

      def new_box
        raise Unavailable, unavailable_message unless available?

        ::Ruby::Box.new
      end

      def evaluate(source, box: nil)
        box ||= new_box
        box.eval(String(source))
      end

      def load(path, box: nil)
        box ||= new_box
        box.load(File.expand_path(path.to_s))
      end

      def snapshot
        {
          present: present?,
          enabled: enabled?,
          available: available?,
          startup_required: startup_required?,
          startup_env: ENV["RUBY_BOX"].to_s == "1",
          current: current_inspect,
        }.freeze
      end

      def unavailable_message
        return "Ruby::Box is unavailable on this Ruby build" unless present?
        return "Ruby::Box is disabled; start the Ruby process with RUBY_BOX=1" unless enabled?

        "Ruby::Box is unavailable"
      end

      def current_inspect
        return unless enabled?

        ::Ruby::Box.current&.inspect
      rescue StandardError
        nil
      end
    end
  end
end
