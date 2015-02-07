# MarketShip
EVE Market Aggregator for Ship Fittings

## Development Setup
1. ``` gem install bundler ```
2. Change directory to the root of the repo
3. ``` bundle install ```
4. ``` bundle exec rackup config.ru ```

## Currently Implemented Features
* EFT-like parsing
* Shopping list calculations [Lowest Jita Sell Value]
* Automatic Package Planner (for EH Shipping)

## Future Features
* List of doctrine ships locked under Eve SSO
* Multiple Region Calculations
* Lossmail Parsing
* SRP Calculations