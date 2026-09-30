# frozen_string_literal: true

module Master
  module Ground
    class Redactor
      KEY_PATTERNS = [
        /sk-[A-Za-z0-9_\-]{16,}/,
        /sk-ant-[A-Za-z0-9_\-]{16,}/,
        /Bearer\s+[A-Za-z0-9_\-\.]{16,}/i,
        /\b[A-Za-z0-9]{32,}\b/,
      ].freeze

      SENSITIVE_KEYS = /
        \A(?:password|passwd|secret|token|api[_-]?key|authorization|cookie|private[_-]?key)\z
      /ix

      DMESG_MAX = 240
      MAX_DEPTH = 16

      def self.text(value)
        out = value.to_s
        KEY_PATTERNS.each { |pattern| out = out.gsub(pattern, "[REDACTED]") }
        out
      end

      def self.payload(hash, seen: {}, depth: 0)
        scrub_container(hash, seen:, depth:)
      end

      def self.scrub_value(key, value, seen: {}, depth: 0)
        return "[REDACTED]" if key.to_s.match?(SENSITIVE_KEYS)
        return "[DEPTH]" if depth >= MAX_DEPTH && (value.is_a?(Hash) || value.is_a?(Array))

        case value
        when Hash, Array
          scrub_container(value, seen:, depth:)
        when String
          truncate(text(value))
        else
          value
        end
      end

      def self.scrub_array(key, array, seen:, depth: 0)
        scrub_container(array, seen:, depth:)
      end

      def self.scrub_container(value, seen:, depth:)
        return "[DEPTH]" if depth >= MAX_DEPTH
        seen.compare_by_identity
        return "[CYCLE]" if seen.key?(value)

        root = value.is_a?(Hash) ? {} : []
        seen[value] = true
        stack = [[:enter, value, root, depth]]

        until stack.empty?
          phase, source, target, current_depth = stack.pop

          if phase == :leave
            seen.delete(source)
            next
          end

          stack << [:leave, source, target, current_depth]

          if source.is_a?(Hash)
            source.to_a.reverse_each do |child_key, child_value|
              if child_key.to_s.match?(SENSITIVE_KEYS)
                target[child_key] = "[REDACTED]"
                next
              end

              assign_container_value(target, child_key, child_value, current_depth + 1, seen, stack)
            end
          else
            source.length.times.to_a.reverse_each do |index|
              assign_container_value(target, index, source[index], current_depth + 1, seen, stack)
            end
          end
        end

        root
      end

      def self.assign_container_value(target, key, value, depth, seen, stack)
        if value.is_a?(Hash) || value.is_a?(Array)
          if depth >= MAX_DEPTH
            target[key] = "[DEPTH]"
          elsif seen.key?(value)
            target[key] = "[CYCLE]"
          else
            nested = value.is_a?(Hash) ? {} : []
            target[key] = nested
            seen[value] = true
            stack << [:enter, value, nested, depth]
          end
        elsif value.is_a?(String)
          target[key] = truncate(text(value))
        else
          target[key] = value
        end
      end

      def self.truncate(value)
        text = value.to_s
        return text if text.length <= DMESG_MAX

        "#{text[0, DMESG_MAX]}…"
      end

      def self.public_error_message
        "An internal error occurred. Retry or check server logs."
      end
    end
  end
end
