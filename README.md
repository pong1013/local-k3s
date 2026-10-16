# local-k3s

`local-k3s` is a VM-backed local k3s lab installer. It creates Multipass VM nodes through `chien-dev`, installs a `1 server + N workers` k3s cluster, merges kubeconfig into `~/.kube/config`, optionally installs `fake-gpu-operator`, Prometheus monitoring, and cert-manager, and writes a Markdown report.

This project is intentionally not a generic k3s builder. It is an all-in-one local lab package for people who do not want to prepare instances or VMs by hand.

## Requirements

- macOS or Linux
- Git (for installation)
- `chien-dev` from [dev-environment-setup](https://github.com/pong1013/dev-environment-setup)
- Multipass
- OpenSSH client
- `kubectl`
- `helm` if installing any optional add-on (`fake-gpu-operator`, Prometheus monitoring, or cert-manager)

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

| Command | Description |
| --- | --- |
| `local-k3s doctor` | Check required tools and host prerequisites. |
| `local-k3s create my-lab` | Interactively configure and create a cluster. |
| `local-k3s status my-lab` | Show cluster and Kubernetes health. |
| `local-k3s status my-lab wide` | Show status with additional Kubernetes node details. |
| `local-k3s report my-lab` | Show the saved cluster configuration, paths, and useful commands. |
| `local-k3s start my-lab` | Start the cluster VMs and wait for Kubernetes nodes to become Ready. |
| `local-k3s stop my-lab` | Stop the cluster VMs while preserving cluster data and kubeconfig. |
| `local-k3s delete my-lab` | Permanently delete the cluster VMs, generated files, and managed kubeconfig entries. |
| `local-k3s update` | Fetch `origin/main`, show installed and remote commit IDs, and align the installed checkout when they differ. Overwrites tracked local changes and local commits; preserves untracked cluster data under `generated/`. A fetch failure leaves the installed revision unchanged. |

The installed checkout defaults to `~/.k3s-vm-lab`; set `K3S_VM_LAB_INSTALL_DIR` to use a different directory for `update`.

### During `create`, the CLI asks for

**Required cluster settings**

- Cluster name, if not provided in the command.
- Total node count, including the fixed `1 control-plane/server` node.
- Ubuntu version for all VM nodes.
- Resource size for each node: CPU, RAM, and disk, using a preset or custom values.

**Optional add-ons — one multi-select question**

- Fake GPU Operator
- Monitoring Stack (Prometheus, Grafana, Alertmanager, Operator)
- cert-manager

Enter space-separated numbers such as `1 3`, or press Enter to skip all add-ons. Selected add-ons require Helm. See the cluster report for installation results and the build log for diagnostics.

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
Select optional add-ons:
  1) Fake GPU Operator — simulate GPU resources
  2) Monitoring Stack (Prometheus, Grafana, Alertmanager, Operator)
  3) cert-manager — TLS certificate management
Enter option numbers (space-separated; Enter skips all): 1 3
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
