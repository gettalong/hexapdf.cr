module HexaPDF
  class MalformedPDFException < Exception
    @pos : Nil | Int32 | Int64

    # The byte position in the PDF file where the error occured.
    getter pos

    # Creates a new exception object.
    #
    # The byte position where the error occured can be given via the optional +pos+ argument.
    def initialize(message, pos = nil)
      super(message)
      @pos = pos
    end

    def message
      pos_msg = @pos.nil? ? "" : " around position #{pos}"
      "PDF malformed#{pos_msg}: #{super}"
    end
  end
end
