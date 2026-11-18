require "rake/testtask"

namespace :test do
  Rake::TestTask.new(:wpt) do |t|
    t.description = "Run WPT urltestdata.json and Unicode IdnaTestV2.txt against URI::WHATWG_PARSER (needs network unless WPT_URLTESTDATA and IDNA_TEST_V2 are local files)"
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
