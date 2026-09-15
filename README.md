# eXist-db StartupTrigger bootstrap ordering repro

Calling `sm:create-account` from inside a package's `finish.xq` fails
**every time** with `Database instance 'exist' is not available`.

## Why

`finish.xq` runs via `AutoDeploymentTrigger`, a `<startup>` trigger —
eXist's own default config, no app-specific customization. Startup triggers
run synchronously inside `BrokerPool.start()`, **before** the BrokerPool
registers itself under its instance name (`"exist"`) and before Jetty
listens. `sm:create-account` looks up that named instance, so the lookup
can never succeed while `finish.xq` — the thing blocking that registration
— is still running. This is not a deadlock: nothing hangs, no thread is
waiting on another. The lookup fails immediately with a clean exception
(`BrokerPool.getInstance` checks a registry and throws if the entry isn't
there yet, rather than blocking for it). It's a bootstrap ordering issue —
a precondition that's structurally unsatisfiable at this point in startup
— so this repro makes a single attempt rather than retrying (retrying was
tested separately and never helps — see Verified below).

**Fix:** never call security-manager functions inline from `finish.xq`.
Defer with `scheduler:schedule-xquery-periodic-job` (one-off, delay > 0) —
a local in-process Quartz call that doesn't touch the security manager, so
it returns instantly; the real work runs a couple seconds later, once
startup has actually finished.

## Layout

- `pkg/finish.xql` — runs inline inside the StartupTrigger (the bug)
- `pkg/deferred-create.xql` — runs later via the scheduler (the fix)
- `build.sh` — packages `pkg/` into `build/startup-trigger-repro.xar`
- `docker-compose.yml` — stock `existdb/existdb`, xar bind-mounted into
  `/exist/autodeploy` (no `conf.xml` patch needed)

`finish.xql` reads `REPRO_MODE`: `broken` (default) calls `sm:create-account`
inline, once; `fixed` schedules `deferred-create.xql` and returns
immediately. No DB volume is mounted, so every `docker compose up`
reinstalls the package from scratch.

## Run it

```sh
./build.sh
REPRO_MODE=broken docker compose up -d   # reproduce
docker compose down -v --remove-orphans
REPRO_MODE=fixed docker compose up -d    # confirm the fix
```

Pin a version with `EXISTDB_TAG` (default `release`), e.g.
`EXISTDB_TAG=6.4.1 docker compose up -d`.

## Verified

Live runs, 2026-09-15, both `REPRO_MODE`s, on `6.4.1`, `7.0.0-beta3`
(= `existdb/existdb:release`, confirmed by image digest) and
`7.0.0-SNAPSHOT`. Same failure, same fix, on every version tested.

**Broken:**
```
inline sm:create-account(repro-user) FAILED - Database instance 'exist' is not available
Server has started, listening on: http://...    # <1s later
```
Startup was never blocked on anything but this trigger returning — the
server starts right after it fails. A retry loop was tested separately (10×
at 500ms): the first attempt always fails with the error above, but the
account is half-persisted before the throw, so every retry after that
fails differently ("account already exists") instead of repeating it. A
real fix needs an `sm:user-exists` guard, not just a retry loop, or it
will eventually "succeed" on a broken, half-created account.

**Fixed:**
```
deferring sm:create-account to a scheduled one-off job instead of calling it inline
job scheduled, finish.xql returning
deferred job firing, calling sm:create-account
deferred sm:create-account(repro-user) SUCCEEDED
```
