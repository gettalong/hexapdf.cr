require "hexapdf"

tok = HexaPDF::Tokenizer.new(File.open(ARGV[0]))
i = 0
while true
  obj = tok.next_object(allow_keyword: true)
  break if obj == HexaPDF::Tokenizer::NO_MORE_TOKENS
  #puts obj
  i += 1
end
puts i
