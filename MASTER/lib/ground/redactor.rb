# frozen_string_literal: true

module Master
  module Ground
    class Redactor
      ASCII_WHITESPACE = [9, 10, 11, 12, 13, 32].freeze
      SECRET_ALPHANUMERIC = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
      SECRET_ALPHANUMERIC_DASH = "#{SECRET_ALPHANUMERIC}_-"
      SECRET_BEARER = "#{SECRET_ALPHANUMERIC}_-."

      SENSITIVE_KEYS = /
        \A(?:password|passwd|secret|token|api[_-]?key|authorization|cookie|private[_-]?key)\z
      /ix

      DMESG_MAX = 240
      MAX_DEPTH = 16

      def self.text(value)
        return "[REDACTED]" if Thread.current.thread_variable_get(:master_redactor_active)

        Thread.current.thread_variable_set(:master_redactor_active, true)
        begin
          redact_secrets(plain_string(value))
        ensure
          Thread.current.thread_variable_set(:master_redactor_active, false)
        end
      end

      def self.redact_secrets(value)
        out = value
        offset = 0

        while (match = next_secret_match(out, offset))
          start, finish = match
          left = String.instance_method(:byteslice).bind(out).call(0, start)
          right = String.instance_method(:byteslice).bind(out).call(finish, String.instance_method(:bytesize).bind(out).call - finish)
          out = String.instance_method(:+).bind(left).call("[REDACTED]")
          out = String.instance_method(:+).bind(out).call(right)
          offset = start + 10
        end

        out
      end

      def self.next_secret_match(value, offset)
        matches = [
          find_prefixed_secret(value, offset, "sk-ant-"),
          find_prefixed_secret(value, offset, "sk-"),
          find_bearer_secret(value, offset),
          find_plain_secret(value, offset),
        ].compact
        matches.min_by(&:first)
      end

      def self.find_prefixed_secret(value, offset, prefix)
        cursor = offset
        while (start = literal_index(value, prefix, cursor))
          finish = start + String.instance_method(:bytesize).bind(prefix).call
          return [start, secret_run_end(value, finish, SECRET_ALPHANUMERIC_DASH)] if secret_run_length(value, finish, SECRET_ALPHANUMERIC_DASH) >= 16
          cursor = start + String.instance_method(:bytesize).bind(prefix).call
        end
        nil
      end

      def self.find_bearer_secret(value, offset)
        cursor = offset
        while (start = literal_index(value, "bearer", cursor, ignore_case: true))
          separator = start + 6
          separator += 1 while separator < String.instance_method(:bytesize).bind(value).call && ASCII_WHITESPACE.include?(String.instance_method(:getbyte).bind(value).call(separator))
          length = secret_run_length(value, separator, SECRET_BEARER)
          return [start, secret_run_end(value, separator, SECRET_BEARER)] if separator > start + 6 && length >= 16
          cursor = start + 6
        end
        nil
      end

      # Do not route secret matching through String#index/downcase. Those methods
      # may be instrumented or prepended by a dependency, and redaction is itself
      # used by the dependency/bootstrap trace path. A call back into #text here
      # turns one secret into an unbounded redaction recursion.
      def self.literal_index(value, needle, offset, ignore_case: false)
        needle_length = String.instance_method(:bytesize).bind(needle).call
        limit = String.instance_method(:bytesize).bind(value).call - needle_length
        cursor = offset

        while cursor <= limit
          matched = true
          needle_length.times do |index|
            left = String.instance_method(:getbyte).bind(value).call(cursor + index)
            right = String.instance_method(:getbyte).bind(needle).call(index)
            if ignore_case
              left -= 32 if left && left >= 97 && left <= 122
              right -= 32 if right && right >= 97 && right <= 122
            end
            if left != right
              matched = false
              break
            end
          end
          return cursor if matched
          cursor += 1
        end
        nil
      end

      def self.find_plain_secret(value, offset)
        cursor = offset
        size = String.instance_method(:bytesize).bind(value).call
        while cursor < size
          byte = String.instance_method(:getbyte).bind(value).call(cursor)
          unless alphanumeric_byte?(byte)
            cursor += 1
            next
          end

          start = cursor
          cursor += 1 while cursor < size && alphanumeric_byte?(String.instance_method(:getbyte).bind(value).call(cursor))
          finish = cursor
          return [start, finish] if finish - start >= 32 && word_boundary?(value, start, finish)
        end
        nil
      end

      def self.secret_run_length(value, offset, alphabet)
        cursor = offset
        size = String.instance_method(:bytesize).bind(value).call
        while cursor < size && alphabet_byte?(String.instance_method(:getbyte).bind(value).call(cursor), alphabet)
          cursor += 1
        end
        cursor - offset
      end

      def self.secret_run_end(value, offset, alphabet)
        offset + secret_run_length(value, offset, alphabet)
      end

      def self.alphabet_byte?(byte, alphabet)
        return false unless byte

        case alphabet
        when SECRET_ALPHANUMERIC
          alphanumeric_byte?(byte)
        when SECRET_ALPHANUMERIC_DASH
          alphanumeric_byte?(byte) || byte == 95 || byte == 45
        when SECRET_BEARER
          alphanumeric_byte?(byte) || byte == 95 || byte == 45 || byte == 46
        else
          false
        end
      end

      def self.alphanumeric_byte?(byte)
        byte && ((byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122))
      end

      def self.word_boundary?(value, start, finish)
        !word_byte?(String.instance_method(:getbyte).bind(value).call(start - 1)) &&
          !word_byte?(String.instance_method(:getbyte).bind(value).call(finish))
      end

      def self.word_byte?(byte)
        alphanumeric_byte?(byte) || byte == 95
      end

      def self.plain_string(value)
        string = String === value ? value : value.to_s
        copy = String.allocate
        String.instance_method(:initialize_copy).bind(copy).call(string)
        copy
      end

      def self.payload(hash = nil, seen: {}, depth: 0, **fields)
        hash = hash ? hash.merge(fields) : fields unless fields.empty?
        raise ArgumentError, "payload requires a Hash" unless hash.is_a?(Hash)

        scrub_container(hash || {}, seen:, depth:)
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

      def self.scrub_array(_key, array, seen:, depth: 0)
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
        return text if String.instance_method(:length).bind(text).call <= DMESG_MAX

        "#{String.instance_method(:[]).bind(text).call(0, DMESG_MAX)}…"
      end

      def self.public_error_message
        "An internal error occurred. Retry or check server logs."
      end
    end
  end
end
