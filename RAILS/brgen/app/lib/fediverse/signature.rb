# frozen_string_literal: true

module Fediverse
  # HTTP Signatures (draft-cavage-http-signatures), which is what the fediverse
  # actually speaks — not RFC 9421.
  #
  # This is the security boundary of the whole feature: an unsigned or
  # badly-verified inbox accepts a Delete for anyone's post and a Follow from
  # anyone's account. Everything here fails closed.
  module Signature
    # Signatures older than this are refused even if otherwise valid, so a
    # captured request cannot be replayed indefinitely. Mastodon uses 12 hours;
    # 5 minutes is enough for clock skew and delivery retries.
    MAX_AGE = 5.minutes

    # Headers we insist were covered by the signature. Without (request-target)
    # a signature for one path is valid for another; without digest a signed
    # request can have its body swapped; without date it replays forever.
    REQUIRED_COVERAGE = %w[(request-target) host date digest].freeze

    module_function

    # Sign an outgoing request. Returns the headers to merge.
    def sign(key:, key_id:, method:, url:, body:, extra_headers: {})
      uri = URI(url)
      digest = "SHA-256=#{Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(body.to_s))}"
      date = Time.now.httpdate

      headers = {
        "Host" => uri.host,
        "Date" => date,
        "Digest" => digest,
        "Content-Type" => "application/activity+json",
      }.merge(extra_headers)

      covered = %w[(request-target) host date digest]
      signing_string = covered.map do |header|
        if header == "(request-target)"
          "(request-target): #{method.to_s.downcase} #{uri.request_uri}"
        else
          "#{header}: #{headers.fetch(header.capitalize)}"
        end
      end.join("\n")

      signature = Base64.strict_encode64(key.sign(OpenSSL::Digest.new("SHA256"), signing_string))
      headers["Signature"] =
        %(keyId="#{key_id}",algorithm="rsa-sha256",headers="#{covered.join(' ')}",signature="#{signature}")
      headers
    end

    # Verify an incoming request. Returns true only if everything holds.
    #
    # `public_key_for` is a callable taking the keyId and answering an
    # OpenSSL::PKey::RSA — passed in rather than reached for, so verification
    # has no opinion about where keys are cached and can be tested without one.
    def verify(request:, body:, public_key_for:)
      parsed = parse(request.headers["Signature"])
      return false if parsed.blank?

      covered = parsed["headers"].to_s.split(/\s+/)
      # Fail closed on partial coverage: a signature over nothing but Date is a
      # valid signature that proves nothing about this request.
      return false unless (REQUIRED_COVERAGE - covered).empty?
      return false unless fresh?(request.headers["Date"])
      return false unless digest_matches?(request.headers["Digest"], body)

      key = public_key_for.call(parsed["keyId"])
      return false if key.blank?

      signing_string = covered.map { |header| header_line(header, request) }.join("\n")
      signature = Base64.decode64(parsed["signature"].to_s)
      key.verify(OpenSSL::Digest.new("SHA256"), signature, signing_string)
    rescue OpenSSL::PKey::PKeyError, ArgumentError
      false
    end

    def parse(header)
      return {} if header.blank?

      header.scan(/(\w+)="([^"]*)"/).to_h
    end

    def fresh?(date)
      return false if date.blank?

      (Time.now - Time.httpdate(date)).abs <= MAX_AGE
    rescue ArgumentError
      false
    end

    # The Digest header is what ties the signature to this body. Without
    # checking it, a signed request can carry any payload at all.
    def digest_matches?(header, body)
      return false if header.blank?

      expected = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(body.to_s))
      provided = header.to_s.split("=", 2).last
      ActiveSupport::SecurityUtils.secure_compare(provided.to_s, expected)
    end

    def header_line(header, request)
      case header
      when "(request-target)"
        "(request-target): #{request.method.downcase} #{request.fullpath}"
      when "host"
        "host: #{request.host_with_port.sub(/:(80|443)\z/, '')}"
      else
        "#{header}: #{request.headers[header.split('-').map(&:capitalize).join('-')]}"
      end
    end
  end
end
