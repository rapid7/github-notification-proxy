require 'rubygems'
require 'bundler/setup'

require 'config'
require 'json'
require 'logger'
require 'thor'
require 'net/http'
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

      err = nil
      closed_mutex = Mutex.new
      closed_resource = ConditionVariable.new

      ['SIGINT', 'SIGTERM'].each do |signal|
        Signal.trap(signal) do
          Thread.new do
            Thread.current.abort_on_exception
            closed_mutex.synchronize {
              err = true
              logger.info "Gracefulling stopping..."
              closed_resource.broadcast()
            }
          end
        end
      end

      loop do
        ids = []
        fetch_notifications.each do |notification|
          if process_notification(notification)
            ids << notification['id']
          end
        end
        ack_notifications(ids)

        sleep 1

        break if err
      end

      exit 1 if err
    end

    no_commands do
      def config
        GithubNotificationProxy.config
      end

      def logger
        @logger ||= begin
          if config.client_log_file.nil? || config.client_log_file.strip.empty?
            logger = ::Logger.new($stdout)
          else
            logger = ::Logger.new(File.absolute_path(config.client_log_file, config.log_dir))
          end
          logger.level = ::Logger.const_get(config.client_log_level.upcase)
          logger
        end
      end

      def parse_notification(notification)
        logger.debug "parse_notification ##{notification['id']}, enter"

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

        result = {}.merge(match).merge({
          'uris' => urls.map { |url| URI.parse(url) }
        })
        logger.debug "parse_notification ##{notification['id']}, return: #{result.inspect}"

        result
      end

      # Process the notification.  This delivers the notification internally
      # using the handlers defined in config.yml.
      # A warning is logged if we can't parse or process the notification.
      #
      # @return [Boolean] true is always returned, even if we cannot process
      # the notification.
      def process_notification(notification)
        logger.debug "process_notification ##{notification['id']}, enter"

        handler = parse_notification(notification)
        uris = handler['uris'] if handler
        if !uris || uris.empty?
          logger.warn "No uris found for notification: #{notification}"
          return true
        end
        logger.debug "process_notification ##{notification['id']}, uris: #{uris.map {|uri| uri.to_s}.join(', ')}"

        if handler.has_key?('verify_ssl') && handler['verify_ssl'] === false
          verify_mode = OpenSSL::SSL::VERIFY_NONE
        else
          verify_mode = OpenSSL::SSL::VERIFY_PEER
        end

        uris.each do |uri|
          logger.debug "process_notification ##{notification['id']}, process uri: #{uri.to_s}"
          begin
            Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == 'https'), verify_mode: verify_mode) do |http|
              if handler.has_key?('method') && handler['method'].to_s == 'get'
                req = Net::HTTP::Get.new(uri.request_uri)
              else
                req = Net::HTTP::Post.new(uri.request_uri)
                req.body = notification['payload']
                if !notification['content_type'].nil?
                  req.content_type = notification['content_type']
                end
              end
              [notification['headers'], handler['headers']].compact.each do |headers|
                headers.each do |header, val|
                  req[header] = val
                end
              end
              logger.debug "process_notification ##{notification['id']}, sending #{req.class} request"
              http.request(req) do |response|
                if (200..299).include?(response.code.to_i)
                  logger.info "Processed ##{notification['id']} #{uri} with status #{response.code}."
                else
                  logger.warn "Error #{response.code} notifying #{uri}."
                end
                headers = []
                response.each_header { |h, val| headers << "#{h}: #{val}" }
                logger.debug "process_notification ##{notification['id']}, response headers:\n#{headers.join("\n")}"
                logger.debug "process_notification ##{notification['id']}, response body:\n#{response.body}"
              end
            end
          rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, SocketError,
                 Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
            logger.warn "Error notifying #{uri}: #{e}"
          end
        end

        logger.debug "process_notification ##{notification['id']}, return: true"
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


