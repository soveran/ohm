Ohm
============

Object-hash mapping library for Redis.

Description
-----------

Ohm is a library that allows to store an object in
[Redis](http://code.google.com/p/redis/), a persistent key-value
database. It includes an extensible list of validations and has very
good performance.

Usage
-----

    require 'ohm'

    Ohm.connect

    class Event < Ohm::Model
      attribute :name
      set :participants
      list :comments

      def validate
        assert_present :name
      end
    end

    event = Event.create(:name => "Ruby Tuesday")
    event.participants << "Michel Martens"
    event.participants << "Damian Janowski"
    event.participants      #=> ["Damian Janowski", "Michel Martens"]

    event.comments << "Very interesting event!"
    event.comments << "Agree"
    event.comments          #=> ["Very interesting event!", "Agree"]

    another_event = Event.new
    another_event.valid?    #=> false
    another_event.errors    #=> [[:name, :nil]]

    another_event.name = ""
    another_event.valid?    #=> false
    another_event.errors    #=> [[:name, :empty]]

    another_event.name = "Ruby Lunch"
    another_event.save      #=> true

Installation
------------

    $ sudo gem install ohm

License
-------

Copyright (c) 2009 Michel Martens and Damian Janowski

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
