require "rake/testtask"

namespace :test do
  Rake::TestTask.new(:wpt) do |t|
    t.description = "Run web-platform-tests urltestdata.json against URI::WHATWG_PARSER (needs network unless WPT_URLTESTDATA is a local file)"
    t.libs << "lib"
    t.test_files = FileList["test/wpt/test_*.rb"]
  end

  namespace :wpt do
    desc "Regenerate test/wpt/urltestdata_exclusions.json from the currently failing cases"
    task :update_exclusions do
      ruby "-Ilib", "test/wpt/update_exclusions.rb"
    end
  end
end
