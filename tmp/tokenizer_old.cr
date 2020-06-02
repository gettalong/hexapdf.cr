require "./pdf_object"

module HexaPDF
  # Tokenizes the content of an IO object following the PDF rules.
  #
  # See: PDF1.7 s7.2
  class Tokenizer
    class Token
      property type : Symbol
      property string_value : String

      def initialize
        @type = :EOF
        @string_value = ""
      end
    end

    # Creates a new tokenizer.
    def initialize(io : (IO::Memory | File))
      @token = Token.new
      @buffer = IO::Memory.new
      @io = io
    end

    # Returns the current position of the tokenizer inside in the IO object.
    def pos
      @io.pos
    end

    # Sets the position at which the next token should be read.
    def pos=(pos)
      @io.pos = pos
    end

    # Returns a single token read from the current position and advances the position.
    #
    # Comments and a run of whitespace characters are ignored. A Token of type +:NO_MORE_TOKENS+ is
    # returned if there are no more tokens available.
    def next_token
      skip_whitespace

      case (byte = @io.read_byte)
      when 43, 45, 46, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57 # + - . 0..9
        parse_number(byte.as(UInt8))
      when 47 # /
        parse_name
      when 40 # (
        parse_literal_string
      when 60 # <
        if peek_byte != 60
          parse_hex_string
        else
          @io.read_byte
          @token.type = :DICT_START
          @token
        end
      when 62 # >
        unless @io.read_byte == 62
          raise "error"
        end
        @token.type = :DICT_END
        @token
      when 91 # [
        @token.type = :ARRAY_START
        @token
      when 93 # ]
        @token.type = :ARRAY_END
        @token
      when 123 # {
        @token.type = :"{"
        @token
      when 125 # }
        @token.type = :"}"
        @token
      when 37 # %
        while true
          case @io.read_byte
          when 10, 13
            break
          when nil
            @token.type = :EOF
            @token
          end
        end
        next_token
      when nil # we reached the end of the file
        @token.type = :EOF
        @token
      else # everything else consisting of regular characters
        parse_keyword(byte)
      end
    end

    # Returns the PDF object at the current position. This is different from #next_token because
    # references, arrays and dictionaries consist of multiple tokens.
    #
    # If the +allow_end_array_token+ argument is +true+, the ']' token is permitted to facilitate
    # the use of this method during array parsing.
    #
    # See: PDF1.7 s7.3
    def next_object(allow_end_array_token = false, allow_keyword = false)
      token = next_token

      if token.is_a?(Token)
        case token.type
        when :DICT_START
          token = parse_dictionary
        when :ARRAY_START
          token = parse_array
        when :ARRAY_END
          unless allow_end_array_token
            raise "ERROR 1"
          end
        else
          unless allow_keyword
            raise "ERROR 2"
          end
        end
      end

      token
    end

    # Skips all whitespace at the current position.
    #
    # See: PDF1.7 s7.2.2
    def skip_whitespace
      while true
        case @io.read_byte
        when '\0'.ord, '\t'.ord, '\n'.ord, '\f'.ord, '\r'.ord, ' '.ord
        when nil
          break
        else
          @io.pos -= 1
          break
        end
      end
    end

    private def peek_byte
      byte = @io.read_byte
      @io.pos -= 1 if byte
      byte
    end

    private def parse_until_whitespace_or_delimiter(byte = nil)
      @buffer.clear
      @buffer.write_byte(byte) if byte

      while true
        case (byte = @io.read_byte)
        when 0, 9, 10, 12, 13, 32, 40, 41, 60, 62, 123, 125, 47, 91, 93, 37, nil
          @io.pos -= 1 if byte
          break
        else
          @buffer.write_byte(byte.as(UInt8))
        end
      end

      @buffer.to_s
    end

    # Parses the keyword at the current position.
    #
    # See: PDF1.7 s7.2
    private def parse_keyword(byte)
      str = parse_until_whitespace_or_delimiter(byte)
      case str
      when "true"
        true
      when "false"
        false
      when "null"
        nil
      else
        @token.type = :KEYWORD
        @token.string_value = str
        @token
      end
    end

    # Parses the number (integer or real) at the current position.
    #
    # See: PDF1.7 s7.3.3
    private def parse_number(byte)
      @buffer.clear

      integer = 0_i64
      negative = false
      digits = 0

      if byte == 45
        @buffer.write_byte(byte)
        negative = true
        byte = @io.read_byte
      end

      case byte
      when Nil
        @io.pos -= 1
        nil
      when 46
        consume_float(byte, negative, integer, digits)
      when 48
        @buffer.write_byte(byte.as(UInt8))
        byte = @io.read_byte
        case byte
        when Nil
          @io.pos -= 1
          0_i64
        when 46
          consume_float(byte, negative, integer, digits)
        when 101, 69
          consume_exponent(byte, negative, integer.to_f64, digits)
        when 48..57
          raise "error 1"
        else
          @io.pos -= 1
          0_i64
        end
      when 49..57
        digits = 1
        @buffer.write_byte(byte)
        integer = (byte - 48).to_i64
        byte = @io.read_byte
        while byte && 48 <= byte <= 57
          @buffer.write_byte(byte)
          integer *= 10
          integer += byte - 48
          digits += 1
          byte = @io.read_byte
        end

        case byte
        when 46
          consume_float(byte, negative, integer, digits)
        when 101, 69
          consume_exponent(byte, negative, integer.to_f64, digits)
        else
          @io.pos -= 1
          negative ? -integer : integer
        end
      else
        raise "error 2"
      end
    end

    private def consume_float(byte, negative, integer, digits)
      @buffer.write_byte(byte.as(UInt8))
      divisor = 1_u64
      byte = @io.read_byte
      while byte && 48 <= byte <= 57
        @buffer.write_byte(byte)
        integer *= 10
        integer += byte - 48
        divisor *= 10
        byte = @io.read_byte
      end
      float = integer.to_f64 / divisor

      if byte == 101 || byte == 69
        consume_exponent(byte, negative, float, digits)
      else
        @io.pos -= 1
        if digits >= 18
          @buffer.to_s.to_f64
        else
          negative ? -float : float
        end
      end
    end

    private def consume_exponent(byte, negative, float, digits)
      @buffer.write_byte(byte.as(UInt8))
      exponent = 0
      negative_exponent = false

      byte = @io.read_byte
      if byte == 43
        @buffer.write_byte(byte.as(UInt8))
        byte = @io.read_byte
      elsif byte == 45
        @buffer.write_byte(byte.as(UInt8))
        byte = @io.read_byte
        negative_exponent = true
      end

      if byte && 48 <= byte <= 57
        while byte && 48 <= byte <= 57
          @buffer.write_byte(byte)
          exponent *= 10
          exponent += byte - 48
          byte = @io.read_byte
        end
      else
        raise "error 3"
      end

      exponent = -exponent if negative_exponent
      float *= (10_f64 ** exponent)
      @io.pos -= 1

      if digits >= 18
        @buffer.to_s.to_f64
      else
        negative ? -float : float
      end
    end

    # :nodoc:
    LITERAL_STRING_ESCAPE_MAP = {
      'n'.ord  => '\n',
      'r'.ord  => '\r',
      't'.ord  => '\t',
      'b'.ord  => '\b',
      'f'.ord  => '\f',
      '('.ord  => '(',
      ')'.ord  => ')',
      '\\'.ord => '\\',
    }

    # Parses the literal string at the current position.
    #
    # See: PDF1.7 s7.3.4.2
    private def parse_literal_string
      @buffer.clear
      parentheses = 1

      while (byte = @io.read_byte)
        case byte
        when 40
          parentheses += 1
          @buffer.write_byte(byte)
        when 41
          parentheses -= 1
          break if parentheses == 0
          @buffer.write_byte(byte)
        when 13
          @buffer << "\n"
          @io.pos += 1 if peek_byte == 10
        when 92
          byte = @io.read_byte
          if byte == nil
            break
          elsif (data = LITERAL_STRING_ESCAPE_MAP[byte])
            @buffer << data
          elsif byte == 10 || byte == 13
            @io.pos += 1 if byte == 13 && peek_byte == 10
          elsif byte.as(UInt8) >= 48 && byte.as(UInt8) <= 55
            t = IO::Memory.new
            t.write_byte(byte.as(UInt8))
            while (byte = @io.read_byte) != nil && (48..55).covers?(byte.as(UInt8)) && t.size < 3
              t.write_byte(byte.as(UInt8))
            end
            @io.pos -= 1
            @buffer << t.to_s.to_i(base: 8).chr
          else
            @buffer.write_byte(byte.as(UInt8))
          end
        else
          @buffer.write_byte(byte.as(UInt8))
        end
      end

      if parentheses != 0
        raise "error"
      end

      @buffer.to_s
    end

    # Parses the hex string at the current position.
    #
    # See: PDF1.7 s7.3.4.3
    private def parse_hex_string
      @buffer.clear
      while (byte = @io.read_byte) && byte != 62
        @buffer.write_byte(byte)
      end
      if byte != 62
        raise "error"
      end
      str = @buffer.to_s
      str = str.delete("\0\t\n\f\r ")
      # [str].pack("H*")
      str
    end

    # Parses the name at the current position.
    #
    # See: PDF1.7 s7.3.5
    private def parse_name
      str = parse_until_whitespace_or_delimiter
      str = str.gsub(/#[A-Fa-f0-9]{2}/) { |m| m[1, 2].to_u8(base: 16).chr }
      Name.new(str)
    end

    # Parses the array at the current position.
    #
    # It is assumed that the initial '[' has already been scanned.
    #
    # See: PDF1.7 s7.3.6
    private def parse_array
      result = [] of PDFObject
      while true
        obj = next_object(allow_end_array_token: true)
        if obj.is_a?(Token)
          break
        else
          result << obj
        end
      end
      result
    end

    # Parses the dictionary at the current position.
    #
    # It is assumed that the initial '<<' has already been scanned.
    #
    # See: PDF1.7 s7.3.7
    private def parse_dictionary
      result = {} of Name => PDFObject
      while true
        # Use #next_token because we either need a Name or the '>>' token here, the latter would
        # throw an error with #next_object.
        key = next_token
        break if key.is_a?(Token) && key.type == :DICT_END
        unless key.is_a?(Name)
          raise "error"
        end

        val = next_object
        next if val.nil?

        if val.is_a?(Token)
          raise "error"
        else
          result[key] = val
        end
      end
      result
    end
  end
end
