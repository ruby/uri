# frozen_string_literal: false
require 'test/unit'
require 'uri'

class URI::TestWHATWGPunycode < Test::Unit::TestCase
  Punycode = URI::WHATWG_Parser::Punycode

  # [Unicode, Punycode]
  ROUND_TRIPS = [
    ["", ""],
    ["a", "a-"],
    ["abc", "abc-"],
    ["-> $1.00 <-", "-> $1.00 <--"],
    ["ü", "tda"],
    ["bücher", "bcher-kva"],
    ["faß", "fa-hia"],
    ["☕", "53h"],
    ["日本語", "wgv71a119e"],
    ["ハロー・ワールド", "gdkl8fhk5egc"],
    ["3年B組金八先生", "3B-ww4c5e180e575a65lsy2b"],
    # RFC 3492 7.1 (A) Arabic (Egyptian)
    ["ليهمابتكلموشعربي؟",
     "egbpdaj6bu4bxfgehfvwxn"],
    # RFC 3492 7.1 (B) Chinese (simplified)
    ["他们为什么不说中文", "ihqwcrb4cv8a8dqg056pqjye"],
    ["é-", "--9fa"],
    ["-é", "--bga"],
    # boundaries of the code space
    ["\u0080", "a"],
    ["\u007F\u0080", "\u007F-ba"],
    ["\u{1F600}", "e28h"],
    ["\u{10FFFF}", "dn32g"],
    ["\u{E000}", "0y0c"],
  ]

  ROUND_TRIPS.each_with_index do |(unicode, punycode), i|
    define_method("test_encode_#{i}") do
      assert_equal(punycode, Punycode.encode(unicode))
    end

    define_method("test_decode_#{i}") do
      assert_equal(unicode, Punycode.decode(punycode))
    end
  end

  def test_encode_returns_ascii
    assert_predicate(Punycode.encode("日本語"), :ascii_only?)
  end

  def test_decode_returns_utf8
    assert_equal(Encoding::UTF_8, Punycode.decode("tda").encoding)
    assert_equal(Encoding::UTF_8, Punycode.decode("a-").encoding)
  end

  def test_decode_digits_are_case_insensitive
    assert_equal("bücher", Punycode.decode("bcher-KVA"))
  end

  def test_decode_keeps_the_case_of_basic_code_points
    assert_equal("BüCHER", Punycode.decode("BCHER-KVA"))
  end

  def test_decode_lone_delimiter
    assert_equal("", Punycode.decode("-"))
  end

  def test_decode_splits_at_the_last_delimiter
    assert_equal("a-b", Punycode.decode("a-b-"))
  end

  def test_decode_rejects_non_ascii
    assert_nil(Punycode.decode("ü"))
    assert_nil(Punycode.decode("ü-tda"))
  end

  def test_decode_rejects_invalid_digits
    assert_nil(Punycode.decode("a-!"))
    assert_nil(Punycode.decode("a-_"))
    assert_nil(Punycode.decode("a- "))
  end

  def test_decode_rejects_truncated_input
    # "9" is a digit that does not end the variable-length integer.
    assert_nil(Punycode.decode("a-9"))
    assert_nil(Punycode.decode("z" * 50))
  end

  def test_decode_rejects_code_points_beyond_unicode
    assert_nil(Punycode.decode("en32g")) # U+110000
  end

  def test_decode_rejects_surrogates
    assert_nil(Punycode.decode("ib9b")) # U+D800
    assert_nil(Punycode.decode("zy0c")) # U+DFFF
  end

  def test_decode_rejects_overflow
    assert_nil(Punycode.decode("9" * 10 + "a"))
    assert_nil(Punycode.decode("a-" + "9" * 10 + "a"))
  end

  def test_decode_of_a_non_string
    assert_raise(NoMethodError, TypeError) { Punycode.decode(nil) }
  end
end
