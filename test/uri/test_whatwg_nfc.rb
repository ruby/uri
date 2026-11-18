# frozen_string_literal: false
require 'test/unit'
require 'uri'

# Unicode Normalization Form C (UAX #15) with the Unicode data of
# URI::WHATWG_Parser::IDNA.
class URI::TestWHATWGNFC < Test::Unit::TestCase
  NFC = URI::WHATWG_Parser::NFC

  def assert_nfc(expected, input)
    assert_equal(expected, NFC.normalize(input), "NFC(#{input.dump})")
  end

  def test_ascii_and_empty
    assert_nfc("", "")
    assert_nfc("example.com", "example.com")
  end

  def test_already_composed
    assert_nfc("\u{E9}", "\u{E9}")
    assert_nfc("\u{1EBE}", "\u{1EBE}")
    assert_nfc("\u{65E5}\u{672C}", "\u{65E5}\u{672C}")
  end

  def test_composes
    assert_nfc("\u{E9}", "e\u{301}")
    assert_nfc("\u{C5}", "A\u{30A}")
    assert_nfc("\u{1EBE}", "\u{CA}\u{301}")
  end

  def test_decomposes_singletons
    assert_nfc("\u{C5}", "\u{212B}")
    assert_nfc("\u{3A9}", "\u{2126}")
    assert_nfc("\u{8C48}", "\u{F900}")
  end

  def test_composition_exclusions_stay_decomposed
    assert_nfc("\u{915}\u{93C}", "\u{958}")
    assert_nfc("\u{915}\u{93C}", "\u{915}\u{93C}")
  end

  def test_non_starter_decomposition
    assert_nfc("\u{308}\u{301}", "\u{344}")
  end

  def test_canonical_ordering
    assert_nfc("\u{1EA1}\u{301}", "a\u{301}\u{323}")
    assert_nfc("\u{1E0D}\u{307}", "\u{1E0B}\u{323}")
  end

  def test_composes_across_a_mark_of_another_class
    assert_nfc("\u{1EAD}", "a\u{323}\u{302}")
  end

  def test_blocked_by_a_mark_of_the_same_class
    assert_nfc("\u{E4}\u{308}", "a\u{308}\u{308}")
    assert_nfc("\u{E9}\u{301}", "e\u{301}\u{301}")
  end

  def test_blocked_by_a_starter
    assert_nfc("\u{1100}\u{301}\u{1161}", "\u{1100}\u{301}\u{1161}")
  end

  def test_leading_combining_mark
    assert_nfc("\u{301}e", "\u{301}e")
  end

  def test_hangul_composes
    assert_nfc("\u{AC00}", "\u{1100}\u{1161}")
    assert_nfc("\u{AC01}", "\u{1100}\u{1161}\u{11A8}")
    assert_nfc("\u{AC01}", "\u{AC00}\u{11A8}")
    assert_nfc("\u{D7A3}", "\u{1112}\u{1175}\u{11C2}")
  end

  def test_hangul_syllables_stay_composed
    assert_nfc("\u{AC01}", "\u{AC01}")
    assert_nfc("\u{D7A3}", "\u{D7A3}")
  end

  def test_hangul_boundaries
    # U+11A7 is just below the trailing consonants (U+11A8..U+11C2).
    assert_nfc("\u{AC00}\u{11A7}", "\u{AC00}\u{11A7}")
    # U+11C3 is just above them.
    assert_nfc("\u{AC00}\u{11C3}", "\u{AC00}\u{11C3}")
    # An LVT syllable takes no further trailing consonant.
    assert_nfc("\u{AC01}\u{11A8}", "\u{AC01}\u{11A8}")
    # U+1113 is just above the leading consonants (U+1100..U+1112).
    assert_nfc("\u{1113}\u{1161}", "\u{1113}\u{1161}")
    # U+1176 is just above the vowels (U+1161..U+1175).
    assert_nfc("\u{1100}\u{1176}", "\u{1100}\u{1176}")
  end

  def test_supplementary_planes
    # U+1D15E MUSICAL SYMBOL HALF NOTE is excluded from composition.
    assert_nfc("\u{1D157}\u{1D165}", "\u{1D15E}")
    assert_nfc("\u{1F600}", "\u{1F600}")
  end

  def test_input_is_not_modified
    input = "e\u{301}"
    NFC.normalize(input)
    assert_equal("e\u{301}", input)
  end

  def test_result_is_utf8
    assert_equal(Encoding::UTF_8, NFC.normalize("e\u{301}").encoding)
    assert_equal(Encoding::UTF_8, NFC.normalize("a").encoding)
  end

  def test_normalized
    assert_true(NFC.normalized?(""))
    assert_true(NFC.normalized?("\u{E9}"))
    assert_false(NFC.normalized?("e\u{301}"))
    assert_false(NFC.normalized?("\u{212B}"))
    assert_false(NFC.normalized?("a\u{301}\u{323}"))
    assert_true(NFC.normalized?("\u{1EA1}\u{301}"))
  end

  def test_works_in_a_ractor
    omit "Ractor is not available" unless defined?(Ractor)
    assert_separately(%w[-W0], <<~'RUBY')
      require "uri"
      r = Ractor.new { URI::WHATWG_Parser::NFC.normalize("e\u{301}") }
      assert_equal("\u{E9}", r.respond_to?(:value) ? r.value : r.take)
    RUBY
  end

  def test_normalize_in_linear_time
    marks = ->(n) { "a" + "\u{301}\u{323}" * n }
    assert_linear_performance([300, 1_000, 3_000, 10_000], pre: marks) do |input|
      NFC.normalize(input)
    end
    hangul = ->(n) { "\u{1100}\u{1161}\u{11A8}" * n }
    assert_linear_performance([300, 1_000, 3_000, 10_000], pre: hangul) do |input|
      NFC.normalize(input)
    end
  end
end
