# Aight REPL - Usage Examples
This document provides practical examples of using the aight REPL with LLM integration.

## Quick Start
```bash
cd aight
./aight.rb
```

## Example Session 1: Basic Ruby Evaluation

```ruby

# Start aight
$ ./aight.rb
🚀 Aight REPL v1.0.0

📦 Model: gpt-4

🔒 Security: standard

💡 Type .help for commands, .exit to quit

# Simple arithmetic

aight[gpt]> 2 + 2

=> 4
# Array operations

aight[gpt]> [1, 2, 3, 4, 5].select(&:even?)

=> [2, 4]
# String manipulation

aight[gpt]> "hello world".split.map(&:capitalize).join(" ")

=> "Hello World"
# Method chaining

aight[gpt]> (1..10).map { |n| n ** 2 }.sum

=> 385
```

## Example Session 2: LLM-Powered Code Analysis

```ruby

# Execute code
aight[gpt]> def fibonacci(n); n <= 1 ? n : fibonacci(n-1) + fibonacci(n-2); end
=> :fibonacci

# Ask for explanation

aight[gpt]> .explain

🤔 Analyzing result...
💡 This is a Symbol representing the method name :fibonacci. In Ruby, defining a

method returns a symbol with the method's name. This indicates the recursive

fibonacci method has been successfully defined.

# Get refactoring suggestions

aight[gpt]> .refactor def fibonacci(n); n <= 1 ? n : fibonacci(n-1) + fibonacci(n-2); end

🔄 Analyzing code for refactoring opportunities...
♻️ Consider memoization to improve performance:

def fibonacci(n, memo = {})

  return n if n <= 1

  memo[n] ||= fibonacci(n-1, memo) + fibonacci(n-2, memo)

end

This reduces time complexity from O(2^n) to O(n).

```

## Example Session 3: Test Generation

```ruby

# Define a method
aight[gpt]> def divide(a, b); raise ArgumentError if b.zero?; a / b; end
=> :divide

# Generate tests

aight[gpt]> .test def divide(a, b); raise ArgumentError if b.zero?; a / b; end

🧪 Generating tests...
🧪 Suggested tests:

describe '#divide' do

  it 'divides two positive numbers' do

    expect(divide(10, 2)).to eq(5)
  end

  it 'handles negative numbers' do

    expect(divide(-10, 2)).to eq(-5)

    expect(divide(10, -2)).to eq(-5)
  end

  it 'handles zero numerator' do

    expect(divide(0, 5)).to eq(0)

  end
  it 'raises ArgumentError for zero denominator' do

    expect { divide(10, 0) }.to raise_error(ArgumentError)

  end
  it 'handles floating point division' do

    expect(divide(5, 2)).to eq(2.5)

  end
end

```

## Example Session 4: Security Analysis

```ruby

# Check potentially unsafe code
aight[gpt]> .security eval(params[:code])
🔒 Analyzing security...

🛡️ Critical vulnerability: `eval(params[:code])` allows arbitrary code execution.

Security issues:

1. Remote Code Execution (RCE): Attacker can execute any Ruby code

2. No input validation or sanitization
3. Violates zero trust principles

Recommendations:

- Never use eval() with user input

- Use JSON.parse for data parsing
- Use YAML.safe_load with allowed classes

- Implement strict allowlisting for allowed operations

- Consider using a DSL with limited capabilities

```

## Example Session 5: Documentation Generation

```ruby

# Generate documentation
aight[gpt]> .doc def calculate_discount(price, percentage); price * (1 - percentage / 100.0); end
📝 Generating documentation...

📚

# Calculates the discounted price

#

# @param price [Numeric] The original price

# @param percentage [Numeric] The discount percentage (0-100)

# @return [Float] The price after applying the discount

#

# @example

#   calculate_discount(100, 20)  #=> 80.0

#   calculate_discount(50, 10)   #=> 45.0

#

# @raise [ArgumentError] if percentage is not between 0 and 100

def calculate_discount(price, percentage)

  raise ArgumentError, "Invalid percentage" unless (0..100).cover?(percentage)

  price * (1 - percentage / 100.0)

end

```

## Example Session 6: Performance Optimization

```ruby

# Analyze performance
aight[gpt]> .performance arr.map { |x| x * 2 }.select { |x| x > 10 }
⚡ Analyzing performance...

🚀 Performance improvements:

1. Combine map and select into a single pass:

   arr.filter_map { |x| (x * 2) if x * 2 > 10 }

2. Use each_with_object for more complex transformations:
   arr.each_with_object([]) { |x, acc| acc << x * 2 if x * 2 > 10 }

3. For large datasets, consider lazy evaluation:
   arr.lazy.map { |x| x * 2 }.select { |x| x > 10 }.force

Performance gain: ~40% faster for large arrays (>1000 elements)
Memory: Reduced by avoiding intermediate array allocation

```
## Example Session 7: History and Context Management

```ruby

# Check session context
aight[gpt]> .context
📊 Current Context:

  Session duration: 5m

  Commands executed: 12

  Cognitive load: 3/7

  Model: gpt-4

  Security: standard

# View command history

aight[gpt]> .history 5

📜 Recent History:
[12:34:56] [1,2,3].sum

        => 6

[12:35:02] "hello".upcase

        => "HELLO"

[12:35:10] .explain

[12:35:20] def foo; bar; end

        => :foo

[12:35:25] .context

# Clear context when cognitive load is high

aight[gpt]⚠️> .clear

✨ Context cleared, cognitive load reset
```

