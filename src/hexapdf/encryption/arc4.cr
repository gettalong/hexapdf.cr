module HexaPDF
  module Encryption
    # Iplementation of the general encryption algorithm ARC4.
    #
    # See: PDF1.7 s7.6.2
    class ARC4
      # Encrypts the given +data+ with the +key+.
      #
      # See: PDF1.7 s7.6.2.
      def self.encrypt(key, data)
        new(key).process(data)
      end

      def self.decrypt(key, data)
        new(key).process(data)
      end

      @state : Bytes

      # Creates a new ARC4 object using the given encryption key.
      def initialize(key : Bytes)
        @i = @j = 0_u8
        @state = INITIAL_STATE.clone
        initialize_state(key)
      end

      # Processes the given data.
      #
      # Since this is a symmetric algorithm, the same method can be used for encryption and
      # decryption.
      def process(data : Bytes)
        result = data.clone
        byte_index = 0
        result_size = result.size
        while byte_index < result_size
          @i = @i + 1
          @j = @j + @state[@i]
          @state[@i], @state[@j] = @state[@j], @state[@i]
          result[byte_index] ^= @state[@state[@i] + @state[@j]]
          byte_index += 1
        end
        result
      end

      # The initial state which is then modified by the key-scheduling algorithm
      INITIAL_STATE = Bytes.new(256)
      (0_u8..255_u8).each { |b| INITIAL_STATE[b] = b }

      # Performs the key-scheduling algorithm to initialize the state.
      private def initialize_state(key)
        i = j = 0_u8
        key_size = key.size
        while true
          j = j + @state[i] + key[i % key_size]
          @state[i], @state[j] = @state[j], @state[i]
          i += 1
          break if i == 0
        end
      end
    end
  end
end
