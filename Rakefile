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

task :default => :test
