# frozen_string_literal: true

require "set"

module Master
  module Trace
    # Bounded TracePoint tracing for selected object identities. Call arguments
    # and return values are deliberately omitted because they often hold secrets.
    #
    #   probe = Master::Trace::ObjectProbe.new(receivers: [service], methods: %i[call execute])
    #   result = probe.capture { service.call }
    #   probe.events
    #   Master::Trace::ObjectProbe.method_chain(service, :call)
    class ObjectProbe
      MAX_EVENTS = 200
      MAX_EVENT_LIMIT = 10_000
      EVENT_TYPES = %i[call return c_call c_return raise].freeze

      Event = Struct.new(
        :event, :receiver_id, :receiver_class, :owner, :method_id,
        :path, :line, :exception_class,
        keyword_init: true
      )

      def initialize(receivers:, methods: nil, max_events: MAX_EVENTS, root: Master::REPO_ROOT)
        @receivers = Array(receivers)
        raise ArgumentError, "at least one receiver is required" if @receivers.empty?

        @receiver_ids = @receivers.to_h { |receiver| [receiver.object_id, true] }.freeze
        @methods = methods.nil? ? nil : Array(methods).map(&:to_sym).to_set.freeze
        @max_events = Integer(max_events)
        unless @max_events.between?(1, MAX_EVENT_LIMIT)
          raise ArgumentError, "max_events must be between 1 and #{MAX_EVENT_LIMIT}"
        end

        @root = File.expand_path(root)
        @events = [].freeze
        @truncated = false
        @active = false
        @instrumentation_error = nil
      end

      attr_reader :events, :instrumentation_error

      def truncated? = @truncated

      # Returns the block's original value and preserves raised exceptions.
      # Events remain readable after the block exits or raises.
      def capture
        started = false
        trace = nil
        raise ArgumentError, "capture requires a block" unless block_given?
        raise RuntimeError, "object probe is already capturing" if @active

        @active = true
        started = true
        @events = []
        @truncated = false
        @instrumentation_error = nil
        owner_thread = Thread.current
        trace = build_trace(owner_thread)
        trace.enable(target_thread: owner_thread) { yield }
      ensure
        if started
          trace&.disable
          @events.freeze if @events && !@events.frozen?
          @active = false
        end
      end

      # Returns the lookup sequence used by Ruby, including prepended modules
      # and each implementation reached by successive super calls.
      def self.method_chain(receiver, name)
        method = receiver.method(name)
        chain = []
        while method
          location = method.source_location&.then { |path, line| [path&.dup&.freeze, line].freeze }
          parameters = method.parameters.map { |kind, parameter| [kind, parameter].freeze }.freeze
          chain << {
            owner: label(method.owner),
            method_id: method.name,
            source_location: location,
            parameters:,
          }.freeze
          method = method.super_method
        end
        chain.freeze
      rescue NameError => e
        raise ArgumentError, "#{receiver.class} has no method #{name}", cause: e
      end

      def self.label(value)
        return "unknown" if value.nil?

        name = value.name if value.respond_to?(:name)
        (name.nil? || name.empty? ? value.to_s : name).dup.freeze
      end

      # Safe shallow state view: it records identities and container shapes,
      # never values, inspected objects, credentials, prompts or message bodies.
      def self.state_snapshot(receiver)
        receiver.instance_variables.sort_by(&:to_s).to_h do |name|
          value = receiver.instance_variable_get(name)
          shape = {
            class: label(value.class),
            object_id: value.object_id,
            frozen: value.frozen?,
          }
          if value.instance_of?(String)
            shape[:bytes] = value.bytesize
          elsif value.instance_of?(Array)
            shape[:length] = value.length
          elsif value.instance_of?(Hash) || value.instance_of?(Set)
            shape[:size] = value.size
          end
          [name, shape.freeze]
        end.freeze
      end

      def self.state_diff(before, after)
        names = (before.keys | after.keys).sort_by(&:to_s)
        names.each_with_object({}) do |name, changed|
          previous = before[name]
          current = after[name]
          changed[name] = { before: previous, after: current }.freeze unless previous == current
        end.freeze
      end

      private

      def build_trace(owner_thread)
        ::TracePoint.new(*EVENT_TYPES) do |point|
          begin
            record(point, owner_thread)
          rescue StandardError => error
            @instrumentation_error ||= error.class.name.to_s.freeze
          end
        end
      end

      def record(point, owner_thread)
        return unless Thread.current.equal?(owner_thread)
        return if point.path == __FILE__
        return unless @receiver_ids.key?(point.self.object_id)
        return if @methods && !@methods.include?(point.method_id)
        if @events.size >= @max_events
          @truncated = true
          return
        end

        @events << Event.new(
          event: point.event,
          receiver_id: point.self.object_id,
          receiver_class: self.class.label(point.self.class),
          owner: self.class.label(point.defined_class),
          method_id: point.method_id,
          path: display_path(point.path),
          line: point.lineno,
          exception_class: exception_name(point),
        ).freeze
      end

      def display_path(path)
        value = path.to_s
        prefix = "#{@root}#{File::SEPARATOR}"
        return value.delete_prefix(prefix).freeze if value.start_with?(prefix)

        "[external]/#{File.basename(value)}".freeze
      end

      def exception_name(point)
        return unless point.event == :raise

        point.raised_exception.class.name.to_s.freeze
      end
    end
  end
end
