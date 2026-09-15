xquery version "3.1";

(:~
 : The REPRO_MODE=fixed counterpart to the inline call in finish.xql.
 : Scheduled by finish.xql as a one-off job; by the time this actually
 : runs, eXist's own startup has finished and the "exist" BrokerPool
 : instance is registered, so sm:create-account works normally.
 :)

util:log("info", "startup-trigger-repro[fixed]: deferred job firing, calling sm:create-account"),
try {
    if (sm:user-exists("repro-user")) then
        util:log("info", "startup-trigger-repro: repro-user already exists")
    else (
        sm:create-account("repro-user", "repro-pass", "dba"),
        util:log("info", "startup-trigger-repro: deferred sm:create-account(repro-user) SUCCEEDED")
    )
} catch * {
    util:log("error", "startup-trigger-repro: deferred sm:create-account(repro-user) FAILED - " || $err:code || ": " || $err:description)
}
