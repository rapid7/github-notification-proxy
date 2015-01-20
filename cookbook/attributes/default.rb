default['github_notification_proxy']['user'] = 'github'
default['github_notification_proxy']['group'] = node['github_notification_proxy']['user']

default['github_notification_proxy']['repo']['url'] = 'git://github.com/rapid7/github-notification-proxy.git'
default['github_notification_proxy']['repo']['revision'] = 'v0.1.4'

# Set the install mode for the default recipe (server or client)
default['github_notification_proxy']['install_type'] = nil

# The secrets databag can contain the following keys:
#   * database_password
default['github_notification_proxy']['secrets_databag'] = 'github_notification_proxy'
default['github_notification_proxy']['secrets_databag_item'] = 'secrets'
