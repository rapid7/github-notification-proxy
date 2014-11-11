#
# Cookbook Name:: github_notification_proxy
# Recipe:: client
#
# Copyright (C) 2014 Rapid7, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


#
# Install Directory
#

install_dir = node['github_notification_proxy']['client']['install_dir']
ruby_string = "#{node['github_notification_proxy']['ruby_version']}@#{node['github_notification_proxy']['ruby_gemset']}"

directory File.dirname(install_dir) do
  recursive true
end

directory install_dir do
  mode 0755
  owner node['github_notification_proxy']['user']
  group node['github_notification_proxy']['group']
end

#
# Source code
#

git 'github-notification-proxy-client' do
  destination install_dir
  user node['github_notification_proxy']['user']
  group node['github_notification_proxy']['group']
  repository node['github_notification_proxy']['repo']['url']
  revision node['github_notification_proxy']['repo']['revision']
  ssh_wrapper "/home/#{node['github_notification_proxy']['user']}/.ssh/github_notification_proxy_ssh_wrapper.sh"
  action :sync
  # Notify configuration files immediately so they are available before
  # running other steps
  notifies :create, 'template[github-notification-proxy-client-configyml]', :immediately
  notifies :reload, 'service[github-notification-proxy-client]', :delayed
end

#
# Configuration files
#

template 'github-notification-proxy-client-configyml' do
  path ::File.join(install_dir, 'config', 'config.yml')
  mode 0644
  owner node['github_notification_proxy']['user']
  group node['github_notification_proxy']['group']
  source 'config.yml.erb'
  variables(
    :handlers => node['github_notification_proxy']['handlers']
  )
  notifies :reload, 'service[github-notification-proxy-client]', :delayed
  only_if { ::File.directory?(::File.join(install_dir, 'config')) }
end

#
# Install gems
#

rvm_shell 'github-notification-proxy-client-gems' do
  ruby_string ruby_string
  user node['github_notification_proxy']['user']
  group node['github_notification_proxy']['group']
  cwd install_dir
  code %{bundle install}
  action :nothing
  subscribes :run, 'git[github-notification-proxy-client]', :immediately
  subscribes :run, 'execute[github-notification-proxy-alias]', :immediately
  notifies :reload, 'service[github-notification-proxy-client]', :delayed
end

# Upstart services
include_recipe 'github_notification_proxy::upstart-client'
