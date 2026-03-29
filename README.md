pgdev
=====

`pgdev` is a standalone Docker-based development wrapper for PostgreSQL. 

What It Does
------------

- builds a reusable Debian-based toolchain image
- bind-mounts a PostgreSQL checkout into the container at `/src`
- stores build artifacts and data in a Docker volume at `/workspace`
- runs configure, build, tests, and a foreground server from the chosen source tree

This keeps the dev tooling independent from the PostgreSQL repo while still
building and running local changes.


Layout
------

- `pgdev` is the host-side command you run
- `docker/Dockerfile.dev` builds the toolchain image
- `docker/dev-entrypoint.sh` runs inside the container


Quick Start
-----------

First, add `pgdev` to `$PATH`.

Build the toolchain image once:

```bash
pgdev build-image
```

Build a PostgreSQL checkout or local changes:

```bash
pgdev --source ~/repos/postgresql build
```

Run tests:

```bash
pgdev --source ~/repos/postgresql test
```

Enable opt-in PostgreSQL test categories with `PG_TEST_EXTRA` or `--test-extra`:

```bash
pgdev --source ~/repos/postgresql --test-extra xid_wraparound test
PG_TEST_EXTRA="ssl ldap" pgdev --source ~/repos/postgresql test
PG_TEST_EXTRA="ssl" pgdev --source ~/repos/postgresql --test-extra "ldap xid_wraparound" test
```

Pull the Meson test logs onto the host:

```bash
pgdev --source ~/repos/postgresql testlogs
```

Summarize failures and skips from an exported log:

```bash
pgdev --source ~/repos/postgresql logreport
pgdev logreport ~/Downloads/pgdev-logs/meson-logs/testlog.json
```

Start the server:

```bash
pgdev --source ~/repos/postgresql server
```

Connect from another terminal:

```bash
pgdev --source ~/repos/postgresql psql
```


Normal Edit/Build/Run Flow
--------------------------

1. Edit code in your PostgreSQL checkout.
2. Rebuild:

   ```bash
   pgdev --source ~/repos/postgresql build
   ```

3. Run tests if needed:

   ```bash
   pgdev --source ~/repos/postgresql test
   ```

4. Start the rebuilt server:

   ```bash
   pgdev --source ~/repos/postgresql server
   ```

5. Connect:

   ```bash
   pgdev --source ~/repos/postgresql psql
   ```

The running server does not hot-reload binaries. If you change code, stop the
server, rebuild, and start it again.


Commands
--------

Build or rebuild the image:

```bash
pgdev build-image
```

Configure:

```bash
pgdev --source ~/repos/postgresql configure
```

Build:

```bash
pgdev --source ~/repos/postgresql build
```

Run the default test set:

```bash
pgdev --source ~/repos/postgresql test
```

Add opt-in PostgreSQL test categories:

```bash
pgdev --source ~/repos/postgresql --test-extra xid_wraparound test
PG_TEST_EXTRA="ssl ldap" pgdev --source ~/repos/postgresql test
PG_TEST_EXTRA="ssl" pgdev --source ~/repos/postgresql --test-extra "ldap xid_wraparound" test
```

Export the Meson log directory, including `testlog.txt` and `testlog.json`:

```bash
pgdev --source ~/repos/postgresql testlogs
pgdev --source ~/repos/postgresql testlogs ~/Downloads/pgdev-logs
```

Summarize failures and skips from `testlog.json`:

```bash
pgdev --source ~/repos/postgresql logreport
pgdev logreport ~/Downloads/pgdev-logs/meson-logs/testlog.json
```

Run a suite or specific tests:

```bash
pgdev --source ~/repos/postgresql test --suite recovery
pgdev --source ~/repos/postgresql test recovery/017_shm
pgdev --source ~/repos/postgresql test recovery/017_shm recovery/018_wal_optimize
```

Run tests against a manually started server:

```bash
pgdev --source ~/repos/postgresql runningcheck
```

Open a shell:

```bash
pgdev --source ~/repos/postgresql shell
```

Open `psql` with defaults for this workflow:

```bash
pgdev --source ~/repos/postgresql psql
pgdev --source ~/repos/postgresql --port 55433 psql
pgdev --source ~/repos/postgresql psql -c 'select version()'
```

Start the server on a different port:

```bash
pgdev --source ~/repos/postgresql --port 55433 server
```

Remove the build/data volume for a checkout:

```bash
pgdev --source ~/repos/postgresql clean
```


Multiple PostgreSQL Checkouts
-----------------------------

`pgdev` is designed for this use case.

By default, the workspace volume name is derived from the absolute source path,
so different checkouts get different persistent build and data state.

Examples:

```bash
pgdev --source ~/repos/postgresql-master build
pgdev --source ~/repos/postgresql-master server
```

```bash
pgdev --source ~/repos/postgresql-v18 build
pgdev --source ~/repos/postgresql-v18 --port 55433 server
```

That lets you jump between versions without clobbering each checkout's build
tree or cluster.

If you want to override the volume identity manually, use `--workspace-key`:

```bash
pgdev --source ~/repos/postgresql --workspace-key rel18 build
pgdev --source ~/repos/postgresql --workspace-key rel18 server
```


Configuration
-------------

Global options:

- `--source PATH` selects the PostgreSQL checkout
- `--workspace-key KEY` overrides the derived workspace identity
- `--port PORT` changes the forwarded port
- `--shm-size SIZE` sets the Docker `/dev/shm` size used by the container
- `--build-jobs N` overrides `PG_BUILD_JOBS` inside the container
- `--test-jobs N` overrides `PG_TEST_JOBS` inside the container
- `--test-extra LIST` adds categories to `PG_TEST_EXTRA`
- `--image NAME` changes the Docker image name

Environment variables:

- `PG_DEV_SOURCE`
- `PG_DEV_WORKSPACE_KEY`
- `PG_DEV_PORT`
- `PG_DEV_SHM_SIZE`
- `PG_DEV_BUILD_JOBS`
- `PG_DEV_TEST_JOBS`
- `PG_TEST_EXTRA`
- `PG_DEV_IMAGE`
- `PG_DEV_VOLUME`

`PG_DEV_VOLUME` overrides the computed Docker volume name directly.
If both `PG_TEST_EXTRA` and `--test-extra` are provided, the combined set is
passed to the container with duplicates removed.


Notes
-----

- The source checkout is mounted read-only for most commands.
- `pgdev test` and `pgdev runningcheck` mount the source checkout
  writable because some PostgreSQL tests generate temporary files alongside
  source fixtures.
- The container defaults to `--shm-size=1g`, and you can raise or lower that
  with `--shm-size` or `PG_DEV_SHM_SIZE`.
- Build artifacts live in a Docker volume, not in a local repo.
- The default database superuser in this workflow is `postgres`.
- `pgdev psql` defaults to `PGUSER=postgres` and `PGDATABASE=postgres`.
- `pgdev testlogs` exports `/workspace/build/meson-logs` to
  `./pgdev-logs/<workspace-key>/meson-logs` by default.
- `pgdev logreport` reads `testlog.json` and prints failures and skip
  reasons. With `--source`, it defaults to
  `./pgdev-logs/<workspace-key>/meson-logs/testlog.json`.
- Host TCP access is configured for this dev environment, and the port is
  published only on `127.0.0.1` on the host.
