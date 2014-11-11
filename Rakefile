require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new

require 'yard'
YARD::Rake::YardocTask.new
task :doc => [:yard]

task :default => [:clean, :spec, :yard]

desc 'Remove any temporary artifacts'
task :clean do
  rm_f 'rspec.xml'
  rm_rf 'coverage'
  rm_rf 'doc'
end
