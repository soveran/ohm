.PHONY: all test examples

all: test

test:
	bundle exec cutest -r ./test/helper.rb ./test/*.rb

examples:
	RUBYLIB="./lib" bundle exec cutest ./examples/*.rb
