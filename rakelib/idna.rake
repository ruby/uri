namespace :idna do
  desc "Generate lib/uri/whatwg_parser/idna_data.rb from Unicode data (UNICODE_VERSION=x.y.z, default: the version of the current data)"
  task :generate do
    require_relative "idna_data_generator"
    require "net/http"
    require "fileutils"

    data_path = "lib/uri/whatwg_parser/idna_data.rb"
    version = ENV["UNICODE_VERSION"] || File.read(data_path)[/UNICODE_VERSION = "([\d.]+)"/, 1]
    abort "set UNICODE_VERSION" unless version

    cache_dir = File.join("tmp", "unicode", version)
    FileUtils.mkdir_p(cache_dir)
    sources = IDNADataGenerator::FILES.to_h do |key, file|
      path = File.join(cache_dir, File.basename(file))
      unless File.exist?(path)
        url = IDNADataGenerator.url(version, file)
        puts "fetching #{url}"
        response = Net::HTTP.get_response(URI(url))
        abort "failed to fetch #{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        File.binwrite(path, response.body)
      end
      [key, File.read(path, encoding: "UTF-8")]
    end

    File.write(data_path, IDNADataGenerator.new(version, sources).generate)
    puts "wrote #{data_path} (Unicode #{version})"
  end
end
