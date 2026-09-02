FPV Labs has published new commits to `fpv-labs/stera-app:main`.

This PR is intentionally not auto-merged. Before merging:

- Resolve conflicts without renaming `stera_recorder` or the Stera MCAP contract.
- Run `bun run brand:verify` and `bun run brand:test`.
- Run `bun run check-types`, `flutter analyze`, and `flutter test`.
- Build iOS and validate one complete recording on a physical device.

See [UPSTREAM.md](../UPSTREAM.md) for the compatibility boundary and release procedure.
