# frozen_string_literal: true

require "securerandom"

module Deploy
  # The RFC 6455 half of CdpSession: masking, frame headers, continuation and
  # control frames, and the blocking reads that assemble a message out of them.
  #
  # Split out when cdp_session.rb passed its file-length ceiling, and the seam
  # was already drawn — the section carried a `--- websocket framing ---`
  # banner. Everything above that line speaks CDP (navigate, evaluate, press,
  # screenshot); everything below speaks WebSocket and knows nothing about
  # Chrome. Two protocols in one file, and only one of them is the reason this
  # class exists.
  #
  # Included rather than extracted to an object, because the framing reads and
  # writes @socket, @timeout and @buffer directly and threading those through a
  # collaborator would buy nothing but indirection. The methods stay private to
  # CdpSession exactly as they were.
  # CdpSession::Error and ::Desync are qualified rather than bare: constant
  # lookup is lexical, so a module that is `include`d does not see the
  # including class's constants. A bare `Desync` here resolved at parse time
  # to nothing and raised NameError from inside the frame reader — which the
  # runner reported as a gate that errored and blocked nothing, exactly as it
  # is meant to. MAX_FRAME_BYTES came with the methods that read it.
  module CdpFraming
    # No legitimate CDP message is anywhere near this large. Without the cap, a
    # desynchronised read parses arbitrary payload bytes as a 64-bit length and
    # read_nonblock tries to allocate it — which surfaces as a NoMemoryError
    # that kills the whole runner instead of one surface.
    MAX_FRAME_BYTES = 64 * 1024 * 1024

    private

    def write_frame(payload)
      bytes = payload.b
      header = [0x81].pack("C")
      len = bytes.bytesize
      header += if len < 126
                  [0x80 | len].pack("C")
                elsif len < 65_536
                  [0x80 | 126, len].pack("Cn")
                else
                  [0x80 | 127, len].pack("CQ>")
                end
      mask = SecureRandom.bytes(4)
      masked = bytes.bytes.each_with_index.map { |b, i| b ^ mask.getbyte(i % 4) }.pack("C*")
      @socket.write(header + mask + masked)
    end

    def read_frame(timeout)
      deadline = monotonic + timeout
      buffer = +""
      loop do
        opcode, payload = read_single_frame(deadline)
        return nil unless opcode

        case opcode
        when 0x9 # ping -> pong
          write_control(0xA, payload)
          next
        when 0xA # pong
          next
        when 0x8
          raise CdpSession::Error, "websocket closed by browser"
        when 0x0
          buffer << payload
        else
          buffer = payload
        end
        return buffer if @frame_fin
      end
    end

    def read_single_frame(deadline)
      raise CdpSession::Desync, "socket abandoned mid-frame by an earlier timeout" if @desync

      @mid_frame = false
      first = read_exactly(2, deadline)
      return [nil, nil] unless first

      # Past this point every read is draining a frame the peer has committed
      # to sending, so read_exactly must not abandon it.
      @mid_frame = true
      b0 = first.getbyte(0)
      b1 = first.getbyte(1)
      @frame_fin = (b0 & 0x80) != 0
      opcode = b0 & 0x0F
      masked = (b1 & 0x80) != 0
      len = b1 & 0x7F
      len = read_exactly(2, deadline).unpack1("n") if len == 126
      len = read_exactly(8, deadline).unpack1("Q>") if len == 127
      if len > MAX_FRAME_BYTES
        @desync = true
        raise CdpSession::Desync, "implausible frame length #{len} — the read stream is out of sync"
      end
      mask = masked ? read_exactly(4, deadline) : nil
      payload = len.zero? ? +"" : read_exactly(len, deadline)
      if mask && payload
        payload = payload.bytes.each_with_index.map { |b, i| b ^ mask.getbyte(i % 4) }.pack("C*")
      end
      [opcode, payload.to_s]
    end

    # A timeout partway through a frame leaves the socket positioned inside a
    # message. Every later read then parses payload bytes as a header, which is
    # how a length of several exabytes gets requested. Mark the session dead the
    # moment that can have happened.
    # Waiting for a response to *begin* and waiting for a frame already in
    # flight to *finish* are different situations. Giving up on the first is
    # fine. Giving up on the second leaves the socket parked inside a message,
    # and every later read then parses payload bytes as a header — which is how
    # a length of several exabytes gets requested and the runner dies with
    # NoMemoryError instead of one surface failing.
    #
    # So: the caller's deadline governs the wait for the first byte; after that
    # a bounded grace window is granted to drain the frame, and only if the peer
    # goes silent mid-frame is the session marked unusable.
    FRAME_GRACE_SECONDS = 30

    def read_exactly(count, deadline)
      out = +""
      graced = false
      while out.bytesize < count
        remaining = deadline - monotonic
        if remaining <= 0 || !IO.select([@socket], nil, nil, [remaining, 0.0].max)
          started = !out.empty? || @mid_frame
          if started && !graced
            graced = true
            deadline = monotonic + FRAME_GRACE_SECONDS
            next
          end
          @desync = true if started
          raise Timeout, "websocket read timeout#{started ? " mid-frame" : ""}"
        end

        chunk = @socket.read_nonblock(count - out.bytesize, exception: false)
        if chunk.nil?
          @desync = true
          raise CdpSession::Desync, "browser closed the socket mid-message"
        end
        next if chunk == :wait_readable

        out << chunk
      end
      out
    end

    def write_control(opcode, payload)
      bytes = payload.to_s.b
      mask = SecureRandom.bytes(4)
      masked = bytes.bytes.each_with_index.map { |b, i| b ^ mask.getbyte(i % 4) }.pack("C*")
      @socket.write([0x80 | opcode, 0x80 | bytes.bytesize].pack("CC") + mask + masked)
    end
  end
end
