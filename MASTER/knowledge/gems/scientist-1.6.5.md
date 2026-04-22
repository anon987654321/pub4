require "scientist"
require "ostruct"

# frozen_string_literal: true

# Widget permission checker built on the Scientist gem.
# Executes a control (trusted) path and a candidate (experimental) path,
# returning the control's result while logging any divergence.
class MyWidget
  include Scientist

  # Creates a new widget checker.
  #
  # @param model [Object] the underlying domain model (must respond to
  #   +check_user+). Passing the model explicitly makes the class easier to test
  #   and removes hidden dependencies.
  def initialize(model: nil)
    @model = model
  end

  # Determines whether +user+ may read the widget.
  #
  # @param user [User] the actor whose permissions are being checked
  # @return [Boolean] result of the control branch
  # @raise [ArgumentError] if +user+ does not respond to +can?+
  def allows?(user)
    raise ArgumentError, "user must respond to #can?" unless user.respond_to?(:can?)

    science("widget-permissions") do |experiment|
      # Trusted, production logic.
      experiment.use { model.check_user(user).valid? }

      # Experimental logic under test.
      experiment.try { user.can?(:read, model) }
    end
  end

  private

  # Lazily resolves the widget's underlying model.
  #
  # In production this should return an ActiveRecord model or similar domain
  # object. A placeholder is provided for test environments.
  #
  # @return [Object] the widget model
  def model
    @model ||= OpenStruct.new # replace with actual model lookup
  end
end