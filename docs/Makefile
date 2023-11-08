all: install build test

install:
	bundle install

build:
	bundle exec jekyll build

test: build
	bundle exec htmlproofer --disable-external --ignore-missing-alt --swap-urls '^/evse-scaling-behavior/:/' _site
