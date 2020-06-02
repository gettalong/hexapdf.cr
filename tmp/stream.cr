require "../src/hexapdf/*"

tok = HexaPDF::Tokenizer.new(IO::Memory.new(File.read(ARGV[0])))
i = 0
while true
  obj = tok.next_object(allow_keyword: true)
  break if obj.is_a?(HexaPDF::Tokenizer::Token) && obj.type == :eof
  #puts obj
  i += 1
end
puts i
