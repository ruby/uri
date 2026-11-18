# frozen_string_literal: true
require 'uri'
require_relative 'idna_test_v2'

# Harness for running Unicode's NormalizationTest.txt against
# URI::WHATWG_Parser::NFC.normalize.
#
# Each case is a Hash of :columns (c1..c5), :line and :part. For NFC, the
# file requires c2 == NFC(c1) == NFC(c2) == NFC(c3) and
# c4 == NFC(c4) == NFC(c5). Every code point that Part 1 does not list
# is unchanged by NFC.
module NormalizationTest
  module_function

  # NormalizationTest.txt of the Unicode version of URI::WHATWG_Parser's
  # data.
  def default_source
    "https://www.unicode.org/Public/#{IDNATestV2.unicode_version}/ucd/NormalizationTest.txt"
  end

  # NORMALIZATION_TEST (a local path or an https URL) if set, otherwise
  # default_source.
  def source
    ENV["NORMALIZATION_TEST"] || default_source
  end

  def load(source)
    text = source.match?(%r{\A[A-Za-z][A-Za-z0-9+.-]*://}) ? WPT::URLTestData.fetch(source) : File.read(source)
    parse(text.dup.force_encoding(Encoding::UTF_8))
  end

  def parse(text)
    part = nil
    cases = []
    text.each_line.with_index(1) do |line, number|
      line = line.sub(/#.*/, "").strip
      next if line.empty?
      if line.start_with?("@")
        part = line[1..-1].strip
        next
      end
      columns = line.split(";").first(5).map { |column| column.split.map(&:hex).pack("U*") }
      cases << { columns: columns, line: number, part: part }
    end
    cases
  end

  def part1_code_points(cases)
    cases.select { |c| c[:part] == "Part1" }.map { |c| c[:columns][0].ord }
  end

  # Runs +test_case+ with +nfc+, a callable. Returns nil when it passes,
  # or a message.
  def run(test_case, nfc)
    c = test_case[:columns]
    checks = [[0, 1], [1, 1], [2, 1], [3, 3], [4, 3]]
    failures = checks.filter_map do |source, expected|
      actual = nfc.call(c[source])
      next if actual == c[expected]
      "NFC(c#{source + 1}) = #{dump(actual)}, expected c#{expected + 1} = #{dump(c[expected])}"
    end
    failures.empty? ? nil : failures.join("\n")
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end

  def dump(str)
    str.codepoints.map { |cp| format("%04X", cp) }.join(" ")
  end
end
