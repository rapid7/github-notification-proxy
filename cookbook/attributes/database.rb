default['github_notification_proxy']['db']['host'] = 'localhost'
default['github_notification_proxy']['db']['port'] = node['postgresql']['config']['port']
default['github_notification_proxy']['db']['name'] = 'github-notification-proxy'
default['github_notification_proxy']['db']['user'] = 'github-notification-proxy'
