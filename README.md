# TinyOS Network Stack and Chat Simulation

This repository contains a TinyOS/TOSSIM-based wireless network project. It implements
neighbor discovery, link-state flooding, shortest-path routing, IP-style packet
forwarding, a lightweight TCP-like transport layer, and an application layer used for
transport tests and chat-style messaging in simulation.

The code is organized for simulator-driven development. Most interactions happen through
TOSSIM command packets and Python test scripts rather than direct hardware deployment.

# Features

* Neighbor discovery with periodic probes and link-cost estimation
* Flood-based link-state advertisement propagation
* Dijkstra-based route computation over a maintained graph
* IP-style forwarding across multiple hops
* TCP-like transport with sockets, connection state, ACKs, retransmission, and teardown
* Application-level transport tests and a small multi-user chat service
* Docker-based development environment for repeatable TinyOS/TOSSIM builds

# Architecture

## Top-level node wiring

`NodeC.nc` wires the system together. A node is composed of:

* `NeighborDiscovery` for direct-link detection and cost sampling
* `Flooding` for propagating LSAs
* `LSRouting` for maintaining the routing table
* `IPForwarding` for routing packets to their final destination
* `Transport` for socket-based reliable delivery
* `Application` for test traffic and chat behavior
* `CommandHandler` for simulation-driven control

`Node.nc` acts as the main integration point. It boots the radio stack, starts
forwarding/routing, and routes incoming simulator commands into the relevant subsystem.

## Network layers

### Neighbor discovery

`lib/modules/NeighborDiscoveryP.nc` periodically probes the local radio neighborhood,
tracks reachable peers, and maintains per-neighbor cost estimates. These neighbor and
cost lists are then consumed by the routing layer.

### Flooding

`lib/modules/FloodingP.nc` propagates link-state advertisements and acknowledgements.
This is the distribution mechanism used by the routing layer to share topology updates.

### Link-state routing

`lib/modules/LSRoutingP.nc` builds a graph from local and received LSAs, then computes
shortest paths with Dijkstra's algorithm. The resulting routing table stores the next
hop and total path cost for each reachable destination.

### IP forwarding

`lib/modules/IPForwardingP.nc` wraps payloads in an IP-style header, chooses the next
hop from the routing table, and forwards packets hop by hop until they reach their final
destination. It supports both ping-style traffic and transport-layer traffic.

### Transport

`lib/modules/TransportP.nc` implements a lightweight connection-oriented transport layer
using the `Transport` interface in `lib/interfaces/Transport.nc`.

Implemented transport concepts include:

* socket allocation and binding
* listen, accept, and connect
* sequence and acknowledgement handling
* buffered reads and writes
* retransmission with timer-based retry
* graceful close and connection state transitions

The transport layer is carried over the forwarding layer rather than directly over a
single radio hop.

### Application layer

`lib/modules/ApplicationP.nc` provides two main behaviors:

* transport test client/server flows for exercising connection setup and bulk transfer
* a chat server/client model built on the transport layer

The chat application supports commands such as:

* `hello <name> <port>`
* `msg <text>`
* `listusr`
* `whisper <username> <message>`
* `quit`

# Repository Layout

* `Node.nc`, `NodeC.nc` - top-level TinyOS module/configuration
* `lib/interfaces/` - interfaces for command handling, routing, forwarding, transport,
  application control, and helper components
* `lib/modules/` - implementations of networking, transport, and application logic
* `includes/` - packet formats, protocol IDs, socket definitions, routing entries, and
  shared types
* `dataStructures/` - generic hashmap, list, and graph components used by routing logic
* `topo/` - network topologies for simulation
* `noise/` - radio noise traces for simulation
* `TestSim.py`, `pingTest.py` - Python TOSSIM drivers

# Protocol and Command Surface

## Protocol IDs

The shared protocol definitions live in `includes/protocol.h`. The stack currently uses
protocol values for:

* ping and ping reply traffic
* link-state advertisements and acknowledgements
* IP forwarding packets
* transport packets
* neighbor discovery request/reply traffic

## Simulation commands

The command IDs are defined in `includes/command.h` and driven by `TestSim.py`.
Supported commands include:

* ping injection
* neighbor dump
* route table dump
* transport test client start
* transport test server start
* application chat client start
* application chat server start

# Running with Docker

This repository includes a Docker-based TinyOS/TOSSIM setup for development on systems
that do not already have TinyOS installed.

## Files

* `Dockerfile` - builds the TinyOS development image
* `docker-compose.yml` - starts an interactive container with the repository mounted at
  `/workspace`
* `docker/entrypoint.sh` - sets the TinyOS environment variables expected by the build

## Prerequisites

Install Docker Desktop or Docker Engine.

## Build the image

```bash
docker compose build
```

## Open a shell in the container

```bash
docker compose run --rm tinyos
```

The repository is mounted into `/workspace`, so edits made in the container are reflected
in the local checkout.

## Compile simulator artifacts

Inside the container:

```bash
make clean
make micaz sim
make CommandMsg.py
make packet.py
```

Successful simulator builds should generate artifacts such as `TOSSIM.py` and
`_TOSSIMmodule.so`.

## Run simulation scripts

Inside the container:

```bash
python2 pingTest.py
```

or

```bash
python2 TestSim.py
```

## Notes

* The container uses Ubuntu 20.04 because it still provides the TinyOS packages used
  by this project.
* The image assumes TinyOS is installed under `/usr/share/tinyos`.
* The Python simulation tooling in this repository uses Python 2 syntax.
* The Docker setup is aimed at simulation and development, not USB flashing of physical
  motes.

# Running Simulations

## Python drivers

`TestSim.py` is the main simulation harness. It can:

* load a topology from `topo/`
* load a noise trace from `noise/`
* boot all motes
* enable debug channels
* inject commands into selected nodes

Useful helpers in `TestSim.py` include:

* `ping(source, dest, msg)`
* `neighborDMP(destination)`
* `routeDMP(destination)`
* `testServer(destination)`
* `testClient(destination)`
* `appServer(destination)`
* `appClient(destination, port)`
* `chat(node, text)`

## Example workflow

```python
from TestSim import TestSim

def main():
    s = TestSim()
    s.runTime(1)
    s.loadTopo("tuna-melt.topo")
    s.loadNoise("no_noise.txt")
    s.bootAll()

    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.ROUTING_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    s.runTime(5000)

    s.appServer(1)
    s.runTime(100)

    s.appClient(4, 200)
    s.runTime(300)

    s.chat(4, "msg hello from node 4")
    s.runTime(1000)

if __name__ == '__main__':
    main()
```

# Simulation Assets

## Topologies

The repository includes several topology files in `topo/`, including:

* `example.topo`
* `long_line.topo`
* `pizza.topo`
* `tuna-melt.topo`

Topology files specify directed links in the form:

```text
source destination gain
```

For bidirectional connectivity, include both directions.

## Noise traces

Noise files in `noise/` model radio conditions:

* `no_noise.txt` - minimal loss scenario
* `some_noise.txt` - moderate noise scenario
* `meyer-heavy.txt` - heavier noise/loss scenario

# Data Structures and Shared Types

The routing and transport code relies on several shared support components:

* `dataStructures/modules/HashmapC.nc`
* `dataStructures/modules/ListC.nc`
* `dataStructures/modules/GraphC.nc`
* `includes/socket.h`
* `includes/ip_header.h`
* `includes/transport_header.h`
* `includes/route_entry.h`
* `includes/user.h`
* `includes/ring.h`

These provide the storage and wire-format definitions used throughout the stack.
