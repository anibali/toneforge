require 'rubygems'
require 'rake'
require 'rake/rdoctask'

task :run do
  load 'bin/toneforge'
end

Rake::RDocTask.new do |t|
  t.main = "README.rdoc"
  t.rdoc_files.include("README.rdoc", "lib/**/*.rb")
  t.rdoc_dir = "doc"
end

