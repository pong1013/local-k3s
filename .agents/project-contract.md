# Project Contract

## Repository and purpose

- Repository: `pong1013/local-k3s`, configured Git remote `origin`.
- This is a single-context Bash CLI for creating and managing a local k3s lab on Multipass VMs through `chien-dev`.
- GitHub Issues is the specification and ticket tracker; `docs/agents/issue-tracker.md` defines its identity and operations.

## Verification

- Complete repository verification: `make test`.
- `make test` runs `make syntax` and the integration scripts under `tests/integration/`.
- The integration scripts use mocks for external tools. Passing them does not prove that real Multipass VMs, k3s, Helm charts, or network installation work.
- For changes to VM creation, installation, kubeconfig, or optional add-ons, report whether a real-environment check was performed; never present mock results as real-environment validation.
- Record the exact command, exit status, and relevant output for each check. A failed or skipped check remains visible in the run ledger.

## Domain knowledge and work artifacts

- Read `docs/agents/domain.md`; use a root `CONTEXT.md` and `docs/adr/` only when settled terminology or decisions warrant them.
- Keep the canonical feature specification and implementation tickets in GitHub Issues.
- Keep disposable run checkpoints in ignored `.agents/runs/`; do not treat checkpoints as approval or as canonical project documentation.
- Do not put credentials, kubeconfig content, k3s join tokens, or other secrets in repository artifacts.

## Workspace and ownership

- Start feature changes on a dedicated `codex/` branch from the current `main` baseline after Workspace Gate approval.
- Record pre-existing changes before branching. Do not stage, discard, or incorporate unrelated changes into ticket commits.
- Assign implementation and quality work to separate agents as required by `$ai-workflow`; keep their owned file paths explicit.
- Only the workflow controller stages and commits a ticket after its verification and review pass.

## Delivery

- Local ticket commits require the approved ticket scope and passing ticket quality evidence.
- Pushing the branch and creating a pull request require a separate Delivery Gate approval for the exact target and changes.
- Never merge the pull request or directly close its issues as part of this workflow.
