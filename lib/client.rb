require 'rubygems'
require 'bundler/setup'

require 'config'
require 'json'
require 'logger'
require 'thor'
require 'websocket-client'

module GithubNotificationProxy

  # `Client` is a `Thor` command line interface for interacting with the
  # server.
  class Client < Thor

    desc 'check', 'Check if there are any pending notifications without processing them'
    option :verbose, type: :boolean, aliases: :v
    def check
      notifications = fetch_notifications
      if notifications.length > 0
        notifications.each_with_index do |notification, i|
          received_at = Time.parse(notification['received_at'])
          puts "#{i+1}. #{notification['handler']}: #{notification['path']} (#{received_at})"
          if options[:verbose]
            indent = " " * ((i+1).to_s.length + 2)

            handler = parse_notification(notification)
            if handler
              puts "#{indent}#{handler['uri']}"
            else
              puts "Unknown handler"
            end

            puts "#{indent}Content-Type: #{notification['content_type']}"
            notification['headers'].each do |header, val|
              puts "#{indent}#{header}: #{val}"
            end

            notification['payload'].each_line do |line|
              puts "#{indent}#{line}"
            end
          end
        end
      else
        $stderr.puts "No notifications."
        exit 1
      end
    end

    desc 'process', 'Process pending notifications and exit immediately'
    def process
      ids = []
      fetch_notifications.each do |notification|
        if process_notification(notification)
          ids << notification['id']
        end
      end
      ack_notifications(ids)
    end

    desc 'start', 'Continuously monitor and process notifications'
    def start
      # Set process title
      $0 = 'github-notification-proxy'

      ws = nil
      err = nil
      reconnect = config.ws_auto_reconnect
      closed_mutex = Mutex.new
      closed_resource = ConditionVariable.new

      ['SIGINT', 'SIGTERM'].each do |signal|
        Signal.trap(signal) do
          Thread.new do
            Thread.current.abort_on_exception
            closed_mutex.synchronize {
              logger.info "Gracefulling stopping..."
              reconnect = false
              ws.close
              closed_resource.broadcast()
            }
          end
        end
      end

      loop do
        ws = WebSocket::Client.new("#{config.server_url}/retrieve-ws")

        ws.onmessage do |data|
          data = JSON.parse(data)
          ids = []
          data.each do |notification|
            if process_notification(notification)
              ids << notification['id']
            end
          end
          logger.info "Acknowleding #{ids.map {|id| "##{id}"}.join(', ')}"
          ws.send(JSON.generate({ack: ids}))
        end

        ws.onopen do
          logger.info "Connected"
        end

        ws.onerror do |error|
          logger.error error
        end

        if err = ws.run
          logger.error err
        end

        if reconnect
          logger.info "Reconnecting..."
          closed_mutex.synchronize {
            # Sleep for a few seconds to allow the server to reset.
            # The while loop is because a CTRL+C will signal the wait early.
            wait_until = Time.now + 5
            while (reconnect && Time.now < wait_until)
              closed_resource.wait(closed_mutex, 5)
            end
          }
        end

        break unless reconnect
      end

      exit 1 if err
    end

    no_commands do
      def config
        GithubNotificationProxy.config
      end

      def logger
        @logger ||= begin
          logger = ::Logger.new($stdout)
          logger.level = ::Logger::INFO
          logger
        end
      end

      def parse_notification(notification)
        unless config.handlers.has_key?(notification['handler'])
          logger.warn "Unknown handler: #{notification['handler']}"
          return
        end

        # Matches may be stored in either an array (with multiple possible
        # matches) or a hash.
        matches = config.handlers[notification['handler']]
        matches = [matches] unless matches.is_a?(Array)

        match_data = nil
        match = matches.find do |match|
          regex = Regexp.new(match['match'])
          match_data = regex.match(notification['path'])
        end

        unless match && match_data
          logger.warn "Path is not valid for the #{notification['handler']} handler: #{notification['path']}"
          return
        end

        urls = Array(match['url']).map do |url|
          match_data.captures.each_with_index do |val, i|
            url = url.gsub("$#{i+1}", val)
          end
          url
        end

        match.merge({
          'uris' => urls.map { |url| URI.parse(url) }
        })
      end

      # Process the notification.  This delivers the notification internally
      # using the handlers defined in config.yml.
      # A warning is logged if we can't parse or process the notification.
      #
      # @return [Boolean] true is always returned, even if we cannot process
      # the notification.
      def process_notification(notification)
        handler = parse_notification(notification)
        uris = handler['uris'] if handler
        if !uris || uris.empty?
          logger.warn "No uris found for notification: #{notification}"
          return true
        end

        if handler.has_key?('verify_ssl') && handler['verify_ssl'] === false
          verify_mode = OpenSSL::SSL::VERIFY_NONE
        else
          verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        uris.each do |uri|
          begin
            Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == 'https'), verify_mode: verify_mode) do |http|
              if handler.has_key?('method') && handler['method'].to_s == 'get'
                req = Net::HTTP::Get.new(uri.to_s)
              else
                req = Net::HTTP::Post.new(uri.to_s)
                req.body = notification['payload']
                req.content_type = notification['content_type']
              end
              [notification['headers'], handler['headers']].compact.each do |headers|
                headers.each do |header, val|
                  req[header] = val
                end
              end
              http.request(req) do |response|
                if (200..299).include?(response.code.to_i)
                  logger.info "Processed ##{notification['id']} #{uri} with status #{response.code}."
                else
                  logger.warn "Error #{response.code} notifying #{uri}."
                end
                headers = []
                response.each_header { |h, val| headers << "#{h}: #{val}" }
                logger.debug "Response headers:\n#{headers.join("\n")}"
                logger.debug "Response body:\n#{response.body}"
              end
            end
          rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, SocketError,
                 Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
            logger.warn "Error notifying #{uri}: #{e}"
          end
        end

        true
      end

      def fetch_notifications
        notifications = []
        uri = URI.parse("#{config.server_url}/retrieve")
        Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == 'https')) do |http|
          req = Net::HTTP::Get.new(uri.to_s)
          http.request(req) do |response|
            if response.code.to_i == 200
              notifications = JSON.parse(response.body)
            end
          end
        end
        notifications
      end

      def ack_notifications(ids)
        uri = URI.parse("#{config.server_url}/ack")
        Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == 'https')) do |http|
          req = Net::HTTP::Put.new(uri.to_s)
          req.body = JSON.generate({ack: ids})
          req.content_type = 'application/json'
          http.request(req)
        end
      end
    end
  end
end


