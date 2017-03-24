# Multish

Allows to run multiple commands in one terminal, side by side.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'multish'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install multish

## Usage

Example:

    $ multish 'find ..' 'for i in `seq 1 10`; do echo $i; sleep 1; done' 'curl -v http://google.com'

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/multish.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