## Example Session 8: Model Switching

```ruby

# Check current model
aight[gpt]> .model
Current model: gpt-4

Usage: .model <model_name>

# Switch to a different model

aight[gpt]> .model gpt-3.5-turbo

✅ Model changed to: gpt-3.5-turbo
# Now using faster, cheaper model

aight[gpt-3]> .explain

🤔 Analyzing result...
💡 [Using gpt-3.5-turbo for faster responses]

```

## Example Session 9: Without LLM API (Offline Mode)

```ruby

# When API keys are not configured
aight[gpt]> .explain
🤔 Analyzing result...

💡 [LLM API not configured. Set OPENAI_API_KEY or ANTHROPIC_API_KEY environment variable]

Mock response: This would analyze your code and provide insights...

# Ruby evaluation still works

aight[gpt]> (1..5).map(&:to_s).join("-")

=> "1-2-3-4-5"
```

## Example Session 10: Starship Integration

```bash

# Before starting aight
$ export AIGHT_MODEL="claude-3-opus"
$ eval "$(starship init zsh)"

# Your prompt shows:

user@host ~/projects $

# After starting aight
$ ./aight.rb

# Starship prompt now shows:
user@host ~/projects 🤖 claude-3-opus $

# In REPL with high cognitive load:

aight[claude]🔥>

# Starship shows: 🤖 claude-3-opus 🔥
# With security on OpenBSD:

aight[gpt]>

# Starship shows: 🤖 gpt-4 🔒
```

## Configuration Examples

### .zshrc Setup

```bash
# Add to ~/.zshrc
# Aight environment
export AIGHT_MODEL="gpt-4"

export OPENAI_API_KEY="your-key-here"
# Completions

fpath=(~/.zsh/completions $fpath)

autoload -Uz compinit && compinit
# Starship

eval "$(starship init zsh)"

# Optional: Alias for quick access
alias ai='cd /path/to/pub3/aight && ./aight.rb'

```
### Starship Config Customization

```toml

# Add to ~/.config/starship/starship.toml
# Customize aight module colors
[custom.aight]

format = "[$output]($style) "
style = "bold purple"  # Change from blue to purple

[custom.aight_model]

format = "[$output]($style) "

style = "bright-cyan"  # Brighter cyan
# Add custom icons

[custom.aight_load]

format = "[$output]($style) "
style = "bold yellow"

```

## Tips and Tricks

### 1. Quick Code Snippets

```ruby
# Define helper methods in REPL
aight[gpt]> def quick_sort(arr); arr.size <= 1 ? arr : quick_sort(arr.select{|x| x < arr[0]}) + [arr[0]] + quick_sort(arr.select{|x| x > arr[0]}); end
=> :quick_sort

aight[gpt]> quick_sort([3,1,4,1,5,9,2,6])

=> [1, 1, 2, 3, 4, 5, 6, 9]

```
### 2. Load External Files

```ruby

# Load a Ruby file into REPL
aight[gpt]> load 'path/to/helpers.rb'
=> true

# Now use methods from that file

aight[gpt]> my_helper_method

```
### 3. Multi-line Input

```ruby

# Use line continuation
aight[gpt]> def complex_method(x)
aight[gpt]>   if x > 10

aight[gpt]>     "large"

aight[gpt]>   else

aight[gpt]>     "small"

aight[gpt]>   end

aight[gpt]> end

=> :complex_method

```

### 4. Quick Performance Testing

```ruby

# Time operations
aight[gpt]> require 'benchmark'
aight[gpt]> Benchmark.measure { 1_000_000.times { [].push(1) } }

```

### 5. Cognitive Load Management

- Monitor the indicator in your prompt

- Use `.clear` when you see 🔥 or 💥
- Use `.history` to review recent work
- Use `.context` to check session stats

## Exit REPL

```ruby

# Any of these work:
aight[gpt]> .exit
aight[gpt]> exit

aight[gpt]> ^D (Ctrl-D)

aight[gpt]> ^C (Ctrl-C) then confirm

```

## Running Tests

```bash

# Run the test suite
cd /home/runner/work/pub3/pub3/aight
./test_aight.rb

```

## Troubleshooting

### Issue: Command not found

**Solution**: Make sure aight.rb is executable
```bash
chmod +x aight.rb

```

### Issue: readline not loading history

**Solution**: Check permissions on history file

```bash
ls -la ~/.aight_history

chmod 600 ~/.aight_history

```

### Issue: Starship module not showing

**Solution**: Verify environment variables

```bash
env | grep AIGHT

echo $AIGHT_MODEL

```

### Issue: LLM API errors

**Solution**: Verify API key is set

```bash
echo $OPENAI_API_KEY | head -c 10

# Should show: sk-proj-... or sk-...

```

## Next Steps

1. Try the examples above

2. Experiment with LLM-powered commands
3. Customize your Starship prompt
4. Create your own helper methods

5. Build a library of useful snippets

For more information, see the main [README.md](README.md).

