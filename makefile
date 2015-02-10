.PHONY: all test examples

all: test

test:
	cutest -r ./test/helper.rb ./test/*.rb

examples:
	RUBYLIB="./lib" cutest ./examples/*.rb
