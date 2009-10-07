require File.join(File.dirname(__FILE__), "test_helper")

class SearchTest < Test::Unit::TestCase
  setup do
    Ohm.flush
  end

  class Lane < Ohm::Model
    attribute :lane_type

    index :lane_type

    def to_s
      lane_type.capitalize
    end

    def validate
      assert_unique :lane_type
    end

    def error_messages
      errors.present do |e|
        e.on [:lane_type, :not_unique], "The lane type #{lane_type} is already in use"
      end
    end
  end

  context "A model with an indexed attribute" do
    setup do
      @results = []
      @subresults = []
      Lane.search(:lane_type => "email") { |sr| @results << sr.size }
      Lane.create(:lane_type => "email")
      Lane.search(:lane_type => "email") { |sr| @results << sr.size }
      Lane.search(:lane_type => "email") { |sr| @results << sr.size }
    end

    should "be able to find by the given attribute" do
      assert_equal [0, 1, 1], @results
    end
  end
end
