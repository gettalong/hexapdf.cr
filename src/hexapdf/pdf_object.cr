require "string_pool"

module HexaPDF
  # Represents a PDF name object.
  #
  # See: PDF1.7 s7.3.5
  class Name
    @@pool = StringPool.new

    getter value : String

    def self.pooled_string(str)
      @@pool.get(str)
    end

    def self.[](str)
      new(str)
    end

    def initialize(str)
      @value = @@pool.get(str)
    end

    def ==(other : self)
      value == other.value
    end

    def ==(other : String)
      value == other
    end

    def hash
      value.hash
    end

    def to_s
      value
    end

    def to_s(io)
      io << value
    end
  end

  # The union of all types that are valid PDF object types.
  #
  # See: PDF1.7 s7.3
  alias PDFObject = Nil | Bool | Int8 | Int16 | Int32 | Int64 | UInt8 | UInt16 | UInt32 | UInt64 | Float32 | Float64 |
                    String | Bytes | Time | Name | Array(PDFObject) | Hash((Name | String), PDFObject)
end

class String
  def ==(other : HexaPDF::Name)
    self == other.value
  end
end
