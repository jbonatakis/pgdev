pgdev
=====

`pgdev` is a standalone Docker-based development wrapper for PostgreSQL
checkouts. It lets you keep the workflow in its own repo while pointing it at
one or more local PostgreSQL source trees.

What It Does
------------

- builds a reusable Debian-based toolchain image
- bind-mounts a PostgreSQL checkout into the container at `/src`
- stores build artifacts and data in a Docker volume at `/workspace`
- runs configure, build, tests, and a foreground server from the chosen source tree

This keeps the dev tooling independent from the PostgreSQL repo while still
building and running your local changes.


Layout
------

- `bin/pgdev` is the host-side command you run
- `docker/Dockerfile.dev` builds the toolchain image
- `docker/dev-entrypoint.sh` runs inside the container


Quick Start
-----------

Build the toolchain image once:

```bash
bin/pgdev build-image
```

Build a PostgreSQL checkout or local changes:

```bash
bin/pgdev --source ~/repos/postgresql build
```

Run tests:

```bash
bin/pgdev --source ~/repos/postgresql test
```

Start the server:

```bash
bin/pgdev --source ~/repos/postgresql server
```

Connect from another terminal:

```bash
psql -h localhost -p 55432 -U postgres -d postgres
```


Normal Edit/Build/Run Flow
--------------------------

1. Edit code in your PostgreSQL checkout.
2. Rebuild:

   ```bash
   bin/pgdev --source ~/repos/postgresql build
   ```

3. Run tests if needed:

   ```bash
   bin/pgdev --source ~/repos/postgresql test
   ```

4. Start the rebuilt server:

   ```bash
   bin/pgdev --source ~/repos/postgresql server
   ```

5. Connect:

   ```bash
   psql -h localhost -p 55432 -U postgres -d postgres
   ```

The running server does not hot-reload binaries. If you change code, stop the
server, rebuild, and start it again.


Commands
--------

Build or rebuild the image:

```bash
bin/pgdev build-image
```

Configure:

```bash
bin/pgdev --source ~/repos/postgresql configure
```

Build:

```bash
bin/pgdev --source ~/repos/postgresql build
```

Run the default test set:

```bash
bin/pgdev --source ~/repos/postgresql test
```

Run a suite or specific tests:

```bash
bin/pgdev --source ~/repos/postgresql test --suite recovery
bin/pgdev --source ~/repos/postgresql test recovery/017_shm
bin/pgdev --source ~/repos/postgresql test recovery/017_shm recovery/018_wal_optimize
```

Run tests against a manually started server:

```bash
bin/pgdev --source ~/repos/postgresql runningcheck
```

Open a shell:

```bash
bin/pgdev --source ~/repos/postgresql shell
```

Start the server on a different port:

```bash
bin/pgdev --source ~/repos/postgresql --port 55433 server
```

Remove the build/data volume for a checkout:

```bash
bin/pgdev --source ~/repos/postgresql clean
```


Multiple PostgreSQL Checkouts
-----------------------------

`pgdev` is designed for this use case.

By default, the workspace volume name is derived from the absolute source path,
so different checkouts get different persistent build and data state.

Examples:

```bash
bin/pgdev --source ~/repos/postgresql-master build
bin/pgdev --source ~/repos/postgresql-master server
```

```bash
bin/pgdev --source ~/repos/postgresql-v18 build
bin/pgdev --source ~/repos/postgresql-v18 --port 55433 server
```

That lets you jump between versions without clobbering each checkout's build
tree or cluster.

If you want to override the volume identity manually, use `--workspace-key`:

```bash
bin/pgdev --source ~/repos/postgresql --workspace-key rel18 build
bin/pgdev --source ~/repos/postgresql --workspace-key rel18 server
```


Configuration
-------------

Global options:

- `--source PATH` selects the PostgreSQL checkout
- `--workspace-key KEY` overrides the derived workspace identity
- `--port PORT` changes the forwarded port
- `--image NAME` changes the Docker image name

Environment variables:

- `PG_DEV_SOURCE`
- `PG_DEV_WORKSPACE_KEY`
- `PG_DEV_PORT`
- `PG_DEV_IMAGE`
- `PG_DEV_VOLUME`

`PG_DEV_VOLUME` overrides the computed Docker volume name directly.


Notes
-----

- The source checkout is mounted read-only into the container.
- Build artifacts live in a Docker volume, not in the PostgreSQL repo.
- The default database superuser in this workflow is `postgres`.
- Host TCP access is configured for this dev environment, and the port is
  published only on `127.0.0.1` on the host.
