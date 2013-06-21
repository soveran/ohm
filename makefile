.PHONY: test

test:
	cutest -r ./test/helper.rb ./test/*.rb
