require 'rubygems'
require 'bundler/setup'

require 'json'
require 'sinatra/base'
require 'sinatra/hijacker'

# Monkey-patch gems with patches/fixes
require 'core_ext'

require 'config'
require 'database'
require 'logger'
Logger.class_eval { alias :write :'<<' }

$stats_received_cnt = 0
$stats_delivered_cnt = 0

module GithubNotificationProxy

  # `Server` is a `Sinatra` application that receives and delivers Github
  # notifications.
  class Server < Sinatra::Base
    register Sinatra::Hijacker

    def self.logger
      @logger ||= begin
        if GithubNotificationProxy.config.server_log_file.nil? || GithubNotificationProxy.config.server_log_file.strip.empty?
          logger = ::Logger.new($stdout)
        else
          logger = ::Logger.new(File.absolute_path(GithubNotificationProxy.config.server_log_file, GithubNotificationProxy.config.log_dir))
        end
        logger.level = ::Logger.const_get(GithubNotificationProxy.config.server_log_level.upcase)
        logger
      end
    end

    configure :production, :development do
      use Rack::CommonLogger, logger
    end

    # Acknowledges (deletes) notifications given a JSON array of IDs.
    def ack(data)
      data = begin
        JSON.parse(data)
      rescue JSON::ParserError
        logger.error "Don't know how to acknowledge: #{data}"
        return false
      end
      logger.debug "ack, data: #{data.inspect}"

      result = true
      if data && data['ack'] && data['ack'].is_a?(Array)
        data['ack'].each do |id|
          notification = Notification.get(id)
          if notification
            if (id > $stats_delivered_cnt)
                $stats_delivered_cnt = id
            end
            logger.info "Acknowledged \##{id}: #{notification.handler}/#{notification.path}"
            result &= notification.destroy
          end
        end
      end

      result
    end

    def notification_headers
      headers = request.env.inject({}) do |memo, (key, val)|
        if key.start_with?('HTTP_')
          header = key.gsub(/^HTTP_/, '')
          # Try to convert back to raw, non-rack headers
          header = header.gsub(/_/, '-')
          header = header.split(/(\W)/).map(&:capitalize).join

          memo[header] = val
        end
        memo
      end

      # Return on User-Agent and X-* headers
      headers.select do |key, val|
        key.start_with?('X-') || key == 'User-Agent'
      end
    end

    get '/' do
      "GitHub Notification Proxy"
    end

    post '/:handler/*' do |handler, path|
      request.body.rewind
      payload = request.body.read

      max_payload_size = GithubNotificationProxy.config.max_payload_size
      if payload.length > max_payload_size
        logger.error "Truncating payload from #{payload.length} to #{max_payload_size} for handler=#{handler}, path=#{path}"
        payload = payload.slice(0, max_payload_size)
      end

      path += "?#{request.query_string}" if request.query_string && !request.query_string.empty?
      notification = Notification.new(
        handler: handler,
        path: path,
        content_type: request.content_type,
        payload: payload,
        headers: notification_headers,
        received_at: Time.now,
      )
      if notification.save
        if (notification.id > $stats_received_cnt)
          $stats_received_cnt = notification.id
        end
        200
      else
        logger.error "Error saving notification: #{notification.errors.full_messages.join(', ')}"
        500
      end
    end

    get '/retrieve' do
      content_type 'application/json'
      JSON.generate(Notification.undelivered)
    end

    put '/ack' do
      request.body.rewind
      if ack(request.body.read)
        200
      else
        [500, 'An error occurred while acknowledging notifications']
      end
    end

    get '/status' do
      content_type 'application/json'
      stats = {
        'received' => $stats_received_cnt,
        'delivered' => $stats_delivered_cnt
      }
      JSON[stats]
    end

    websocket '/retrieve-ws' do
      closed = false
      closed_mutex = Mutex.new
      closed_resource = ConditionVariable.new

      ws.onclose do
        closed_mutex.synchronize {
          closed = true
          closed_resource.broadcast()
        }
      end

      ws.onmessage do |msg|
        ack(msg)
      end

      thread = Thread.new do
        logger.debug "web socket thread ##{Thread.current.object_id}, started"
        Thread.current.abort_on_exception = true

        # Close connections older than ws_max_lifetime to force clients
        # to reconnect
        ws_max_lifetime = GithubNotificationProxy.config.ws_max_lifetime.to_i

        # Loop until the connection closes, checking the database
        # for new notifications every `sleep_delay` seconds.
        sleep_delay = GithubNotificationProxy.config.ws_sleep_delay

        start = Time.now
        delivered_ids = []
        loop do
          if Notification.count > 0
            notifications = Notification.undelivered

            # Don't deliver notifications we've already delivered to this websocket
            delivery = notifications.reject do |n|
              delivered_ids.include?(n.id)
            end

            unless delivery.empty?
              delivery.each do |notification|
                logger.debug "web socket thread ##{Thread.current.object_id}, deliver ##{notification.id}"
                logger.info "Delivering \##{notification.id}: #{notification.handler}/#{notification.path}"
              end
              ws.send_data(JSON.generate(delivery))
            end

            # Keep track of sent notifications so we do not resend them
            delivered_ids = notifications.map { |n| n.id }
          end
          closed_mutex.synchronize {
            # Sleep `sleep_delay` seconds (or until connection closes)
            closed_resource.wait(closed_mutex, sleep_delay)
          }
          break if closed
          break if ws_max_lifetime > 0 && (Time.now > start + ws_max_lifetime)
        end

        unless closed
          ws.send_data(nil, :close)
          ws.close
        end

        logger.debug "web socket thread ##{Thread.current.object_id}, finished"
      end

      # Return async rack response
      [-1, {}, []]
    end

    private

    def logger
      self.class.logger
    end
  end
end
