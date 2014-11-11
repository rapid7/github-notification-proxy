default['github_notification_proxy']['http']['host_name'] = node['fqdn']
default['github_notification_proxy']['http']['host_aliases'] = []
default['github_notification_proxy']['http']['port'] = 80
default['github_notification_proxy']['http']['ssl']['port'] = 443
default['github_notification_proxy']['http']['ssl']['enabled'] = true
default['github_notification_proxy']['http']['ssl']['strict'] = node['github_notification_proxy']['http']['ssl']['enabled']

# The cert databag should have `cert` and `key` keys
default['github_notification_proxy']['http']['ssl']['cert_databag'] = 'github_notification_proxy'
default['github_notification_proxy']['http']['ssl']['cert_databag_item'] = 'ssl_cert'

default['github_notification_proxy']['http']['restrict_ips'] = []
