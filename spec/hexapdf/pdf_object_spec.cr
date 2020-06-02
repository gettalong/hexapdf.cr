require "../spec_helper"

describe HexaPDF::Name do
  it "can be used together with strings as hash keys" do
    hash = {} of (HexaPDF::Name | String) => HexaPDF::PDFObject
    hash[HexaPDF::Name["name"]] = "name"
    hash["string"] = "string"

    hash[HexaPDF::Name["name"]].should eq("name")
    hash[HexaPDF::Name["string"]].should eq("string")
    hash["name"].should eq("name")
    hash["string"].should eq("string")
  end
end
