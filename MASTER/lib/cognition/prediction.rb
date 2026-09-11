# frozen_string_literal: true

module Master
  module Cognition
    # What MASTER expects next, learned from what came before.
    #
    # What this replaced was recurrence rather than prediction: seconds since
    # that event last fired, read off an instance variable that started empty on
    # every boot. So every event was maximally surprising once per process
    # forever, nothing MASTER had ever seen informed what it expected, and the
    # number the self-model reports as `prediction_error` was a clock.
    #
    # A first-order transition table is the smallest thing that is actually a
    # prediction: P(this event | the one before it), learned from the bus and
    # kept in the state file, so a restart resumes an expectation instead of
    # resetting it. It is a Markov chain over event names and claims nothing
    # more — the bus interleaves concurrent turns, so a transition here is an
    # adjacency and not a cause.
    class Prediction
      MAX_ANTECEDENTS = 64
      MAX_SUCCESSORS = 16

      def observe!(predictions, event:)
        previous = predictions["previous_event"]
        error = (1.0 - confidence(predictions, previous, event)).clamp(0.0, 1.0)
        learn!(predictions, previous, event) if previous
        predictions["previous_event"] = event
        predictions["last_error"] = error.round(4)
        error
      end

      # What MASTER expects after this event, and how strongly. nil until the
      # pair has been seen once.
      def expected(predictions, event:)
        row = predictions.dig("transitions", event.to_s)
        row&.max_by { |_name, count| count.to_i }&.first
      end

      private

      # Laplace, so one sighting is not certainty: count / (total + 1) puts a
      # pair seen once at 0.5 and only repetition drives the error down. Without
      # the +1 the second occurrence of any pair scores a confident 1.0 and the
      # model would be surer of a coincidence than of anything it had watched.
      def confidence(predictions, previous, event)
        return 0.0 unless previous

        row = predictions.dig("transitions", previous)
        return 0.0 unless row

        row.fetch(event, 0).to_i / (row.values.sum(&:to_i) + 1).to_f
      end

      def learn!(predictions, previous, event)
        transitions = predictions["transitions"] ||= {}
        row = transitions[previous] ||= {}
        row[event] = row.fetch(event, 0).to_i + 1
        prune!(row, MAX_SUCCESSORS) { |name| row.fetch(name).to_i }
        prune!(transitions, MAX_ANTECEDENTS) { |name| transitions.fetch(name).values.sum(&:to_i) }
      end

      # Bounded in both directions, because this table is written to disk and an
      # unbounded one grows with the event vocabulary rather than with what is
      # worth remembering. The rarest rows go first: a transition seen once is
      # the one the model has learned least from.
      def prune!(table, limit)
        return if table.size <= limit

        table.keys.sort_by { |name| -yield(name) }.drop(limit).each { |name| table.delete(name) }
      end
    end
  end
end
