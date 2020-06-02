require "../src/hexapdf/**"
require "openssl/cipher"

file = File.open(ARGV[0])
buffer = Bytes.new(file.size)
file.read(buffer)
#buf = HexaPDF::Encryption::ARC4.new(("a"*32).to_slice).process(buffer)

cipher = OpenSSL::Cipher.new("RC4")
cipher.key = "a"*32
buf = cipher.update(buffer)

STDOUT.write(buf)
