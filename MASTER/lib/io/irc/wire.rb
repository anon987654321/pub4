# frozen_string_literal: true

require "base64"
require_relative "../chat"

module Master
  module Io
    class Irc < Chat::Transport
      # Pure IRC wire format: parsing, building and splitting lines.
      module Wire
        Message = Struct.new(:prefix, :nick, :command, :params, keyword_init: true) do
          def trailing = params.last.to_s
        end

        MAX_LINE = 510
        RELAY_RESERVE = 100 # the server prepends :nick!user@host to what it relays
        MAX_BUFFER = 8192

        module_function

        # ":nick!user@host CMD a b :trailing". IRCv3 tags (@k=v ) are skipped.
        def parse(raw)
          line = raw.to_s.dup.force_encoding(Encoding::UTF_8).scrub("?").chomp.delete("\r\n\0")
          line = line.sub(/\A@\S+ /, "")
          return nil if line.strip.empty?

          prefix = line.slice!(/\A:\S+ /)&.strip&.delete_prefix(":")
          head, trailing = line.split(" :", 2)
          words = head.to_s.split
          command = words.shift.to_s.upcase
          return nil if command.empty?

          Message.new(prefix:, nick: prefix&.split("!")&.first, command:, params: trailing ? words + [trailing] : words)
        end

        # One outgoing line; CR, LF and NUL in any argument would smuggle a
        # second command, so they are refused rather than stripped.
        def line(command, *params)
          raise ArgumentError, "control character in IRC argument" if params.any? { |p| p.to_s.match?(/[\r\n\0]/) }

          *middle, last = params.map(&:to_s)
          text = [command, *middle].join(" ")
          text += (last.empty? || last.include?(" ") || last.start_with?(":") ? " :#{last}" : " #{last}") if last
          raise ArgumentError, "IRC line over #{MAX_LINE} bytes" if text.bytesize > MAX_LINE

          text
        end

        # PRIVMSG bodies that fit 512 bytes with CRLF and the relay prefix,
        # cut at spaces where possible and never inside a character.
        def split_message(target, text, action: false)
          overhead = "PRIVMSG #{target} :".bytesize + (action ? 9 : 0)
          room = MAX_LINE - RELAY_RESERVE - overhead
          raise ArgumentError, "target too long" if room < 20

          chunks = []
          rest = text.to_s.strip
          until rest.empty?
            cut = fit(rest, room)
            chunks << rest[0, cut].strip
            rest = rest[cut..].to_s.lstrip
          end
          chunks
        end

        def fit(text, bytes)
          return text.length if text.bytesize <= bytes

          size = 0
          cut = text.each_char.take_while { |c| (size += c.bytesize) <= bytes }.size
          space = text[0, cut].rindex(" ")
          space && space > cut / 2 ? space : cut
        end

        # AUTHENTICATE payload(s): base64 in 400-byte pieces, "+" when exact.
        def sasl_plain(nick, password)
          encoded = Base64.strict_encode64("\0#{nick}\0#{password}")
          pieces = encoded.scan(/.{1,400}/)
          pieces << "+" if (encoded.length % 400).zero?
          pieces.map { |p| "AUTHENTICATE #{p}" }
        end

        # Complete lines out of a growing buffer; an unterminated run past
        # MAX_BUFFER is dropped, not kept, so a hostile peer cannot grow it.
        def drain(buffer)
          lines = []
          while (idx = buffer.index("\n"))
            lines << buffer.slice!(0, idx + 1)
          end
          buffer.clear if buffer.bytesize > MAX_BUFFER
          lines
        end
      end
    end
  end
end
