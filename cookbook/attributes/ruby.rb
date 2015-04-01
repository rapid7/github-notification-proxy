default['github_notification_proxy']['ruby_version'] = 'ruby-2.2.1'
default['github_notification_proxy']['ruby_gemset'] = 'github-notification-proxy'
default['github_notification_proxy']['rvm_alias'] = 'github-notification-proxy'

default['rvm']['version'] = '1.26.11'
default['rvm']['user_rubies'] = [node['github_notification_proxy']['ruby_version']]
default['rvm']['user_default_ruby'] = node['github_notification_proxy']['ruby_version']
default['rvm']['user_autolibs'] = 'read-fail'
