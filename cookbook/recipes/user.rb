#
# Cookbook Name:: github_notification_proxy
# Recipe:: user
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

group node['github_notification_proxy']['group']

user node['github_notification_proxy']['user'] do
  gid node['github_notification_proxy']['group']
  shell '/bin/bash'
  home "/home/#{node['github_notification_proxy']['user']}"
  supports :manage_home => true
end
