# Introduction
This skeleton code is the basis for the CSE160 network project. Additional documentation
on what is expected will be provided as the school year continues.

# Docker Setup
This repository now includes a Docker-based development setup for TinyOS/TOSSIM work.
The goal is to give you a repeatable Linux environment for compiling the project and
running the Python simulation scripts without changing your host machine.

## Files
* `Dockerfile` - builds the TinyOS development image.
* `docker-compose.yml` - starts an interactive container with this repository mounted
at `/workspace`.
* `docker/entrypoint.sh` - sets the TinyOS environment variables used by the Makefile.

## Prerequisites
Install Docker Desktop or Docker Engine on your machine before using these steps.

## Build the image
From the repository root, run:

```bash
docker compose build
```

## Start a shell in the container
```bash
docker compose run --rm tinyos
```

This opens a shell in `/workspace`, which is the mounted copy of this repository.
Any file changes you make in the container will appear in your local checkout.

## Compile the simulator artifacts
Inside the container, run:

```bash
make clean
make micaz sim
make CommandMsg.py
make packet.py
```

If `make micaz sim` succeeds, it should generate simulator outputs such as
`TOSSIM.py` and `_TOSSIMmodule.so` in the repo root.

## Run a simulation
After building the simulator artifacts, run one of the Python scripts from inside
the same container shell:

```bash
python2 pingTest.py
```

or

```bash
python2 TestSim.py
```

## One-command workflow
If you want to build and immediately open a shell:

```bash
docker compose build
docker compose run --rm tinyos
```

## Rebuilding after code changes
Normal source changes do not require rebuilding the Docker image. Rebuild the image
only if you change:
* `Dockerfile`
* `docker-compose.yml`
* `docker/entrypoint.sh`

For normal code changes, just rerun:

```bash
make micaz sim
```

## Notes and assumptions
* This setup is based on Ubuntu 20.04 because Ubuntu Focal still provides `tinyos-tools`
and related packages used by the project.
* The image assumes TinyOS installs into `/usr/share/tinyos`, which matches the package
layout used by the Ubuntu package set.
* The Python simulation scripts in this repo use Python 2 syntax, so commands in the
container use `python2`.
* This setup is intended for simulation and local development. It does not configure
USB device passthrough for flashing physical motes.

# General Information
## Data Structures
There are two data structures included into the project design to help with the
assignment. See dataStructures/interfaces/ for the header information of these
structures.

* **Hashmap** - This is for anything that needs to retrieve a value based on a key.

* **List** - The list is design to have pushfront, pushback capabilities. For the most part,
you can stick with an array or even a QueueC (FIFO) which are more robust.

## General Libraries
/lib/interfaces

* **CommandHandler** - CommandHandler is what interfaces with TOSSIM. Commands are
sent to this function, and based on the parameters passed, an event is fired.
* **SimpleSend** - This is a wrapper of the lower level sender in TinyOS. The features
included is a basic queuing mechanism and some small delays to prevent collisions. Do
not change the delays. You can duplicate SimpleSendC to use a different AM type or
possibly rewire it.
* **Transport** - There is only the interface of Transport included. The actual
implementation of the Transport layer is left to the student as an exercise. For
CSE160 this will be Project 3 so don't worry about it now.

## Noise
/noise/

This is the "noise" of the network. A heavy noised network will cause issues with
packet loss.

* **no_noise.txt** - There should be no packet loss using this model.

## Topography
/topo/

This folder contains a few example topographies of the network and how they are
connected to each other. Be sure to try additional networks when testing your code
since additional ones will be added when grading.

* **long_line.topo** - this topography is a line of 19 motes that have bidirectional
links.
* **example.topo** - A slightly more complex connection

Each line has three values, the source node, the destination node, and the gain.
For now you can keep the gain constant for all of your topographies. A line written
as ```1 2 -53``` denotes a one-way connection from 1 to 2. To make it bidirectional
include also ```2 1 -53```.

# Running Simulations
The following is an example of a simulation script.
```
from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    s.loadTopo("long_line.topo");

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);

    # After sending a ping, simulate a little to prevent collision.
    s.runTime(1);
    s.ping(1, 2, "Hello, World");
    s.runTime(1);

    s.ping(1, 10, "Hi!");
    s.runTime(1);

if __name__ == '__main__':
    main()
```
