# frozen_string_literal: true
# instrument: code_lines=10 longest_method=1 public_methods=2

# `private` does not touch `def self.x`.
#
# Core::Constitution measured 16 public methods when three are its API and the
# other thirteen are rule factories only it calls. Every one is a class method,
# and `private` marks a position in the instance-method stream that class
# methods never enter — so a class written in that idiom reads as fully public
# no matter how it is arranged. ABSTRACTION was measuring the idiom.
#
# private_class_method names its methods rather than marking a position, which
# is why the counter collects the names and subtracts them instead of stopping
# where it appears.
class ClassMethods
  def self.build = new(helper)

  def self.helper = 1

  def initialize(value)
    @value = value
  end

  private_class_method :helper

  private

  def hidden = @value
end
