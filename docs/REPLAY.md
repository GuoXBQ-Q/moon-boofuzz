# Replay recorded sequences

Load records with `recordio.read_records`, handle its optional parse issue,
then use `records.select_case(records, id)`. Unknown or duplicate identities
are errors. Call `runner.replay(record)` or pass
`override_target=("127.0.0.1", 9000)` to change host/port while retaining timeouts.

Replay validates the format, identity, stored transport options and response
policies before connecting. It sends only `steps[].sent` in recorded order,
including partial bytes from a failed send. It never invokes protocol
compilation or a mutation generator. A fresh connection is used and always
closed. No response-equality check or current monitor callback is applied;
the original response boundaries and timeouts still govern receiving.

`ExecutionConfig::parse` rejects unknown/unsupported network properties and
validates all limits. Only recorded TCP/UDP configurations can use native replay;
custom test channels require their own application integration.

Source: new GPL-2.0-only replay implementation built on the portable record
schema. It does not emulate boofuzz's database or regenerate upstream mutants.
Tests change the generator and response contents while asserting identical
saved outgoing bytes, plus malformed configuration/version/identity rejection.
