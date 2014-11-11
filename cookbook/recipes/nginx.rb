#
# Cookbook Name:: github_notification_proxy
# Recipe:: nginx
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


node.default['nginx']['default_site_enabled'] = false

include_recipe 'nginx::repo'
include_recipe 'nginx'

if node['github_notification_proxy']['http']['ssl']['enabled']
  ssl_data_bag = GithubNotificationProxy::Helpers.load_data_bag(
    node['github_notification_proxy']['http']['ssl']['cert_databag'],
    node['github_notification_proxy']['http']['ssl']['cert_databag_item']
  )

  # Public key.
  file "/etc/ssl/certs/#{node['github_notification_proxy']['http']['host_name']}.crt" do
    mode 0644
    user 'root'
    group 'root'
    content "#{ssl_data_bag['cert']}"
    notifies :reload, 'service[nginx]', :delayed
  end

  # Private key.
  file "/etc/ssl/private/#{node['github_notification_proxy']['http']['host_name']}.key" do
    mode 0600
    user 'root'
    group 'root'
    content "#{ssl_data_bag['key']}"
    notifies :reload, 'service[nginx]', :delayed
  end
end

template ::File.join(node['nginx']['dir'], 'sites-available', 'github_notification_proxy') do
  source 'nginx-github-notification-proxy.conf.erb'
  notifies :reload, 'service[nginx]', :delayed
  mode 0644
  owner 'root'
  group 'root'
  action :create
  variables(
    :host_name          => node['github_notification_proxy']['http']['host_name'],
    :host_aliases       => node['github_notification_proxy']['http']['host_aliases'] || [],
    :ssl_enabled        => node['github_notification_proxy']['http']['ssl']['enabled'],
    :ssl_strict         => node['github_notification_proxy']['http']['ssl']['strict'],
    :redirect_http      => node['github_notification_proxy']['http']['ssl']['enabled'],
    :listen_port        => node['github_notification_proxy']['http']['port'],
    :ssl_listen_port    => node['github_notification_proxy']['http']['ssl']['port'],
    :install_dir        => node['github_notification_proxy']['server']['install_dir'],
    :restrict_ips       => node['github_notification_proxy']['http']['restrict_ips']
  )
end

nginx_site 'github_notification_proxy'
