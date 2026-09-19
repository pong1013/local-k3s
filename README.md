# local-k3s

`local-k3s` is a VM-backed local k3s lab installer. It creates Multipass VM nodes through `chien-dev`, installs a `1 server + N workers` k3s cluster, merges kubeconfig into `~/.kube/config`, optionally installs `fake-gpu-operator`, and writes a Markdown report.

This project is intentionally not a generic k3s builder. It is an all-in-one local lab package for people who do not want to prepare instances or VMs by hand.

## Requirements

- macOS or Linux
- Git (for installation)
- `chien-dev` from [dev-environment-setup](https://github.com/pong1013/dev-environment-setup)
- Multipass
- OpenSSH client
- `kubectl`
- `helm` if installing `fake-gpu-operator`

Windows and WSL are not officially supported in the first version.

One-command requirements setup is not included yet. For now, install the required tools above before running the lab commands.

## Usage

Install from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/pong1013/local-k3s/main/install.sh | bash
```

The installer checks out `main` under `~/.k3s-vm-lab` and links `~/.local/bin/local-k3s`. Add `~/.local/bin` to your `PATH` if the installer prompts you. Re-running the installer refreshes the checkout and preserves existing cluster data under `~/.k3s-vm-lab/generated`.

Run commands from any directory:

```bash
local-k3s doctor
local-k3s create my-lab
local-k3s status my-lab
local-k3s status my-lab wide
local-k3s report my-lab
local-k3s start my-lab
local-k3s stop my-lab
local-k3s delete my-lab
local-k3s update
```

`local-k3s update` fetches `origin/main` for the installed checkout (by default,
`~/.k3s-vm-lab`) and prints the installed and remote commit IDs. If the
revisions differ, it aligns the installed checkout with remote `main`. This
overwrites local changes to tracked files, including local commits, while
keeping untracked cluster data under `generated/`. If fetching fails, the
command exits with an error and leaves the installed revision unchanged. Set
`K3S_VM_LAB_INSTALL_DIR` to use a non-default installation directory.

During `create`, the CLI asks for:

- cluster name, if not provided in the command
- total node count, including the fixed `1 control-plane/server` node
- Ubuntu version for every VM node
- resource size for each node, with explicit CPU/RAM/disk values or custom values
- whether to install `fake-gpu-operator` after the cluster is ready

Example interactive creation:

```text
local-k3s create my-lab

==============================================
 local-k3s | VM-backed local k3s lab
==============================================
This command creates one k3s control-plane/server VM plus worker VMs.
Total node count, including the control-plane/server (default=2):
Select Ubuntu version for all VM nodes:
  1) 22.04
  2) 24.04
Enter option number: 1
Host capacity
  CPU:       8 cores
  RAM:       24G
  Free disk: 386G
  Reserve:   2 CPU / 4G RAM / 20G disk

Resources for my-lab-server-1 (server)
Select resource size:
  1) small - 2 CPU / 2G RAM / 20G disk
  2) medium - 2 CPU / 4G RAM / 30G disk
  3) large - 4 CPU / 8G RAM / 40G disk
  4) custom - enter CPU, RAM, and disk
Enter option number: 1
Install fake-gpu-operator after the cluster is ready? [y/N]:
```

Node names are deterministic:

```text
<cluster>-server-1
<cluster>-worker-1...N
```

## Resource Profiles

| Size | Resources |
| --- | --- |
| small | 2 CPU / 2G RAM / 20G disk |
| medium | 2 CPU / 4G RAM / 30G disk |
| large | 4 CPU / 8G RAM / 40G disk |
| custom | prompted CPU / RAM / disk |

The create flow shows host CPU, RAM, and free disk before resource selection. It checks the sum of all node resources before creating VMs and reserves at least `2 CPU + 4G RAM + 20G disk` for the host.

## Start, Stop, and Delete Safety

`start` starts stopped cluster VM nodes and waits for Kubernetes nodes to become Ready.

`stop` pauses the cluster VM nodes and records `stopped`. It keeps generated files, the cluster index entry, and kubeconfig entries intact.

`delete` permanently deletes VM nodes, purges Multipass deleted instances, backs up `~/.kube/config`, removes only the kube context/cluster/user recorded in the k3s-vm-lab index, removes the index entry, and removes generated files.

## Generated Files

Cluster files are written under:

```text
~/.k3s-vm-lab/generated/clusters/<cluster-name>/
```

The cluster index is written to:

```text
~/.k3s-vm-lab/generated/clusters.tsv
```

Important files:

- `build.log`
- `kubeconfig`
- `report.md`
- `cluster.env`
- `nodes.tsv`

The user kubeconfig is backed up before merge:

```text
~/.kube/config.k3s-vm-lab.<timestamp>.bak
```

The generated context is:

```text
k3s-vm-lab-<cluster-name>-<cluster-id>
```

## Development

```bash
make syntax
make test
```

`make test` uses mocked external commands and does not create real VMs.
