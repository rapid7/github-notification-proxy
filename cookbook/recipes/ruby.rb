#
# Cookbook Name:: github_notification_proxy
# Recipe:: ruby
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

# gawk is needed to install ruby 2.1.x but is not installed by RVM
package 'gawk'

node.default['rvm']['user_installs'] = [{
  user: node['github_notification_proxy']['user'],
  home: "/home/#{node['github_notification_proxy']['user']}",
  upgrade: node['rvm']['version']
}]
include_recipe 'rvm::user'

rvm_gemset node['github_notification_proxy']['ruby_gemset'] do
  user node['github_notification_proxy']['user']
  ruby_string node['github_notification_proxy']['ruby_version']
end

# Create an alias that remains consistent across version/gemset changes
execute 'github-notification-proxy-alias' do
  rvm_cmd = "/home/#{node['github_notification_proxy']['user']}/.rvm/bin/rvm"
  rvm_alias = node['github_notification_proxy']['rvm_alias']
  ruby_string = "#{node['github_notification_proxy']['ruby_version']}@#{node['github_notification_proxy']['ruby_gemset']}"

  user node['github_notification_proxy']['user']
  group node['github_notification_proxy']['group']
  command "#{rvm_cmd} alias create #{rvm_alias} #{ruby_string}"
  not_if do
    cmd = Mixlib::ShellOut.new("#{rvm_cmd} alias show #{rvm_alias}")
    cmd.run_command
    !cmd.error? && (cmd.stdout.strip == ruby_string)
  end
end
