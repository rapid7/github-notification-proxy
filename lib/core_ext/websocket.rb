module WebSocket
  module Handshake
    class Server
      # Work around a bug that prevents websockets from working on Passenger.
      # Passenger doesn't support readpartial on rack.input and Passenger's
      # read is blocking.  This replaces rack.input with a null IO object
      # for the from_rack method.
      # See https://github.com/ngauthier/tubesock/issues/10#issuecomment-25471793
      def from_rack_with_nullio(env)
        rack_input = env['rack.input']
        env['rack.input'] = StringIO.new
        begin
          from_rack_without_nullio(env)
        ensure
          env['rack.input'] = rack_input
        end
      end
      alias_method :from_rack_without_nullio, :from_rack
      alias_method :from_rack, :from_rack_with_nullio
    end
  end
end
