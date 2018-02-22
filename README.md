# Github Notification Proxy

The Github Notification Proxy stores and delivers Github notifications to
protected locations without requiring firewall pinholes or port forwarding.
The server runs in the cloud or a DMZ and receives notifications from Github.
The client runs inside a network and polls (or uses websockets to continuously
monitor) the server for notifications.

No data from internal destinations is ever returned to Github.

At this time, the Github Notification Proxy does not support any form of
authentication or authorization.  It is recommended that you use host based
authentication on your webserver to protect access to the server URLs.

The server is built using Sinatra.  Notifications are stored in PostgreSQL and
discarded as soon as they are delivered.

## Reliability

The server makes no guarantees of reliability.  Notification messages from
Github are always accepted, regardless of whether they can be delivered.

The client acknowledges notifications regardless of whether they can be
delivered.

## Server

The Github Notification Proxy can run on any Rack-based server.  We recommend
[Puma](http://puma.io).  To start the server:

```sh
puma
```

Websockets are only supported on servers that support
[socket hijacking](https://github.com/rack/rack/pull/481) such as
[Phusion Passenger](https://www.phusionpassenger.com/) and [Puma](http://puma.io/).
Apache is known to not work properly with WebSockets.

## Client

The client polls the server for incoming notifications and delivers them
internally.  Handlers are defined in `config/config.yml`.  Regular expressions
are used to validate the notification URL and transform it into an internal URL
for delivery.

### Handler Configuration

Handler configuration is stored in `config/config.yml`.  Configuration looks similar to:

```yaml
handlers:
  jira-proxy:
    match: ^(\d+)/sync$
    url: https://myjiraserver.local/rest/bitbucket/1.0/repository/$1/sync
  jenkins-proxy:
    - match: ^my-job/([^\/]+)$
      url: https://myjenkinsserver.local/job/My-Job/build?token=myjenkinsbuildtoken&cause=$1
    - match: ^ghprbhook/$
      url: https://myjenkinsserver.local/ghprbhook/
```

In the above example, two handlers are defined `jira-proxy` and `jenkins-proxy`.
Notifications posted to `/444/sync` will be delivered to
`https://myjiraserver.local/rest/bitbucket/1.0/repository/444/sync`.

Notifications that do match a handler and regular expression will be logged and dropped.

### Poll

This processes any pending notifications and then immediately exits.  This is
useful in a cron job.

    ./bin/client process

### Continuous Monitoring

This monitors for notifications continuously (using a websocket).  This is
useful for daemons.

    ./bin/client start

### Check for notifications

To list notifications without processing them:

    ./bin/client check

## Chef

A [chef cookbook](cookbook/) is included in this repo for installing and configuring the
notification proxy.

## License

Copyright 2014, Rapid7 Inc.
MIT License
