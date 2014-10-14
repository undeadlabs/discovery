# Changelog

## 0.5.3

* Enhancements
  * Update to latest version of Consul package

## 0.5.2

* Enhancements
  * Change arity of NodeConnector.Handler.on_connect/2 and on_disconnect/2 to on_connect/3 and on_disconnect/3. The third parameter is the state of the event handler to allow for customization at start up.

## 0.5.1

* Bug Fixes
  * Calls to NodeConnector.connect/2 are now idempotent.
  * Running a heartbeat process will once again register a service with Discovery.Directory.

## 0.5.0

* Enhancements
  * Add `NodeConnector.Handler` module. This can be given to a Poller to run on_connect and on_disconnect functions upon succesful node connect, reconnect, or disconnects.
  * Added `enable_polling` app configuration which can be set to false in test or dev or places where you do not want to connect out to Consul.
  * Increase Consul long poll retry to 30 seconds from 5.

* Bug Fixes
  * Running a heartbeat process will no longer register a service with the directory. This will ensure that pollers are the only thing that manipulate the Directory and all handlers are properly run.
  * Fix indefinite retry issue when unable to communicate with Consul.

## 0.4.0

* Enhancements
  * Broadcast to other nodes Directory service upon a successful connect

## 0.3.3

* Enhancements
  * No longer require github version of hackney now that it is hosted on hex

## 0.3.0

* Enhancements
  * Updated for Elixir 0.15.x

## 0.2.0

* Enhancements
  * Automatically deregister provided services from nodes no longer providing service
  * Automatically disconnect from nodes that are no longer providing any services

## 0.1.0

* Initial release
