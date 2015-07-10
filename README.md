# Discovery

[![Build Status](https://travis-ci.org/undeadlabs/discovery.png?branch=master)](https://travis-ci.org/undeadlabs/discovery) [![Inline docs](http://inch-ci.org/github/undeadlabs/discovery.svg?branch=master)](http://inch-ci.org/github/undeadlabs/discovery)

An OTP application for auto-discovering services with [Consul](http://www.consul.io)

## Requirements

* Elixir 1.0.0 or newer

## Installation

Add Discovery as a dependency in your `mix.exs` file

```elixir
def application do
  [applications: [:discovery]]
end

defp deps do
  [
    {:discovery, "~> 0.5.0"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.


## Usage

There are two parts for automatically interconnecting services.

  * Services need to publish their status
  * Services which care about others need to poll for the statuses of the services they care about

### Publishing service status

First, you'll need to install a [Consul Agent](http://www.consul.io/docs/agent/basics.html) on the machine which will be running the OTP application. This can be done manually, but I recommend the [Consul Cookbook](https://github.com/johnbellone/consul-cookbook) for [Chef](http://getchef.com).

Next a [service definition](http://www.consul.io/docs/agent/services.html) must be defined with a TTL for an application to report it's status to.

```json
{
  "service": {
    "name": "my_application",
    "check": {
      "ttl": "15s"
    },
    "tags": [
      "otp_name:my_application@jamie.undeadlabs.com"
    ]
  }
}
```

The TTL acts as a [dead man's trigger](https://www.youtube.com/watch?v=GyDEbV3zblA) where the service will be marked as unavailable if the OTP application hasn't sent a heartbeat within the allotted TTL.

Start and supervise a `Discovery.Heartbeat` process in your OTP application to report your status to Consul.

```elixir
defmodule MyApplication.Supervisor do
  use Supervisor

  @heartbeat_check "service:my_application"
  @heartbeat_ttl   10

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    children = [
      worker(Discovery.Heartbeat, [@heartbeat_check, @heartbeat_ttl]),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
```

The value for `@heartbeat_check` is composed of two strings separated by a colon:

  * The first string is the type of check that we're reporting our status for; in this case a service.
  * The second string is the name of the check which was defined in the service definition above.

The value for `@heartbeat_ttl` a time in seconds for how often to check-in with Consul. I recommend setting this to a few seconds before the TTL configured in the service definition to allow for some breathing room and prevent false service outage blips.

If you want other OTP nodes to automatically discover and connect to you (more on that later) it is also important to note that a special tag has been added to the service definition above. Tags separated by a colon (`:`) are key/value pairs used by certain handlers. In this case the `Discovery.NodeConnector` will use the value of this key/value pair as the OTP node name to connect to another OTP node.

### Polling for services

The flipside for broadcasting service status is listening for service status. For that, Discovery provides a poller process that can be started and supervised.

```elixir
defmodule MyApplication.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    children = [
      worker(Discovery.Poller, ["my_application", Discovery.Handler.NodeConnect], id: MyApplication.MyPoller),
    ]
    supervise(children, strategy: :one_for_one)
  end
end
```

The poller process will poll the given service health check and upon change, notify a handler process implementing `Discovery.Handler.Behaviour`. One or many handlers can be passed to the poller. In the above example a single handler, `Discovery.Handler.NodeConnector`, is registered with the poller.

> If you are supervising multiple pollers it is important to specify a value for `:id`. Not doing so will halt startup. This can be safely ignored if you do not intend to supervise more than one poller.

#### Poller handler

In the previous section we passed the module `Discovery.Handler.NodeConnect` as an argument to `Discovery.Poller` when we supervised the poller. This is a poller handler.

Poller handlers implement the behaviour `Discovery.Handler.Behaviour` which requires a single function to be implemented, `handle_services/2`. This function is called whenever the poller completes and passes the services it found when performing a health check as the first argument. The second argument is the state of the event handler.

> `Discovery.Handler.Behaviour` is actually using `GenEvent` under the hood

Discovery comes with two handlers

  * `Discovery.Handler.NodeConnector` - automatically connects OTP nodes which have been discovered by a poller
  * `Discovery.Handler.Generic` - executes an anonymous function with an arity of 1 with the found services

Multiple handlers can be added and they can be added with or without arguments:

```elixir
def init([]) do
  children = [
    worker(Discovery.Poller, ["my_application", [
      Discovery.Handler.NodeConnect,
      {MyApplication.MyHandler, ["argument_1", "argument_2"]}
    ], id: MyApplication.MyPoller),
  ]
  supervise(children, strategy: :one_for_one)
end
```

An anonymous function can also act as a handler:

```elixir
def init([]) do
  children = [
    worker(Discovery.Poller, ["my_application", &my_function/1], id: MyApplication.MyPoller)
  ]
  supervise(children, strategy: :one_for_one)
end

def my_function(services) do
  # do something
end
```

> The generic handler `Discovery.Handler.Generic` is used under the hood if you provide an anonymous function as a handler.

### Automatically connecting nodes (Handler.NodeConnect)

The node connector handler `Discovery.Handler.NodeConnect` will notify the registered `Discovery.NodeConnector` process of additional nodes and service status changes.

The `Discovery.NodeConnector` process will automatically connect and retry connections to other nodes when they become available. It will also sever connections when Consul reports those nodes as being no longer available.

`Node.connect/1` will be be run for each registered service found by Consul. The OTP node name for each of these nodes is read from a tag written to the service definition (see above) in the form of `otp_name:<name>` where name is the OTP node name. So given the node name `my_application@jamie.undeadlabs.com` the service definition would contain a tag `otp_name:my_application@jamie.undeadlabs.com`.

> Ensure that the --name flag is set to the proper node name before starting your OTP application. This can be set in the `vm.args` file or passed to Elixir on the command line.

### Selecting nodes

Nodes which have been automatically discovered and connected to via `Discovery.NodeConnector` can be filtered or selected via a hash value.

Listing all registered nodes which provide the given service:

```Elixir
iex> Discovery.nodes("my_application")
[:'my_application@jamie.undeadlabs.com']

iex> Discovery.nodes("another_application")
[]
```

Selecting a node for a given hash value using a consistent hashing algorithm:

```Elixir
Discovery.select("my_application", "hashValue", fn
  {:ok, node} ->
    # do something with node
  {:error, {:no_servers, "my_application"}} ->
    # do something with error
end)
```

A node can also be randomly selected if the atom `:random` is passed as the hash value:

```Elixir
Discovery.select("my_application", :random, fn(result) -> IO.inspect result end)
```

## Authors

Jamie Winsor (<jamie@undeadlabs.com>)
