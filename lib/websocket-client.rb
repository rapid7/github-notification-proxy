require 'monitor'
require 'openssl'
require 'websocket'

module GithubNotificationProxy
  module WebSocket

    # A simple `Websocket` client.  Supports http and https connections.
    #
    # ##Usage
    #
    #     require 'websocket-client'
    #
    #     ws = WebSocket::Client.new('https://localhost/stream')
    #
    #     ws.onmessage do |msg|
    #       puts "Got: #{msg.data}"
    #     end
    #
    #     ws.run
    #
    # A single thread (separate from the websocket thread) is used for
    # callbacks.  This ensures messages will be received in order and that the
    # websocket will continue to function if callbacks perform long-running
    # actions.
    #
    # Adapted from: https://github.com/shokai/websocket-client-simple
    class Client
      attr_reader :url, :handshake

      def initialize(url)
        @url = url
        @closed = false
        @closing = false

        @callbacks = []
        @callbacks.extend(MonitorMixin)
        @callbacks_empty_cond = @callbacks.new_cond
        @callback_thread = nil

        @open_handlers    = []
        @message_handlers = []
        @close_handlers   = []
        @error_handlers   = []
      end

      # Starts the websocket.  Messages and other events will be delivered to
      # callbacks.
      #
      # @param block [Boolean] if true, this method will block until the
      #   socket closes.
      # @return [String] a string describing the error that caused the socket
      #   to close, or `nil`.  NOTE: If `block` is false, this will always return
      #   `nil`.
      def run(block=true)
        uri = URI.parse(url)
        if uri.scheme == 'https'
          tcp_socket = TCPSocket.new(uri.host, uri.port || 443)
          ssl_context = OpenSSL::SSL::SSLContext.new
          @socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
          @socket.sync_close = true
          @socket.connect
        else
          @socket = TCPSocket.new(uri.host, uri.port || 80)
        end
        @handshake = ::WebSocket::Handshake::Client.new :url => url.gsub(/^https?/, 'ws')
        @handshaked = false
        frame = ::WebSocket::Frame::Incoming::Client.new
        close_error = nil

        thread = Thread.new do
          Thread.current.abort_on_exception = true
          while !@closed do
            recv_data = nil
            begin
              recv_data = @socket.readpartial(2000)
            rescue EOFError
              close_error = 'Connection closed by server'
              @socket.close
              break
            rescue => e
              if @closed || @closing
                break
              else
                do_callbacks(:error, e)
              end
            end
            break if @closed
            next unless recv_data

            if @handshaked
              frame << recv_data
            else
              @handshake << recv_data
              if @handshake.finished?
                @handshaked = true
                frame << @handshake.leftovers if @handshake.leftovers
                do_callbacks(:open)
              end
            end

            while msg = frame.next
              if msg.type == :ping
                send(nil, type: :pong)
                next
              end
              if msg.type == :close
                close(false)
                break
              end
              do_callbacks(:message, msg.data)
            end
          end
          close
          do_callbacks(:close, close_error)
        end

        @socket.write @handshake.to_s

        # Wait for threads to finish (close)
        if block
          thread.join if thread.alive?
          @callback_thread.join if @callback_thread && @callback_thread.alive?
          close_error
        else
          nil
        end
      end

      # Registers an `open` callback.  This callback is triggered when
      # the websocket completes its initial handshake.
      #
      # @return [void]
      def onopen(&block)
        @open_handlers << block
      end

      # Registers callback to receive messages.
      #
      # @yield [String] an incoming message
      # @return [void]
      def onmessage(&block)
        @message_handlers << block
      end

      # Registers a `close` callback.  This callback is triggered when
      # the websocket closes.
      #
      # @return [void]
      def onclose(&block)
        @close_handlers << block
      end

      # Registers an `error` callback.  This callback is triggered when
      # the websocket encounters an error.
      #
      # @return [void]
      def onerror(&block)
        @error_handlers << block
      end

      # Perform callbacks on a separate worker thread.
      #
      # @param handler [Symbol] the callback to trigger
      # @param args the arguments to pass to the callback
      # @return [void]
      def do_callbacks(handler, *args)

        @callbacks.synchronize do
          @callbacks.push([handler, args])
          @callbacks_empty_cond.signal
        end

        unless @callback_thread and @callback_thread.alive?
          @callback_thread = Thread.new do
            Thread.current.abort_on_exception = true
            loop do
              handler = nil
              args = nil
              @callbacks.synchronize do
                @callbacks_empty_cond.wait_while { @callbacks.empty? }
                (handler, args) = @callbacks.shift
              end
              handlers = instance_variable_get("@#{handler}_handlers")
              handlers.each do |h|
                h.call(*args)
              end
              break if handler == :close
            end
          end
        end
      end
      private :do_callbacks

      # Sends a message over the websocket.
      #
      # @param data [String] data to send over the websocket
      # @return [void]
      def send(data, opt={:type => :text})
        return if !@handshaked or @closed or @socket.closed?
        type = opt[:type]
        frame = ::WebSocket::Frame::Outgoing::Client.new(:data => data, :type => type, :version => @handshake.version)
        begin
          @socket.write frame.to_s
        rescue Errno::EPIPE => e
          close(e)
        end
      end

      # Closes the websocket.
      #
      # @return [void]
      def close(send_close=true)
        return if @closed || @closing
        @closing = true
        if @socket && !@socket.closed?
          send(nil, :type => :close) if send_close
          @socket.close
        end
        @closed = true
        @socket = nil
      end

      # Is the websocket open?
      #
      # @return [Boolean]
      def open?
        @handshake.finished? and !@closed
      end
    end

  end
end
