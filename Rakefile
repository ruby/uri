require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test/lib"
  t.ruby_opts << "-rhelper"
  # The WPT and Unicode data tests need the network and run in rake
  # test:wpt; the tests of their harness do not.
  t.test_files = FileList["test/**/test_*.rb"].exclude(%r{\Atest/wpt/(?!test_\w+_harness\.rb\z)})
end

require "rdoc/task"
RDoc::Task.new do |doc|
  doc.main   = "README.md"
  doc.title  = "URI - handle Uniform Resource Identifiers"
  doc.rdoc_files = FileList.new %w[lib README.md BSDL COPYING]
  doc.rdoc_dir = "_site" # for github pages
end

task :default => :test
