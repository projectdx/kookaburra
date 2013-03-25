require 'kookaburra/mental_model'
require 'timeout'

class Kookaburra
  class MentalModel
    # This is a custom matcher that matches the RSpec matcher API.
    #
    # @see Kookaburra::TestHelpers#match_mental_model_of
    # @see Kookaburra::TestHelpers#assert_mental_model_of
    class Matcher
      # Creates a new matcher for the given MentalModel on the given
      # collection_key.
      #
      # @param [MentalModel] mental_model The MentalModel instance to
      #   request the expected collection from.
      # @param collection_key The name of the collection that contains
      #   the expected elements.
      # @param [Integer] wait_for The number of seconds during which to
      #   continually retry failures, before reporting the failure. Not
      #   used when comparing against an array (see #matches?).
      # @return [self]
      def initialize(mental_model, collection_key, wait_for = 2)
        @collection_key = collection_key
        @wait_for = wait_for

        mental_model.send(collection_key).tap do |collection|
          @expected   = collection.dup
          @unexpected = collection.deleted.dup
        end
      end

      # Specifies that result should be limited to the given keys from the
      # mental model.
      #
      # Useful if you are looking at a filtered result. That is, your mental
      # model contains elements { A, B, C }, but you only expect to see element
      # A.
      #
      # @example
      #   matcher.only?(:foo, :bar, :baz)
      # @example With an array of keys
      #   keys = [:foo, :bar, :baz]
      #   matcher.only?(*keys)
      #
      # @param collection_keys The keys used in your mental model to reference
      #   the data - if you have an array, splat it.
      # @return [self]
      def only(*collection_keys)
        keepers = @expected.slice(*collection_keys)
        tossers = @expected.except(*collection_keys)

        @expected = keepers
        @unexpected.merge! tossers

        self
      end

      # Specifies that members of the expected collection should be mapped by
      # the given block before attempting to match.
      #
      # Useful if the result represents a modified version of what's on the
      # mental model.
      #
      # @yield [val] map function, run once for each member of the collection
      # @return [self]
      def mapped_by(&block)
        validate_block_arguments 'mapped_by', &block
        @expected = Hash[@expected.map { |key, val| [key, block.call(val)] }]
        @unexpected = Hash[@unexpected.map { |key, val| [key, block.call(val)] }]
        self
      end

      # Specifies that result should be filtered by a given block.
      #
      # Useful if you are looking at a filtered result based on given criteria.
      # That is, you only expect to see elements for which a given block
      # returns true.
      #
      # @yield [val] function used to select specific results from collection
      # @return [self]
      def where(&block)
        validate_block_arguments 'where', &block
        valid_keys = @expected.select { |key, val| block.call(val) }.map { |key, val| key }
        only *valid_keys
      end

      # Reads better than {#only} with no args
      #
      # @return [self]
      def expecting_nothing
        only
      end

      # Specifies the method to try calling on "actual," which is expected to
      # return the observed result for comparison against the mental model.
      #
      # @param [Symbol] method The method to call on "actual"
      # @return [self]
      def using(collection_method)
        @collection_method = collection_method
        self
      end

      # The result contains everything that was expected to be found and nothing
      # that was unexpected.
      #
      # The MentalModel::Matcher can be used with two types of objects.
      #
      # 1) If the matcher is called on an Array, a direct comparison will be
      # done between the Array and the MentalModel collection (after any
      # specified scoping or mapping methods have) been applied.
      #
      # 2) If the matcher is called on an object that responds to the
      # collection_method (which defaults to the collection_key but can be
      # overridden with "#using"), the result of actual#collection_method will
      # be used for the comparison.
      #
      # When using method #2, if the match is unsuccessful, failure won't be
      # reported immediately; instead, the comparison will be retried
      # continuously for the number of seconds specified by wait_for (see
      # "#initialize").  This is the recommended usage, and is useful for taking
      # into account possible rendering delays.
      #
      # (Part of the RSpec protocol for custom matchers.)
      #
      # @param [Array, #collection_method] actual This is the data observed
      #   (or an object that returns the data observed when called with
      #   collection_method) that you you are attempting to match against the
      #   mental model.
      # @return Boolean
      def matches?(actual)
        @collection_method ||= @collection_key
        @proc_for_actual = if actual.respond_to?(@collection_method.to_sym)
          proc { actual.send(@collection_method.to_sym) }
        else
          @wait_for = 0
          proc { actual }
        end
        if @wait_for > 0
          begin
            Timeout.timeout(@wait_for) do
              sleep(0.1) until value = check_expectations
              value
            end
          rescue TimeoutError
            false
          end
        else
          check_expectations
        end
      end

      # Message to be printed when observed reality does not conform to
      # mental model.
      #
      # (Part of the RSpec protocol for custom matchers.)
      #
      # @return String
      def failure_message_for_should
        message = "expected #{@collection_key} to match the user's mental model, but:\n"
        if expected_items_not_found.present?
          message += "expected to be present:         #{pp_array(expected_items)}\n"
          message += "the missing elements were:      #{pp_array(expected_items_not_found)}\n"
        end
        if unexpected_items_found.present?
          message += "expected to not be present:     #{pp_array(unexpected_items)}\n"
          message += "the unexpected extra elements:  #{pp_array(unexpected_items_found)}\n"
        end
        message
      end

      # Message to be printed when observed reality does conform to mental
      # model, but you did not expect it to.  (To be honest, we can't think of
      # why you would want this, but it is included for the sake of RSpec
      # compatibility.)
      #
      # (Part of the RSpec protocol for custom matchers.)
      #
      # @return String
      def failure_message_for_should_not
        "expected #{@collection_key} not to match the user's mental model"
      end

      # (Part of the RSpec protocol for custom matchers.)
      #
      # @return String
      def description
        "match the user's mental model of #{@collection_key}"
      end

      private

      def expected_items;   @expected.values;   end
      def unexpected_items; @unexpected.values; end

      def expected_items_not_found
        difference_between_arrays(expected_items, @actual)
      end

      def unexpected_items_found
        unexpected_items_not_found = difference_between_arrays(unexpected_items, @actual)
        difference_between_arrays(unexpected_items, unexpected_items_not_found)
      end

      def check_expectations
        @actual = @proc_for_actual.call
        expected_items_not_found.empty? && unexpected_items_found.empty?
      end

      # (Swiped from RSpec's array matcher)
      # Returns the difference of arrays, accounting for duplicates.
      # e.g., difference_between_arrays([1, 2, 3, 3], [1, 2, 3]) # => [3]
      def difference_between_arrays(array_1, array_2)
        difference = array_1.dup
        array_2.each do |element|
          if index = difference.index(element)
            difference.delete_at(index)
          end
        end
        difference
      end

      def pp_array(array)
        array = array.sort if array.all? { |e| e.respond_to?(:<=>) }
        array.inspect
      end

      def validate_block_arguments(method, &block)
        raise "Must supply a block to ##{method}" unless block_given?
        raise "Block supplied to ##{method} must take one argument (the value)" unless block.arity == 1
      end

      def wait_until
        Timeout.timeout(Capybara.default_wait_time) do
          sleep(0.1) until value = yield
          value
        end
      end
    end
  end
end
