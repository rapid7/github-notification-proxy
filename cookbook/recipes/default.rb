#
# Cookbook Name:: github_notification_proxy
# Recipe:: default
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

include_recipe 'apt'

package 'git'

# These packages are needed to compile the datamapper gem
package 'libpq-dev'
package 'postgresql-server-dev-9.3'

include_recipe 'github_notification_proxy::user'
include_recipe 'github_notification_proxy::ssh'
include_recipe 'github_notification_proxy::ruby'

if node['github_notification_proxy']['install_type']
  include_recipe "github_notification_proxy::#{node['github_notification_proxy']['install_type']}"
end
