require "capistrano/configuration"
require "yaml"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
  config.mock_with(:rspec) { |c| c.syntax = :should }
end

# The recipes build commands by string interpolation, which leaves runs of
# spaces wherever an optional flag is empty.
RSpec::Matchers.define :command_line do |expected|
  match do |actual|
    actual.is_a?(String) && expected === actual.squeeze(" ").strip
  end
end
