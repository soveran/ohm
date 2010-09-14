# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

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

test "raise an error if the errors are not handled" do
  begin
    @model.errors.present do |e|
      e.on :terrible_error do
      end
    end
  rescue => e
    assert e.class == Ohm::Validations::Presenter::UnhandledErrors
  end
end

test "evaluate blocks when errors match" do
  values = []

  @model.errors.present do |e|
    e.on [:name, :not_present] do
      values << 1
    end

    e.on [:account, :not_present] do
      values << 2
    end

    e.on :terrible_error do
      values << 3
    end
  end

  assert [1, 2, 3] == values
end

test "accept case-like matches for an error" do
  values = []

  @model.errors.present do |e|
    e.on Array do
      values << 1
    end

    e.on :terrible_error do
      values << 3
    end
  end

  assert [1, 3] == values
end

test "accept multiple matches for an error" do
  values = @model.errors.present do |e|
    e.on [:name, :not_present], "A"
    e.on [:account, :not_present] do
      "B"
    end
    e.on :terrible_error, "C"
  end

  assert %w{A B C} == values
end

class MyPresenter < Ohm::Validations::Presenter
  def on(*args)
    super(*args) do
      yield.downcase
    end
  end
end

test "take a custom presenter" do
  values = @model.errors.present(MyPresenter) do |e|
    e.on([:name, :not_present]) { "A" }
    e.on([:account, :not_present]) { "B" }
    e.on(:terrible_error) { "C" }
  end

  assert %w{a b c} == values
end

test "raise an error if neither a message nor a block are supplied" do
  begin
    Ohm::Validations::Presenter.new([:custom]).present do |e|
      e.on(:custom)
    end
  rescue => e
    assert e.class == ArgumentError
  end
end

test "not raise an error if the message passed is nil" do
  values = Ohm::Validations::Presenter.new([:custom]).present do |e|
    e.on(:custom, nil)
  end

  assert [nil] == values

  Ohm::Validations::Presenter.new([:custom]).present do |e|
    e.on(:custom, nil) do
      raise "Should not call block"
    end
  end
end
