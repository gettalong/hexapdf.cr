require "./pdf_object"

module HexaPDF
  # Tokenizes the content of an IO object following the PDF rules.
  #
  # See: PDF1.7 s7.2
  class Tokenizer
    class Token
      property type : Symbol
      property value : String

      def self.[](str)
        new(:keyword, str)
      end

      def initialize(@type = :eof, @value = "")
      end

      def ==(other : self)
        type == other.type && (type != :keyword || value == other.value)
      end

      def to_s
        @value
      end

      def to_s(io)
        io << @value
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
      when '+'.ord, '-'.ord, '.'.ord,
           '0'.ord, '1'.ord, '2'.ord, '3'.ord, '4'.ord, '5'.ord, '6'.ord, '7'.ord, '8'.ord, '9'.ord
        parse_number(byte.as(UInt8))
      when '/'.ord
        parse_name
      when '('.ord
        parse_literal_string
      when '<'.ord
        if peek_byte != '<'.ord
          parse_hex_string
        else
          @io.read_byte
          @token.type = :dict_start
          @token
        end
      when '>'.ord
        unless @io.read_byte == '>'.ord
          raise MalformedPDFException.new("Delimiter '>' found at invalid position", pos: pos)
        end
        @token.type = :dict_end
        @token
      when '['.ord
        @token.type = :array_start
        @token
      when ']'.ord
        @token.type = :array_end
        @token
      when '{'.ord
        @token.type = :"{"
        @token
      when '}'.ord
        @token.type = :"}"
        @token
      when '%'.ord
        while true
          case @io.read_byte
          when '\n'.ord, '\r'.ord
            break
          when nil
            @token.type = :eof
            return @token
          end
        end
        next_token
      when nil # we reached the end of the file
        @token.type = :eof
        @token
      else # everything else consisting of regular characters
        parse_keyword(byte)
      end
    end

    # Returns the next token but does not advance the scan pointer.
    def peek_token
      pos = self.pos
      tok = next_token
      self.pos = pos
      tok
    end

    # Returns the PDF object at the current position. This is different from #next_token because
    # references, arrays and dictionaries consist of multiple tokens.
    #
    # If +allow_end_array_token+ is +true+, the ']' token is permitted to facilitate the use of
    # this method during array parsing.
    #
    # If +allow_keyword+ is +true+, the return value may also be a Token instance.
    # See: PDF1.7 s7.3
    def next_object(allow_end_array_token = false, allow_keyword = false)
      token = next_token

      if token.is_a?(Token)
        case token.type
        when :dict_start
          token = parse_dictionary
        when :array_start
          token = parse_array
        when :array_end
          unless allow_end_array_token
            raise MalformedPDFException.new("Found invalid end array token ']'", pos: pos)
          end
        else
          unless allow_keyword
            raise MalformedPDFException.new("Invalid object, got token #{token}", pos: pos)
          end
        end
      end

      token
    end

    # Skips all whitespace at the current position.
    #
    # See: PDF1.7 s7.2.2
    def skip_whitespace
      while byte = @io.read_byte
        if !whitespace?(byte)
          @io.pos -= 1
          break
        end
      end
    end

    # Reads the byte at the current position and advances the scan pointer.
    def next_byte
      @io.read_byte
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
        @token.type = :keyword
        @token.value = str
        @token
      end
    end

    # Parses the number (integer or real) at the current position.
    #
    # See: PDF1.7 s7.3.3
    private def parse_number(byte)
      integer = 0_i64
      negative = false
      original_byte = byte

      if byte == '-'.ord
        negative = true
        byte = @io.read_byte
      elsif byte == '+'.ord
        byte = @io.read_byte
      end

      case byte
      when nil
        @io.pos -= 1 if original_byte != byte
        @token.type = :keyword
        @token.value = String.new(Bytes.new(1, original_byte))
        @token
      when ('0'.ord)..('9'.ord)
        integer = (byte - '0'.ord).to_i64
        byte = @io.read_byte
        while byte && '0'.ord <= byte <= '9'.ord
          integer *= 10
          integer += byte - '0'.ord
          byte = @io.read_byte
        end

        case byte
        when '.'.ord
          parse_float(integer, negative)
        else
          @io.pos -= 1 if byte
          negative ? -integer : integer
        end
      when '.'.ord
        parse_float(integer, negative)
      else
        @io.pos -= 1 if original_byte != byte
        parse_keyword(original_byte)
      end
    end

    private def parse_float(integer, negative)
      divisor = 1_u64
      byte = @io.read_byte
      while byte && '0'.ord <= byte <= '9'.ord
        integer *= 10
        integer += byte - '0'.ord
        divisor *= 10
        byte = @io.read_byte
      end
      float = integer.to_f64 / divisor

      @io.pos -= 1 if byte
      negative ? -float : float
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
        when '('.ord
          parentheses += 1
          @buffer.write_byte(byte)
        when ')'.ord
          parentheses -= 1
          break if parentheses == 0
          @buffer.write_byte(byte)
        when '\r'.ord
          @buffer << '\n'
          @io.pos += 1 if peek_byte == '\n'.ord
        when '\\'.ord
          byte = @io.read_byte
          if byte.nil?
            break
          elsif (data = LITERAL_STRING_ESCAPE_MAP[byte]?)
            @buffer << data
          elsif byte == '\n'.ord || byte == '\r'.ord
            @io.pos += 1 if byte == '\r'.ord && peek_byte == '\n'.ord
          elsif '0'.ord <= byte <= '9'.ord
            temp = IO::Memory.new
            temp.write_byte(byte)
            while !(byte = @io.read_byte).nil? && '0'.ord <= byte <= '9'.ord && temp.size < 3
              temp.write_byte(byte)
            end
            @io.pos -= 1
            @buffer << temp.to_s.to_i(base: 8).chr
          else
            @buffer.write_byte(byte)
          end
        else
          @buffer.write_byte(byte) #.as(UInt8))
        end
      end

      if parentheses != 0
        raise MalformedPDFException.new("Unclosed literal string found", pos: pos)
      end

      @buffer.to_slice.clone
    end

    # Parses the hex string at the current position.
    #
    # See: PDF1.7 s7.3.4.3
    private def parse_hex_string
      @buffer.clear
      while (byte = @io.read_byte) && byte != '>'.ord
        @buffer.write_byte(byte) unless whitespace?(byte)
      end
      if byte != '>'.ord
        raise MalformedPDFException.new("Unclosed hex string found", pos: pos)
      end
      @buffer << '0' if @buffer.size % 2 == 1
      @buffer.to_s.hexbytes
    end

    # Parses the name at the current position.
    #
    # See: PDF1.7 s7.3.5
    private def parse_name
      str = parse_until_whitespace_or_delimiter
      str = str.gsub(/#[A-Fa-f0-9]{2}/) { |m| m[1, 2].to_u8(base: 16).chr }
      Name[str]
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
        break if key.is_a?(Token) && key.type == :dict_end
        unless key.is_a?(Name)
          raise MalformedPDFException.new("Dictionary keys must be PDF name objects", pos: pos)
        end

        val = next_object
        next if val.nil?

        result[key] = val.as(PDFObject)
      end
      result
    end

    private def peek_byte
      byte = @io.read_byte
      @io.pos -= 1 if byte
      byte
    end

    private def whitespace?(byte)
      case byte
      when '\0'.ord, '\t'.ord, '\n'.ord, '\f'.ord, '\r'.ord, ' '.ord
        true
      else
        false
      end
    end

    private def delimiter?(byte)
      case byte
      when '/'.ord, '%'.ord, '('.ord, ')'.ord, '<'.ord, '>'.ord, '['.ord, ']'.ord, '{'.ord, '}'.ord
        true
      else
        false
      end
    end

    private def parse_until_whitespace_or_delimiter(byte = nil)
      @buffer.clear
      @buffer.write_byte(byte) if byte

      while byte = @io.read_byte
        if whitespace?(byte) || delimiter?(byte)
          @io.pos -= 1
          break
        else
          @buffer.write_byte(byte)
        end
      end

      @buffer.to_s
    end
  end
end
