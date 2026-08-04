# TODO

## Add mesh to CI once it stabilizes

`make test` runs `mesh_test.sh` (378 tests over `config/mesh/env.mesh` and
`config/mesh/rc.mesh`) only when `mesh` is on PATH, so on the CI runner it
prints `SKIP: test-mesh (mesh not installed)` and the job still goes green.
`install-ci-shells.sh` installs zsh, fish and nu but deliberately leaves mesh
out.

The reason is that mesh has no releases to pin. The other three are fixed to a
version and a checksum, which is what makes a CI failure mean "the config
broke" rather than "upstream moved". mesh is pre-1.0 and its language is still
being designed in `docs/DESIGN.md`, so tracking its `main` would put the config
tests at the mercy of an in-progress language — a mesh change could turn CI red
here with nothing wrong in this repo. That is a worse signal than the skip.

When it settles enough to pin — a tagged release, or a commit worth holding
still — add it alongside the others:

```sh
cargo install --git https://github.com/mikelward/mesh --tag "$MESH_VERSION" mesh
```

with `MESH_VERSION` in `test-tool-versions.sh` like the rest. A `cargo install`
build costs a few minutes per run, so cache it on that pin rather than
rebuilding every job.

Two things to check when it lands, because both are exercised by the current
config and neither is old: `:bool` (mikelward/mesh#394) is what
`config/mesh/env.mesh` reads `FAILSAFE` with, and the suite needs `mesh -c` to
stay able to source a config non-interactively.
