lib = File.expand_path('lib', File.dirname(__FILE__))
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'server'

if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      # Don't carry database connections across passenger forks
      DataObjects::Pooling.pools.each { |pool| pool.dispose }
    end
  end
end

run GithubNotificationProxy::Server
