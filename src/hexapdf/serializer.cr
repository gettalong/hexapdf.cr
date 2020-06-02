require "./pdf_object"

module HexaPDF
  class Serializer
    def self.serialize(obj : PDFObject)
      String.build do |str|
        serialize(obj, str)
      end
    end

    def self.serialize(obj : PDFObject, io : IO)
      new(io).serialize(obj)
    end

    # Creates a new serializer.
    def initialize(@io : IO)
    end

    def serialize(obj : Nil)
      @io << "null"
    end

    def serialize(obj : Bool)
      @io << obj
    end

    def serialize(obj : Int)
      @io << obj
    end

    def serialize(obj : Float)
      if obj.finite?
        if obj.abs < 0.0001 && obj != 0
          @io << sprintf("%.6f", obj)
        else
          @io << obj.round(6)
        end
      else
        raise "Can't serialize float values NaN or (+|-)Inf"
      end
    end

    def serialize(obj : Name)
      string_as_name(obj.value)
    end

    private def string_as_name(str)
      @io << "/"
      str.each_byte do |byte|
        case byte
        when 63..90, 94..122, 33, 34, 36, 38, 39, 42..46, 48..59, 61, 63, 92, 124, 126
          @io.write_byte(byte)
        else
          @io << "#"
          temp = byte.to_s(16)
          if temp.bytesize == 1
            @io << "0"
          end
          @io << temp
        end
      end
    end

    def serialize(obj : String)
      if obj =~ /[^ -~\t\r\n]/
        encoded = obj.encode("UTF16BE")
        bytes = Bytes.new(2 + encoded.size)
        bytes[0_u8] = 254_u8
        bytes[1_u8] = 255_u8
        (bytes + 2).copy_from(encoded)
        serialize(bytes)
      else
        serialize(obj.to_slice)
      end
    end

    def serialize(obj : Bytes)
      @io << "("
      obj.each do |byte|
        case byte
        when '('.ord
          @io << "\\("
        when ')'.ord
          @io << "\\)"
        when '\\'.ord
          @io << "\\\\"
        when '\r'.ord
          @io << "\\r"
        else
          @io.write_byte(byte)
        end
      end
      @io << ")"
    end
  end
end

class Object
  def to_pdf
    HexaPDF::Serializer.serialize(self)
  end

  def to_pdf(io : IO)
    HexaPDF::Serializer.serialize(self, io)
  end
end
