all: install build test

install:
	bundle install

build:
	echo $$JEKYLL_ENV
	bundle exec jekyll build

test: build
	bundle exec htmlproofer --disable-external --
	ignore-missing-alt --swap-urls '^/evse-scaling-behavior/:/' _site
