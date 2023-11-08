all: install build test

install:
	bundle install

build:
	JEKYLL_ENV=production bundle exec jekyll build

test: build
	bundle exec htmlproofer --disable-external --ignore-missing-alt --swap-urls '^/evse-scaling-behavior/:/' _site
