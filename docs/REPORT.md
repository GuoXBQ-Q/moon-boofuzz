# Replay and report commands

`report CASES.jsonl` summarizes total cases and counts by outcome, with failure
case IDs, line numbers and steps. It prints a report for the complete prefix
even if a later line is corrupt, includes the issue, and exits with code 2.
`--max-bytes N` raises the default 64 MiB file-read limit explicitly.

`replay CASES.jsonl --id CASE_ID` validates the complete file, selects an
unambiguous identity, and replays saved bytes. Add `--host HOST --port PORT`
together to override the target. The JSON result includes actual sent/received
hex, outcome and failed step. Exit 0 means successful replay execution, 1 means
a replay network/response failure, and 2 means a configuration or file error.
Existing monitor callbacks and response equality checks are not rerun.

The CLI scenarios test offline parser inputs, TCP timeout recording/reporting/
replay after deleting the source definition, and fresh handshake/authentication
for every stateful target case. Reports are new GPL-2.0-only functionality over
the project's portable record schema, not an upstream database reader.
