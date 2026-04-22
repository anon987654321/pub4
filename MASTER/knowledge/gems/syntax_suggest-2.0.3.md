# frozen_string_literal: true

# A minimal dog that can bark.
class Dog
  # Outputs a bark to STDOUT.
  #
  # @return [void]
  def bark
    puts 'Woof!'
  end
end

# Usage example
dog = Dog.new
dog.bark # => Woof!
