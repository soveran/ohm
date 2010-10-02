### Chaining Ohm Sets

#### Doing the straight forward approach

# Let's design our example around the following requirements:
#
# 1. a `User` has many orders.
# 2. an  `Order` can be pending, authorized or captured.
# 3. a `Product` is referenced by an `Order`.

#### Doing it the normal way

# Let's first require `Ohm`.
require "ohm"

# A `User` has a `collection` of *orders*. Note that a collection
# is actually just a convenience, which implemented simply will look like:
#
#     def orders
#       Order.find(:user_id => self.id)
#     end
#
class User < Ohm::Model
  collection :orders, Order
end

# The product for our purposes will only contain a name.
class Product < Ohm::Model
  attribute :name
end

# We define an `Order` with just a single `attribute` called state, and
# also add an `index` so we can search an order given its state.
#
# The `reference` to the `User` is actually required for the `collection`
# of *orders* in the `User` declared above, because the `reference` defines
# an index called `:user_id`.
#
# We also define a `reference` to a `Product`.
class Order < Ohm::Model
  attribute :state
  index :state

  reference :user, User
  reference :product, Product
end

##### Testing what we have so far.

# For the purposes of this tutorial, we'll use cutest for our test framework.
require "cutest"

# Make sure that every run of our test suite has a clean Redis instance.
prepare { Ohm.flush }

# Let's create a *user*, a *pending*, *authorized* and a captured order.
# We also create two products named *iPod* and *iPad*.
setup do
  @user = User.create

  @ipod = Product.create(:name => "iPod")
  @ipad = Product.create(:name => "iPad")

  @pending =    Order.create(:user => @user, :state => "pending",
                             :product => @ipod)
  @authorized = Order.create(:user => @user, :state => "authorized",
                             :product => @ipad)
  @captured =   Order.create(:user => @user, :state => "captured",
                             :product => @ipad)
end

# Now let's try and grab all pending orders, and also pending
# *iPad* and *iPod* ones.
test "finding pending orders" do
  assert @user.orders.find(state: "pending").include?(@pending)

  assert @user.orders.find(:state => "pending",
                           :product_id => @ipod.id).include?(@pending)

  assert @user.orders.find(:state => "pending",
                           :product_id => @ipad.id).empty?
end

# Now we try and find captured and authorized orders. The tricky part
# is trying to find an order that is either *captured* or *authorized*,
# since `Ohm` as of this writing doesn't support unions in its
# finder syntax.
test "finding authorized and/or captured orders" do
  assert @user.orders.find(:state => "authorized").include?(@authorized)
  assert @user.orders.find(:state => "captured").include?(@captured)

  assert @user.orders.find(:state => ["authorized", "captured"]).empty?

  auth_or_capt = @user.orders.key.volatile[:auth_or_capt]
  auth_or_capt.sunionstore(
    @user.orders.find(:state => "authorized").key,
    @user.orders.find(:state => "captured").key
  )

  assert auth_or_capt.smembers.include?(@authorized.id)
  assert auth_or_capt.smembers.include?(@captured.id)
end

#### Creating shortcuts

# You can of course define methods to make that code more readable.
class User < Ohm::Model
  def authorized_orders
    orders.find(:state => "authorized")
  end

  def captured_orders
    orders.find(:state => "captured")
  end
end

# And we can now test these new methods.
test "finding authorized and/or captured orders" do
  assert @user.authorized_orders.include?(@authorized)
  assert @user.captured_orders.include?(@captured)
end

# In most cases this is fine, but if you want to have a little fun,
# then we can play around with some chainability.

#### Chaining Kung-Fu

# The `Ohm::Model::Set` takes a *Redis* key and a *class monad*
# for its arguments.
#
# We can simply subclass it and define the monad to always be an
# `Order` so we don't have to manually set it everytime.
class UserOrders < Ohm::Model::Set
  def initialize(key)
    super key, Ohm::Model::Wrapper.wrap(Order)
  end

  # Here is the crux of the chaining pattern. Instead of
  # just doing a straight up `find(:state => "pending")`, we return
  # `UserOrders` again.
  def pending
    self.class.new(model.index_key_for(:state, "pending"))
  end

  def authorized
    self.class.new(model.index_key_for(:state, "authorized"))
  end

  def captured
    self.class.new(model.index_key_for(:state, "captured"))
  end

  # Now we wrap the implementation of doing an `SUNIONSTORE` and also
  # make it return a `UserOrders` object.
  #
  # NOTE: `volatile` just returns the key prepended with a `~:`, so in
  # this case it would be `~:Order:accepted`.
  def accepted
    model.key.volatile[:accepted].sunionstore(
      authorized.key, captured.key
    )

    self.class.new(model.key.volatile[:accepted])
  end
end

# Now let's re-open the `User` class and add a customized `orders` method.
class User < Ohm::Model
  def orders
    UserOrders.new(Order.index_key_for(:user_id, id))
  end
end

# Ok! Let's put all of that chaining code to good use.
test "finding pending orders using a chainable style" do
  assert @user.orders.pending.include?(@pending)
  assert @user.orders.pending.find(:product_id => @ipod.id).include?(@pending)

  assert @user.orders.pending.find(:product_id => @ipad.id).empty?
end

test "finding authorized and/or captured orders using a chainable style" do
  assert @user.orders.authorized.include?(@authorized)
  assert @user.orders.captured.include?(@captured)

  assert @user.orders.accepted.include?(@authorized)
  assert @user.orders.accepted.include?(@captured)

  accepted = @user.orders.accepted

  assert accepted.find(:product_id => @ipad.id).include?(@authorized)
  assert accepted.find(:product_id => @ipad.id).include?(@captured)
end

#### Conclusion

# This design pattern is something that really depends upon the situation. In
# the example above, you can add more complicated querying on the `UserOrders`
# class.
#
# The most important takeaway here is the ease of which we can weild the
# different components of Ohm, and mold it accordingly to our preferences,
# without having to monkey-patch anything.
