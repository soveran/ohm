require File.join(File.dirname(__FILE__), "test_helper")

class ErrorsTest < Test::Unit::TestCase
  class User < Ohm::Model
    attribute :name
    attribute :account

    def validate
      assert_present :name
      assert_present :account
      assert false, :terrible_error
    end
  end

  setup do
    @model = User.new(:account => "")
    @model.valid?
  end

  context "errors handler" do
    should "raise an error if the errors are not handled" do
      assert_raise Ohm::Validations::Presenter::UnhandledErrors do
        @model.errors.present do |e|
          e.on :terrible_error do
          end
        end
      end
    end

    should "evaluate blocks when errors match" do
      values = []

      @model.errors.present do |e|
        e.on [:name, :nil] do
          values << 1
        end

        e.on [:account, :empty] do
          values << 2
        end

        e.on :terrible_error do
          values << 3
        end
      end

      assert_equal [1, 2, 3], values
    end

    should "accept case-like matches for an error" do
      values = []

      @model.errors.present do |e|
        e.on Array do
          values << 1
        end

        e.on :terrible_error do
          values << 3
        end
      end

      assert_equal [1, 3], values
    end

    should "accept multiple matches for an error" do
      values = @model.errors.present do |e|
        e.on [:name, :nil], "A"
        e.on [:account, :empty] do
          "B"
        end
        e.on :terrible_error, "C"
      end

      assert_equal %w{A B C}, values
    end

    class MyPresenter < Ohm::Validations::Presenter
      def on(*args)
        super(*args) do
          yield.downcase
        end
      end
    end

    should "take a custom presenter" do
      values = @model.errors.present(MyPresenter) do |e|
        e.on([:name, :nil]) { "A" }
        e.on([:account, :empty]) { "B" }
        e.on(:terrible_error) { "C" }
      end

      assert_equal %w{a b c}, values
    end

    should "raise an error if neither a message nor a block are supplied" do
      assert_raise ArgumentError do
        Ohm::Validations::Presenter.new([:custom]).present do |e|
          e.on(:custom)
        end
      end
    end

    should "not raise an error if the message passed is nil" do
      values = Ohm::Validations::Presenter.new([:custom]).present do |e|
        e.on(:custom, nil)
      end

      assert_equal [nil], values

      assert_nothing_raised do
        Ohm::Validations::Presenter.new([:custom]).present do |e|
          e.on(:custom, nil) do
            raise "Should not call block"
          end
        end
      end
    end
  end
end
