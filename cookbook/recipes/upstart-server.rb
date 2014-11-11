#
# Cookbook Name:: github_notification_proxy
# Recipe:: upstart-server
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

template "/etc/init/github-notification-proxy-server.conf" do
  source 'upstart-github-notification-proxy-server.conf.erb'
  mode 0644
  owner 'root'
  group 'root'
  action :create
  variables(
    :home_path => "/home/#{node['github_notification_proxy']['user']}",
    :rvm_path => "/home/#{node['github_notification_proxy']['user']}/.rvm"
  )
  notifies :restart, 'service[github-notification-proxy-server]', :delayed
end

service 'github-notification-proxy-server' do
  provider Chef::Provider::Service::Upstart
  supports :status => true, :restart => true, :reload => true
  action :start
  subscribes :reload, 'execute[github-notification-proxy-alias]', :delayed
end
