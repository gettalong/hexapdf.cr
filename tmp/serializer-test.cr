require "./hexapdf/*"

str = "This is a test string"
strb = str.to_slice
strd = str + "ö"
name = HexaPDF::Name["Type"]

io = if ARGV.size > 0
       STDOUT
     else
       String::Builder.new
     end

s = HexaPDF::Serializer.new(io)
100_000.times do
  s.serialize(nil)
  s.serialize(true)
  s.serialize(false)
  s.serialize(3424)
  s.serialize(342.34295693)
  s.serialize(name)
  s.serialize(str)
  s.serialize(strb)
  s.serialize(strd)
end
