require "../../spec_helper"

describe HexaPDF::Encryption::ARC4 do
  it "processes the test vectors from the ARC4 wikipedia page" do
    vectors = {
      {encrypted: "BBF316E8D940AF0AD3", plain: "Plaintext", key: "Key"},
      {encrypted: "1021BF0420", plain: "pedia", key: "Wiki"},
      {encrypted: "45A01F645FC35B383552544B9BF5", plain: "Attack at dawn", key: "Secret"}
    }
    vectors.each do |vector|
      decrypted = HexaPDF::Encryption::ARC4.decrypt(vector[:key].to_slice, vector[:encrypted].hexbytes)
      decrypted.should eq(vector[:plain].to_slice)
    end
  end
end
