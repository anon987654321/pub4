#!/usr/bin/env ruby

# Simple Calculator class in Ruby
class Calculator
  def add(a, b)
    a + b
  end

  def subtract(a, b)
    a - b
  end

  def multiply(a, b)
    a * b
  end

  def divide(a, b)
    raise ArgumentError, "Cannot divide by zero" if b.zero?
    a.to_f / b
  end
end

# Demo usage
if __FILE__ == $PROGRAM_NAME
  calc = Calculator.new
  
  puts "Calculator Demo"
  puts "=" * 30
  puts "5 + 3 = #{calc.add(5, 3)}"
  puts "10 - 4 = #{calc.subtract(10, 4)}"
  puts "6 * 7 = #{calc.multiply(6, 7)}"
  puts "15 / 3 = #{calc.divide(15, 3)}"
end
