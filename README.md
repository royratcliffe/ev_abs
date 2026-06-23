# ev_abs

A SWI-Prolog service that consumes `EV_ABS` (absolute axis) input events from a
Redis stream, normalises joystick axis values, and republishes the results to a
separate Redis stream. Designed to run in Docker, connecting to a Redis instance
via the network.

## Overview

Input events — produced by joystick or gamepad devices — arrive as entries on a
Redis stream (default key: `input_event`). Each entry carries fields such as
`device`, `typename`, `codename`, `value`, `absinfo_minimum`, and
`absinfo_maximum`. The service filters for `EV_ABS` events whose code names map
to X/Y axes (e.g. `ABS_X`/`ABS_Y`, `ABS_RX`/`ABS_RY`), normalises the raw
integer value to the range `[-1, 1]` (or `[0, 1]` for trigger axes), and
publishes the result to the `ev_abs` Redis stream.

## Requirements

- [Docker](https://docs.docker.com/get-docker/)
- A running Redis server accessible on the network

## Build

```sh
docker build -t ev_abs .
```

The image is based on Alpine Linux with SWI-Prolog installed from the Alpine
edge testing repository. All `.pl` source files are compiled to `.qlf` bytecode
at image build time for the sake of faster startup and reduced image size.

## Run

```sh
docker run --rm --network=host ev_abs
```

This command runs the service in a Docker container, connecting to a Redis server
on the host network. The service will consume events from the `input_event` stream
and publish normalised axis values to the `ev_abs` stream.

### Options

| Flag | Description |
|------|-------------|
| `-v` / `--verbose` | Enable verbose debug output |

```sh
docker run --rm --network=host ev_abs -v
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REDISCLI_HOST` | `localhost` | Redis server hostname |
| `REDISCLI_PORT` | `6379` | Redis server port |
| `HOSTNAME` | `ev_abs_consumer` | Consumer name used in the Redis consumer group |

```sh
docker run --rm --network=host \
  -e REDISCLI_HOST=redis.local \
  -e REDISCLI_PORT=6379 \
  ev_abs
```

## Redis Streams

| Stream key | Direction | Description |
|------------|-----------|-------------|
| `input_event` | Input | Raw `EV_ABS` events from input devices |
| `ev_abs` | Output | Normalised axis values per stick |

Output entries on the `ev_abs` stream contain: `device`, `stick`, `x` (or `y`),
and the complementary axis value when both axes are available. It _only_
publishes when both axes of a stick have been received, so that the consumer of
the `ev_abs` stream can always read a complete stick state.

The service creates the `ev_abs` consumer group on the `input_event` stream
automatically at startup (with `MKSTREAM`), so no manual stream setup is
required.

## Project Structure

| File | Description |
|------|-------------|
| `ev_abs.pl` | Main module: settings, event consumption, axis normalisation |
| `xgroup.pl` | Helper module: idempotent `XGROUP CREATE` wrapper |
| `Dockerfile` | Alpine-based Docker image definition |

## License

Released under the MIT License.
