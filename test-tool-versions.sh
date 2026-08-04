#!/bin/sh
# Versions and checksums of the tools `make test` wants but no environment
# here ships. Sourced by both installers -- .claude/hooks/session-start.sh for
# the agent container and install-ci-shells.sh for the CI runner -- so a bump
# happens once and the two cannot drift.
#
# Drift is the failure this file exists to prevent: the two installers used to
# be the only place a version lived, and a suite that passes in one environment
# and fails in the other, against a different build of the same shell, is a
# long afternoon.
#
# Bump a version and its checksum together. The pin fixes *which* release is
# wanted; the checksum is what makes the downloaded bytes actually that
# release, so a replaced asset or a compromised publisher account cannot hand
# an installer a binary every later test then executes.

SHELLCHECK_VERSION=0.10.0
SHELLCHECK_SHA256=6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87

# Matches the version on the maintainer's machine. 0.101.0 could not parse
# config/nushell/config.nu at all, so the whole nu-native suite died on a
# parser error rather than running.
NU_VERSION=0.113.1
NU_SHA256=9008d309aaa35e29ed5d5985306a83e2bf5093e31677d4cd969914552d12b8fb

# fish publishes a single self-contained executable per release, so this needs
# no build and no apt. Pinned to a 4.x because config/fish/config.fish is
# written against it; Ubuntu's own package is still on 3.x, which is why the
# distro copy is not what CI installs.
FISH_VERSION=4.1.2
FISH_SHA256=3d68eb2617fb1f07006723893f078784e37e7e2923d4bc61ab4654c2966fd369
