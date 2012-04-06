# encoding: UTF-8

require File.expand_path("./helper", File.dirname(__FILE__))

if defined?(Ohm::Model::PureRuby)
  class User < Ohm::Model
    attribute :email

    attr_accessor :foo

    def save
      super do |t|
        t.before do
          self.email = email.downcase
        end

        t.after do
          if @foo
            key[:foos].sadd(@foo)
          end
        end
      end
    end

    def delete
      super do |t|
        foos = nil

        t.before do
          foos = key[:foos].smembers
        end

        t.after do
          foos.each { |foo| key[:foos].srem(foo) }
        end
      end
    end
  end

  test do
    u = User.create(:email => "FOO@BAR.COM", :foo => "bar")
    assert_equal "foo@bar.com", u.email
    assert_equal ["bar"], u.key[:foos].smembers

    u.delete
    assert_equal [], User.key[u.id][:foos].smembers
  end
end
