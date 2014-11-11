require 'data_mapper'
require 'config'


db_config = GithubNotificationProxy.db_config[ENV['RACK_ENV']]
DataMapper.setup(:default, db_config)

class Notification
  include DataMapper::Resource
  property :id, Serial
  property :handler, String
  property :path, String, :length => 255
  property :payload, Text, :length => GithubNotificationProxy.config.max_payload_size
  property :headers, Json
  property :content_type, String
  property :received_at, Time

  def self.undelivered
    all(order: :received_at)
  end
end

DataMapper.finalize

# automatically create the notification table
Notification.auto_upgrade!
