#!/usr/bin/env nu

let backend = ($env.FILE_PWD | path join "shrc_nushell_test.sh")

if not ($backend | path exists) {
  print $"Error: backend test script not found: ($backend)"
  exit 1
}

let run = (^bash $backend | complete)

if (($run.stdout | str length) > 0) {
  print $run.stdout
}

if (($run.stderr | str length) > 0) {
  print --stderr $run.stderr
}

if ($run.exit_code != 0) {
  exit $run.exit_code
}
