require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test/lib"
  t.ruby_opts << "-rhelper"
  t.test_files = FileList["test/**/test_*.rb"]
end

require "rdoc/task"
RDoc::Task.new do |doc|
  doc.main   = "README.md"
  doc.title  = "URI - handle Uniform Resource Identifiers"
  doc.rdoc_files = FileList.new %w[lib README.md LICENSE.txt]
  doc.rdoc_dir = "_site" # for github pages
end

task :sync_tool do
  require 'fileutils'
  FileUtils.cp "../ruby/tool/lib/test/unit/core_assertions.rb", "./test/lib"
  FileUtils.cp "../ruby/tool/lib/envutil.rb", "./test/lib"
  FileUtils.cp "../ruby/tool/lib/find_executable.rb", "./test/lib"
end

task :default => :test
