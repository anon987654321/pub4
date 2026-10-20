# frozen_string_literal: true

require "rb_edge_tts"

module Master
  module Voice
    # Microsoft's Edge voice service now refuses the v1 Sec-MS-GEC token that rb_edge_tts 1.0.1 sends (the
    # handshake answers 403, and every utterance falls to the OS voice). The service wants the v2 token,
    # "<16 hex CS64>-<64 hex SHA-256>", with a "2-" version prefix, as in rany2/edge-tts drm.py. This is a
    # port of that digest, loaded by bin/tts-worker over the gem until the gem ships it.
    module EdgeGec
      MASK = 0xFFFFFFFF
      WIN_EPOCH = 11_644_473_600

      SHA256_INITIAL = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
                        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19].freeze
      SHA256_STATE = [0xFD9FBEA2, 0x91243CE7, 0xBE499094, 0xCD2E1E0A,
                      0x6C006F49, 0x04BD35AB, 0xFEB0A7E4, 0x03EFFBD2].freeze
      SCHEDULE = [0xEB24BF9E, 0x1558691F, 0xA0C09EE2, 0x0CFA32BA, 0xA622EE8C, 0xD1DD9491, 0xC0DD25A0,
                  0xF9E70AB6, 0xF0C31573, 0x7058CE4E, 0x7188E606, 0x00E5AB33, 0xD258B060, 0x72766564].freeze
      ROUND_K = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
      ].freeze
      ADJUSTMENT = 0xC9DC06A7
      BLOCK_K = ROUND_K.dup.tap { |k| k[14] = ADJUSTMENT }.freeze
      SIGMA0_ADJUSTMENT = 0x059C0B80
      SIGMA1_ADJUSTMENT = 0x000B92C0

      CS64 = [[0xE82E91B1, 0xB32700D0], [0x44DE24C6, 0x88DFF51D], [0x3BEB65BC, 0x29514038],
              [0xC89C5933, 0xB328CBDF], [0x8D1EC211, 0xD405B4D5], [0x314EF5D5, 0x26E55F3C],
              [0xE92491B1, 0x607801C6], [0xF0A5B9D5, 0x82B2C1FB], [0x06064CF3, 0xFA51A3DA],
              [0xDA79FA60, 0x207CC464], [0xBED20560, 0x3C3C74F3], [0x89F9C9F8, 0xD2D14B61],
              [0x35FA38C6, 0xBB04A2C1], [0xCB49E3C6, 0xC5626167]].freeze
      CS64_FACTOR = 0x82893933
      CS64_ADJUSTMENT0 = 0xF2F90B1A
      CS64_ADJUSTMENT1 = 0x0B1A0000

      module_function

      def rol16(value) = (((value & MASK) << 16) | ((value & MASK) >> 16)) & MASK

      def ror(value, bits) = ((value >> bits) | (value << (32 - bits))) & MASK

      def sigma0(value) = ((value >> 7) ^ (value << 25) ^ (value >> 18) ^ (value << 14) ^ (value >> 3)) & MASK

      def sigma1(value) = ((value >> 17) ^ (value << 15) ^ (value >> 19) ^ (value << 13) ^ (value >> 10)) & MASK

      def expand(words, from = 16)
        (from...64).each do |i|
          words[i] = (sigma1(words[i - 2]) + words[i - 7] + sigma0(words[i - 15]) + words[i - 16]) & MASK
        end
      end

      def rounds(state, words, first = 0)
        k = first == 14 ? BLOCK_K : ROUND_K
        a, b, c, d, e, f, g, h = state
        (first...64).each do |i|
          t1 = h + (ror(e, 6) ^ ror(e, 11) ^ ror(e, 25)) + (g ^ (e & (f ^ g))) + k[i] + words[i]
          t2 = (ror(a, 2) ^ ror(a, 13) ^ ror(a, 22)) + ((a & b) | (c & (a | b)))
          a, b, c, d, e, f, g, h = (t1 + t2) & MASK, a, b, c, (d + t1) & MASK, e, f, g
        end
        [a, b, c, d, e, f, g, h]
      end

      def sha256_init(prefix)
        words = Array.new(14, 0) + [prefix[0, 3].unpack1("H*").to_i(16), prefix[3, 4].unpack1("N")]
        (16...30).each { |i| words[i] = schedule_word(words, i) }
        words[30] = (sigma1(words[28]) + words[23] + sigma0(words[15]) + words[14] + ADJUSTMENT - ROUND_K[14]) & MASK
        expand(words, 31)
        rounds(SHA256_STATE, words, 14).zip(SHA256_INITIAL).map { |x, y| (x + y) & MASK }
      end

      def schedule_word(words, i)
        value = SCHEDULE[i - 16]
        value += i == 16 ? (sigma1(words[i - 2]) ^ SIGMA1_ADJUSTMENT) : sigma1(words[i - 2]) if i - 2 >= 14
        value += words[i - 7] if i - 7 >= 14
        value += i == 29 ? (sigma0(words[i - 15]) ^ SIGMA0_ADJUSTMENT) : sigma0(words[i - 15]) if i - 15 >= 14
        value & MASK
      end

      def sha256_digest(data)
        raise ArgumentError, "token salt must hold at least seven bytes" if data.bytesize < 7

        length = 57 + data.bytesize
        padded = data.byteslice(7..).b + "\x80".b + ("\x00".b * ((55 - length) % 64)) + [length * 8].pack("Q>")
        state = sha256_init(data.byteslice(0, 7).b)
        padded.bytes.each_slice(64) do |block|
          words = block.pack("C*").unpack("N16")
          expand(words)
          state = state.zip(rounds(state, words)).map { |x, y| (x + y) & MASK }
        end
        state.pack("N8")
      end

      def cs64_digest(data, digest)
        key_a, key_b = digest.unpack("VV").map { |key| key | 1 }
        factors = [(key_a * CS64_FACTOR) & MASK, (key_b * CS64_FACTOR) & MASK]
        terms = CS64.each_with_index.map { |(coefficient, _), i| (coefficient * factors[i % 2]) & MASK }
        offsets = CS64.map(&:last)
        cs64_words(data).each_with_index do |word, i|
          term = word * (i.even? ? key_a : key_b)
          offset = rol16(word) * (i.even? ? 0xEF0569FB : 0xC31713DB)
          term, offset = term + (CS64_ADJUSTMENT0 * factors[0]), offset + CS64_ADJUSTMENT1 if i.zero?
          terms << (term & MASK)
          offsets << (offset & MASK)
        end
        cs64_fold(terms, offsets, key_a, key_b)
      end

      def cs64_words(data)
        padded = "\x00".b + data.b
        padded += "\x00".b * ((-padded.bytesize) % 4)
        words = padded.unpack("V*")
        words << 0 if words.size.odd?
        words
      end

      def cs64_fold(terms, offsets, key_a, key_b)
        swap_acc = swap_last = state = acc = 0
        terms.each_slice(2).with_index do |(x, y), n|
          swap_acc, swap_last = cs64_swap(swap_acc, offsets[2 * n], x, offsets[2 * n + 1], y)
          state, acc = cs64_mix(state, acc, x, y, key_a, key_b)
        end
        [swap_last ^ state, swap_acc ^ acc]
      end

      def cs64_swap(swap_acc, offset_x, x, offset_y, y)
        q = (rol16((offset_x + x) & MASK) * 0x76F50F34) & MASK
        swap_acc += (rol16(q) * 0xC3EFEA97 + q) & MASK
        q = (rol16((offset_y + y) & MASK) * 0x1881CE3C) & MASK
        swap_last = (rol16(q) * 0x35BD1EC9 + q) & MASK
        [(swap_acc + swap_last) & MASK, swap_last]
      end

      def cs64_mix(state, acc, x, y, key_a, key_b)
        state = (state * key_a + x) & MASK
        [0xCF98B111, 0x87085B9F, 0x12CEB96D, 0x257E1D83].each { |m| state = (rol16(state) * m) & MASK }
        acc += state
        t = (state * key_b + y) & MASK
        t = (rol16(t) * 0xA27416F5) & MASK
        t = (rol16(t) * 0xD38396FF) & MASK
        state = (rol16((rol16(t) * 0x7C932B89) & MASK) * 0xBFA49F69) & MASK
        [state, (acc + state) & MASK]
      end

      def token(now = RbEdgeTTS::DRM.get_unix_timestamp)
        ticks = now + WIN_EPOCH
        ticks -= ticks % 300
        data = (ticks * 10_000_000.0).to_i.to_s + RbEdgeTTS::TRUSTED_CLIENT_TOKEN
        digest = sha256_digest(data)
        cs64 = cs64_digest(data, digest).pack("VV").unpack1("H*").upcase
        "#{cs64}-#{digest.unpack1("H*").upcase}"
      end

      # DRM's token method, replaced ahead of the gem's own.
      module Token
        def generate_sec_ms_gec = EdgeGec.token
      end

      def install!
        version = "2-#{RbEdgeTTS::CHROMIUM_FULL_VERSION}"

        RbEdgeTTS.class_eval do
          remove_const(:SEC_MS_GEC_VERSION)
          const_set(:SEC_MS_GEC_VERSION, version)
        end

        RbEdgeTTS::DRM.singleton_class.prepend(Token)
      end
    end
  end
end
