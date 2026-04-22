# frozen_string_literal: true
# typed: strict

class User
  extend T::Sig

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.nilable(T.untyped)) }
  private attr_reader :profile

  sig { params(name: String, profile: T.nilable(T.untyped)).void }
  def initialize(name, profile = nil)
    @name = T.let(name, String)
    @profile = T.let(profile, T.nilable(T.untyped))
  end

  # Returns the user's email if present, otherwise nil.
  sig { returns(T.nilable(String)) }
  def email
    @profile&.email
  end
end