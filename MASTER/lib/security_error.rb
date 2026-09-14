# frozen_string_literal: true

# A file of its own despite FILE_SPRAWL: Zeitwerk resolves Master::SecurityError
# at lib/security_error.rb and nowhere else, so absorbing it moves the constant.
module Master
  class SecurityError < StandardError; end
end
