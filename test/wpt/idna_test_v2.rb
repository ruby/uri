# frozen_string_literal: true
require 'uri'
require 'rbconfig'
require_relative 'wpt_url_test_data'

# Harness for running Unicode's IdnaTestV2.txt, the conformance test of
# UTS #46, against URI::WHATWG_Parser::IDNA.to_ascii.
#
# Each case is a Hash of :source, :to_ascii (the toAsciiN column: ToASCII
# with Nontransitional Processing), :status (the status codes of
# toAsciiN) and :line. :source and :to_ascii are nil when the column
# holds a surrogate, which a UTF-8 String cannot.
module IDNATestV2
  # Status codes of the checks that domain to ASCII turns off:
  # CheckHyphens (V2, V3), UseSTD3ASCIIRules (U1) and VerifyDnsLength
  # (A4_1, A4_2, and X4_2, which IdnaTestV2.txt reports for an empty
  # label).
  IGNORED_STATUSES = %w[V2 V3 U1 A4_1 A4_2 X4_2].freeze

  # The ReadMe of the latest version of the Unicode Character Database.
  LATEST_README = "https://www.unicode.org/Public/UCD/latest/ReadMe.txt"

  ESCAPE = /\\u(\h{4})|\\x\{(\h+)\}/
  SURROGATES = (0xD800..0xDFFF).freeze
  UNKNOWN_TO_RUBY = /(?!\p{Noncharacter_Code_Point})\p{Cn}/

  module_function

  def unicode_version
    URI::WHATWG_Parser::IDNA.load_data
    URI::WHATWG_Parser::IDNA::UNICODE_VERSION
  end

  # IdnaTestV2.txt of the Unicode version of URI::WHATWG_Parser's data.
  def default_source
    "https://www.unicode.org/Public/#{unicode_version}/idna/IdnaTestV2.txt"
  end

  # IDNA_TEST_V2 (a local path or an https URL) if set, otherwise
  # default_source.
  def source
    ENV["IDNA_TEST_V2"] || default_source
  end

  # The Unicode version that +readme+ (LATEST_README) is for.
  def latest_unicode_version(readme)
    readme[/data files and charts for version (\d+\.\d+\.\d+)/, 1] or
      raise "no Unicode version in #{LATEST_README}"
  end

  def newer?(version, other)
    Gem::Version.new(version) > Gem::Version.new(other)
  end

  def load(source)
    text = source.match?(%r{\A[A-Za-z][A-Za-z0-9+.-]*://}) ? WPT::URLTestData.fetch(source) : File.read(source)
    parse(text.dup.force_encoding(Encoding::UTF_8))
  end

  def parse(text)
    cases = []
    text.each_line.with_index(1) do |line, number|
      line = line.sub(/#.*/, "").strip
      next if line.empty?

      columns = line.split(";", -1).map(&:strip)
      source = value(columns[0])
      to_unicode = columns[1].empty? ? source : value(columns[1])
      to_unicode_status = statuses(columns[2])
      to_ascii = columns[3].empty? ? to_unicode : value(columns[3])
      status = columns[4].empty? ? to_unicode_status : statuses(columns[4])
      cases << { source: source, to_ascii: to_ascii, status: status, line: number }
    end
    cases
  end

  def value(column)
    column == '""' ? "" : unescape(column)
  end

  def statuses(column)
    column.delete("[]").split(",").map(&:strip)
  end

  # Replaces \uXXXX and \x{X...} escapes. Returns nil if one of them is a
  # surrogate.
  def unescape(str)
    code_points = []
    result = str.gsub(ESCAPE) do
      code_point = ($1 || $2).hex
      code_points << code_point
      SURROGATES.cover?(code_point) ? "" : code_point.chr(Encoding::UTF_8)
    end
    code_points.any? { |c| SURROGATES.cover?(c) } ? nil : result
  end

  # {failure: true}, {value: expected ASCII}, or nil when the case cannot
  # be checked: it holds a surrogate, it has only ignored errors and the
  # file gives no ASCII result for it, or it succeeds with a code point
  # that the running Ruby, whose Unicode data IDNA uses, does not know.
  def expectation(test_case)
    return nil if test_case[:source].nil? || test_case[:to_ascii].nil?
    return { failure: true } unless (test_case[:status] - IGNORED_STATUSES).empty?
    return nil unless test_case[:to_ascii].ascii_only?
    return nil if unknown_to_ruby?(test_case)
    { value: test_case[:to_ascii] }
  end

  # Whether +test_case+ holds a code point that is unassigned in the
  # Unicode version of the running Ruby, in its source or in its ASCII
  # result decoded. Noncharacters are unassigned in every version.
  def unknown_to_ruby?(test_case)
    [test_case[:source], test_case[:to_ascii]].compact.any? do |domain|
      domain.split(".", -1).any? do |label|
        decoded = URI::WHATWG_Parser::Punycode.decode(label[4..-1]) if label.start_with?("xn--") && label.ascii_only?
        [label, decoded].compact.any? { |s| s.match?(UNKNOWN_TO_RUBY) }
      end
    end
  end

  # Runs +test_case+ with +to_ascii+, a callable that returns the ASCII
  # domain or nil on failure. Returns nil when it passes, or a message.
  def run(test_case, to_ascii)
    expected = expectation(test_case)
    return nil unless expected

    begin
      actual = to_ascii.call(test_case[:source])
    rescue StandardError => e
      return "#{e.class}: #{e.message}"
    end

    if expected[:failure]
      actual.nil? ? nil : "expected failure (#{test_case[:status].join(", ")}), got #{actual.inspect}"
    elsif actual.nil?
      "unexpected failure, expected #{expected[:value].inspect}"
    elsif actual != expected[:value]
      "expected #{expected[:value].inspect}, got #{actual.inspect}"
    end
  end
end
