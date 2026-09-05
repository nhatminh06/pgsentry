# pgsentry contributor guidance

pgsentry is a PostgreSQL reliability engineering lab that measures and verifies database behavior under failover, partitions, unsafe migrations, and recovery — rather than merely demonstrating that an HA stack can be deployed.

## Scope

- Follow the fixed M1–M10 roadmap and work on one explicitly authorized milestone at a time. Do not invent M11 or scaffold later milestones early.
- Keep the canonical seven-VM topology separate from the resource-constrained three-VM development topology.
- Preserve the boundary between infrastructure provisioning and database/service configuration.
- Back reliability claims with commands and evidence executed against the canonical topology. Never infer runtime behavior from configuration alone.

## Changes and verification

- Inspect repository state, relevant files, available tooling, and the live baseline before editing.
- Reuse existing modules and conventions; keep changes minimal and milestone-specific.
- Run formatting, validation, and applicable provisioning checks. Report commands that could not run and why.
- Never commit credentials, private keys, Terraform state, or generated secrets.
- Do not weaken tests, stage, commit, push, or add AI attribution unless explicitly authorized.

