ENV['RACK_ENV'] = 'test'

require 'simplecov'

require 'rspec'
require 'rack/test'
require 'database_cleaner'
require 'data_mapper'
require 'logger'

lib = File.expand_path('../lib', File.dirname(__FILE__))
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'database'

class NullLogger < ::Logger
  def initialize(*args)
    super(nil)
  end

  def add(*args, &block)
  end
end

RSpec.configure do |config|
  # Disable old "should" syntax.  Force all specs to use
  # the new "expect" syntax.
  config.expect_with(:rspec) {|c| c.syntax = :expect}

  config.include Rack::Test::Methods

  config.before(:suite) do
    DatabaseCleaner.clean_with :truncation
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
