#JSON Formatter for SimpleCov

Generates a `coverage.json` file in the `coverage` directory from SimpleCov results on Ruby 2.4+.

## Overview
The formatter reads SimpleCov’s coverage data and outputs JSON. The output format depends on the coverage type:

- Branch coverage follows the structure in `spec/fixtures/sample_with_branch.json`.
- Simple coverage follows the structure in `spec/fixtures/sample.json`.

## Usage
Add the formatter to your SimpleCov configuration to produce `coverage.json`.

## Development
Use Docker for testing and debugging.

- Run `make sh` to start a container shell.
- Run `make test` to execute tests and RuboCop.
- Run `make format` to auto‑format code with RuboCop.

## License
See the [License](https://github.com/codeclimate-community/simplecov_json_formatter/blob/master/LICENSE) file.