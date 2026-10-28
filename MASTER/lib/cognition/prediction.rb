# frozen_string_literal: true

require "digest"
require_relative "state"

module Master
  module Cognition
    # Predict event transitions in bounded streams. An unscoped stream retains
    # compatibility with older state files; task/run contexts keep concurrent
    # work from training one another's transition table. Adjacency is temporal
    # evidence, not a claim of causation.
    class Prediction
      MAX_ANTECEDENTS = State::MAX_PREDICTION_ANTECEDENTS
      MAX_SUCCESSORS = State::MAX_PREDICTION_SUCCESSORS
      MAX_STREAMS = State::MAX_PREDICTION_STREAMS

      # Deterministic prequential benchmark. Predictions are scored before each
      # test event is revealed; after scoring, that observation joins the stream.
      # This measures next-event utility only, not causation or consciousness.
      def self.evaluate(training:, testing:, scoped: true)
        predictor = new
        predictions = { "transitions" => {}, "previous_event" => nil }
        previous = {}

        Array(training).each do |item|
          row = evaluation_row(item)
          context = scoped ? row[:context] : nil
          predictor.observe!(predictions, event: row[:event], context:)
          previous[context] = row[:event]
        end

        attempts = 0
        correct = 0
        Array(testing).each do |item|
          row = evaluation_row(item)
          context = scoped ? row[:context] : nil
          prior = previous[context]
          if prior
            attempts += 1
            expected = predictor.expected(predictions, event: prior, context:)
            correct += 1 if expected == row[:event]
          end
          predictor.observe!(predictions, event: row[:event], context:)
          previous[context] = row[:event]
        end

        {
          state: attempts.positive? ? :measured : :inconclusive,
          protocol: :walk_forward,
          scope: scoped ? :contextual : :shared,
          attempts:,
          correct:,
          top1_accuracy: attempts.positive? ? (correct.to_f / attempts).round(4) : nil,
        }.freeze
      end

      def self.evaluation_row(item)
        raise ArgumentError, "evaluation item must be a hash" unless item.is_a?(Hash)

        event = item[:event] || item["event"]
        raise ArgumentError, "evaluation event must be non-empty" if event.to_s.strip.empty?

        context = item[:context] || item["context"]
        { event: event.to_s, context: context&.to_s }
      end
      private_class_method :evaluation_row

      def observe!(predictions, event:, context: nil)
        stream = stream_for(predictions, context:, create: true)
        previous = stream["previous_event"]
        error = (1.0 - confidence(stream, previous, event)).clamp(0.0, 1.0)
        learn!(stream, previous, event) if previous
        stream["previous_event"] = event.to_s
        stream["last_error"] = error.round(4)
        stream["observations"] = stream.fetch("observations", 0).to_i + 1
        stream["last_observed_at"] = Time.now.to_i if contextual?(context)
        predictions["last_error"] = error.round(4)
        error
      end

      # What MASTER expects after this event, and how strongly. nil until the
      # pair has been seen in the requested stream.
      def expected(predictions, event:, context: nil)
        stream = stream_for(predictions, context:, create: false)
        row = stream&.dig("transitions", event.to_s)
        row&.max_by { |_name, count| count.to_i }&.first
      end

      private

      def contextual?(context) = !context.nil? && !context.to_s.strip.empty?

      def stream_for(predictions, context:, create:)
        return predictions unless contextual?(context)

        # Do not persist raw task/request identifiers in cognition state.
        key = "ctx:#{Digest::SHA256.hexdigest(context.to_s.strip)[0, 24]}"
        streams = predictions["streams"]
        unless streams.is_a?(Hash)
          return unless create

          streams = predictions["streams"] = {}
        end
        stream = streams[key]
        if stream && !stream.is_a?(Hash)
          return unless create

          stream = nil
        end
        if stream.nil? && create
          stream = streams[key] = {
            "transitions" => {},
            "previous_event" => nil,
            "last_error" => 0.0,
            "observations" => 0,
            "last_observed_at" => Time.now.to_i,
          }
          prune_streams!(streams, keep: key)
        end
        stream
      end

      # Laplace smoothing: a single observation is not certainty.
      def confidence(stream, previous, event)
        return 0.0 unless previous

        row = stream.dig("transitions", previous)
        return 0.0 unless row

        row.fetch(event.to_s, 0).to_i / (row.values.sum(&:to_i) + 1).to_f
      end

      def learn!(stream, previous, event)
        transitions = stream["transitions"] ||= {}
        row = transitions[previous] ||= {}
        row[event.to_s] = row.fetch(event.to_s, 0).to_i + 1
        prune!(row, MAX_SUCCESSORS) { |name| row.fetch(name).to_i }
        prune!(transitions, MAX_ANTECEDENTS) { |name| transitions.fetch(name).values.sum(&:to_i) }
      end

      def prune_streams!(streams, keep:)
        excess = streams.size - MAX_STREAMS
        return unless excess.positive?

        oldest = streams.keys.reject { |key| key == keep }
                         .sort_by { |key| streams.dig(key, "last_observed_at").to_i }
        oldest.first(excess).each { |key| streams.delete(key) }
      end

      # Both transition dimensions and stream count are bounded. Rare evidence
      # goes first; no unbounded task history can grow the cognition file forever.
      def prune!(table, limit)
        return if table.size <= limit

        table.keys.sort_by { |name| -yield(name) }.drop(limit).each { |name| table.delete(name) }
      end
    end
  end
end
