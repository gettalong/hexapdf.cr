require "../spec_helper"

private def create_tokenizer(str)
  HexaPDF::Tokenizer.new(IO::Memory.new(str))
end

describe HexaPDF::Tokenizer do
  it "next_token: returns all available kinds of tokens on next_token" do
    tokenizer = create_tokenizer("
      % Regular tokens

      true false
      123 +17 -98 0 0059
      34.5 -3.62 +123.6 4. -.002 .002 0.0

      % Keywords
      obj endobj f* *f - +

      % Specials
      { }

      % Literal string tests
      (parenthese\\s ( ) and \\(\r
      special \\0053\\053\\53characters\r (*!&}^% and \\
      so \\\r
      on).\\n)
      ()

      % Hex strings
      <4E6F762073 686D6F7A20	6B612070
      6F702E>
      < 901FA3 ><901fA>

      % Names
      /Name1
      /ASomewhatLongerName
      /A;Name_With-Various***Characters?
      /1.2/$$
      /@pattern
      /.notdef
      /lime#20Green
      /paired#28#29parentheses
      /The_Key_of_F#23_Minor
      /A#42
      /

      % Arrays
      [ 5 6 /Name ]
      [5 6 /Name]

      % Dictionaries
      <</Name 5>>

      % Test".gsub(/^ {6}/m, ""))

    expected_tokens = [
      true, false,
      123, 17, -98, 0, 59,
      34.5, -3.62, 123.6, 4.0, -0.002, 0.002, 0.0,
      HexaPDF::Tokenizer::Token["obj"], HexaPDF::Tokenizer::Token["endobj"], HexaPDF::Tokenizer::Token["f*"],
      HexaPDF::Tokenizer::Token["*f"], HexaPDF::Tokenizer::Token["-"], HexaPDF::Tokenizer::Token["+"],
      HexaPDF::Tokenizer::Token.new(:"{"), HexaPDF::Tokenizer::Token.new(:"}"),
      "parentheses ( ) and (\nspecial \x053++characters\n (*!&}^% and so on).\n".to_slice, "".to_slice,
      "Nov shmoz ka pop.".to_slice, "\x90\x1F\xA3".to_slice, "\x90\x1F\xA0".to_slice,
      HexaPDF::Name["Name1"], HexaPDF::Name["ASomewhatLongerName"],
      HexaPDF::Name["A;Name_With-Various***Characters?"],
      HexaPDF::Name["1.2"], HexaPDF::Name["$$"], HexaPDF::Name["@pattern"],
      HexaPDF::Name[".notdef"], HexaPDF::Name["lime Green"], HexaPDF::Name["paired()parentheses"],
      HexaPDF::Name["The_Key_of_F#_Minor"], HexaPDF::Name["AB"], HexaPDF::Name[""],
      HexaPDF::Tokenizer::Token.new(:array_start), 5, 6, HexaPDF::Name["Name"], HexaPDF::Tokenizer::Token.new(:array_end),
      HexaPDF::Tokenizer::Token.new(:array_start), 5, 6, HexaPDF::Name["Name"], HexaPDF::Tokenizer::Token.new(:array_end),
      HexaPDF::Tokenizer::Token.new(:dict_start), HexaPDF::Name["Name"], 5, HexaPDF::Tokenizer::Token.new(:dict_end),
    ]

    while expected_tokens.size > 0
      expected_token = expected_tokens.shift
      token = tokenizer.next_token
      token.should eq(expected_token)
    end
    expected_tokens.size.should eq(0)
    token = tokenizer.next_token
    token.should be_a(HexaPDF::Tokenizer::Token)
    token.as(HexaPDF::Tokenizer::Token).type.should eq(:eof)
  end

  it "next_token: fails on a greater than sign that is not part of a hex string" do
    tokenizer = create_tokenizer(" >")
    expect_raises(HexaPDF::MalformedPDFException) { tokenizer.next_token }
  end

  it "next_token: fails on a missing greater than sign in a hex string" do
    tokenizer = create_tokenizer("<ABCD")
    expect_raises(HexaPDF::MalformedPDFException) { tokenizer.next_token }
  end

  it "next_token: fails on unbalanced parentheses in a literal string" do
    tokenizer = create_tokenizer("(href(test)")
    expect_raises(HexaPDF::MalformedPDFException) { tokenizer.next_token }
  end

  it "next_object: works for all PDF object types, including array and dictionary" do
    tokenizer = create_tokenizer("true false null 123 34.5 (string) <4E6F76> /Name [5 6 /Name] <</Name 5>>")
    tokenizer.next_object.should be_true
    tokenizer.next_object.should be_false
    tokenizer.next_object.should be_nil
    tokenizer.next_object.should eq(123)
    tokenizer.next_object.should eq(34.5)
    tokenizer.next_object.should eq("string".to_slice)
    tokenizer.next_object.should eq("Nov".to_slice)
    tokenizer.next_object.should eq(HexaPDF::Name["Name"])
    tokenizer.next_object.should eq([5, 6, HexaPDF::Name["Name"]])
    tokenizer.next_object.should eq({HexaPDF::Name["Name"] => 5})
  end

  it "next_object: allows keywords if the corresponding option is set" do
    tokenizer = create_tokenizer("name")
    obj = tokenizer.next_object(allow_keyword: true)
    obj.should be_a(HexaPDF::Tokenizer::Token)
    obj.as(HexaPDF::Tokenizer::Token).value.should eq("name")
  end

  it "next_object: fails if the value is not a correct object" do
    tokenizer = create_tokenizer("<< /name ] >>")
    expect_raises(HexaPDF::MalformedPDFException) { tokenizer.next_object }
    tokenizer = create_tokenizer("other")
    expect_raises(HexaPDF::MalformedPDFException) { tokenizer.next_object }
    tokenizer = create_tokenizer("<< (string) (key) >>")
    expect_raises(HexaPDF::MalformedPDFException) { tokenizer.next_object }
    tokenizer = create_tokenizer("<< /NoValueForKey >>")
    expect_raises(HexaPDF::MalformedPDFException) { tokenizer.next_object }
  end

  it "returns the correct position on operations" do
    tokenizer = create_tokenizer("hallo du")
    tokenizer.next_token
    tokenizer.pos.should eq(5)

    tokenizer.skip_whitespace
    tokenizer.pos.should eq(6)

    tokenizer.next_byte
    tokenizer.pos.should eq(7)

    tokenizer.peek_token
    tokenizer.pos.should eq(7)
  end

  it "returns the next byte" do
    tokenizer = create_tokenizer("hallo")
    tokenizer.next_byte.should eq('h'.ord)
    tokenizer.next_byte.should eq('a'.ord)
  end

  it "returns the next token but doesn't advance the position on peek_token" do
    tokenizer = create_tokenizer("hallo du")
    2.times do
      tokenizer.peek_token.as(HexaPDF::Tokenizer::Token).value.should eq("hallo")
      tokenizer.pos.should eq(0)
    end
  end
end
