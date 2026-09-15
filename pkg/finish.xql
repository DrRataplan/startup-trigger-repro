xquery version "3.1";

(:~
 : Runs inside org.exist.repo.AutoDeploymentTrigger (a StartupTrigger),
 : synchronously inside BrokerPool.start() - before the pool registers
 : itself under its instance name ("exist") and before Jetty listens.
 :
 : REPRO_MODE=broken (default): calls sm:create-account inline. Fails -
 : it looks up the named "exist" BrokerPool instance, which can't exist
 : yet because this call is what's blocking its registration. A bootstrap
 : ordering issue, not a race: it fails immediately (no hang, no thread
 : contention), and retrying wouldn't help either (confirmed separately;
 : see README).
 :
 : REPRO_MODE=fixed: schedules deferred-create.xql via
 : scheduler:schedule-xquery-periodic-job instead. Scheduling is a local
 : Quartz call with no security-manager dependency, so it returns
 : immediately; the job itself runs a few seconds later, once startup has
 : actually finished.
 :)

let $mode := head((fn:environment-variable("REPRO_MODE"), "broken"))
return
    if ($mode = "fixed") then (
        util:log("info", "startup-trigger-repro[fixed]: deferring sm:create-account to a scheduled one-off job instead of calling it inline"),
        scheduler:schedule-xquery-periodic-job(
            "/db/apps/startup-trigger-repro/deferred-create.xql",
            1,
            "startup-trigger-repro-deferred",
            (),
            2000,
            0
        ),
        util:log("info", "startup-trigger-repro[fixed]: job scheduled, finish.xql returning (this always succeeds - scheduling never touches the security manager)")
    ) else (
        util:log("info", "startup-trigger-repro[broken]: calling sm:create-account INLINE from finish.xql (expected to fail)"),
        try {
            sm:create-account("repro-user", "repro-pass", "dba"),
            util:log("info", "startup-trigger-repro: inline sm:create-account(repro-user) SUCCEEDED (unexpected!)")
        } catch * {
            util:log("error", "startup-trigger-repro: inline sm:create-account(repro-user) FAILED - " || $err:code || ": " || $err:description)
        }
    )
