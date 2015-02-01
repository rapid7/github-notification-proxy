require 'erb'
require 'yaml'

module GithubNotificationProxy
  # Returns the `Config` singleton.
  #
  # @return [Config]
  def self.config
    @config ||= Config.new(config_file)
  end

  # The config file to read configuration from.
  #
  # @return [String] config/config.yml
  def self.config_file
    File.expand_path('../config/config.yml', File.dirname(__FILE__))
  end

  # Returns a `Config` singleton for database configuration
  #
  # @return [Config]
  def self.db_config
    @db_config ||= Config.new(db_config_file)
  end

  # The config file to read configuration from.
  #
  # @return [String] config/database.yml
  def self.db_config_file
    File.expand_path('../config/database.yml', File.dirname(__FILE__))
  end

  class ERBContext
    def initialize(hash)
      hash.each_pair do |key, value|
        instance_variable_set('@' + key.to_s, value)
      end
    end

    def get_binding
      binding
    end
  end

  # Represents configuration loaded from `config/config.yml`.
  class Config < Hash
    def initialize(config_file)
      super
      merge!(defaults)
      if File.exist?(config_file)
        erb_context = ERBContext.new(root_dir: File.expand_path('..', File.dirname(__FILE__)))
        str = File.read(config_file)
        erb = ERB.new(str).result(erb_context.get_binding)
        hash = YAML.load(erb)
        merge!(hash)
      end
    end

    def defaults
      {
        'handlers' => {},
        'max_payload_size' => 1024 * 128,
        'server_url' => 'http://localhost:9292',
        'ws_sleep_delay' => 5,
        'ws_max_lifetime' => 14400,
        'ws_auto_reconnect' => true,
        'client_log_file' => nil,
        'client_log_level' => 'info',
      }
    end

    def log_dir
      File.join(root_dir, 'log')
    end

    def root_dir
      @root_dir ||= File.expand_path('..', File.dirname(__FILE__))
    end

    def method_missing(meth, *args, &block)
      if has_key?(meth.to_s)
        fetch(meth.to_s)
      elsif has_key?(meth.to_sym)
        fetch(meth.to_sym)
      elsif meth =~ /^(.+)=$/
        store($1, args[0])
      elsif meth =~ /^[a-zA-Z_\-]+$/
        nil
      else
        super
      end
    end
  end
end
