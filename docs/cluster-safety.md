# Cluster Safety

The lab uses its own kind cluster (`incident-lab`, context `kind-incident-lab`) and its own kubeconfig at `.lab/kubeconfig`. `lab.sh` never reads or writes your normal `~/.kube/config`, and every command it runs names that kubeconfig and context explicitly.

## The safe way to type your own kubectl commands

```bash
./lab.sh shell
```

This opens a sub-shell (your usual bashrc still loads) in which `KUBECONFIG` points at the lab and the prompt shows `(incident-lab)`. Type `exit` to leave; nothing changes in your normal shell.

## If you prefer your own terminal

Pass the flags yourself: `kubectl --kubeconfig .lab/kubeconfig --context kind-incident-lab get pods -A`.

## Rules the product follows

- Incident namespaces are named `incident-NN`; `reset <n>` and `reset all` only delete those (plus the few cluster-scoped objects an incident created).
- Incidents 10, 21 and 22 touch cluster-scoped objects (a Pod request sized to the node, one PersistentVolume, a Terminating namespace). All are inside the disposable kind cluster and are removed by `./lab.sh reset <n>`.
- Never point a lab command at a shared or production cluster. `./lab.sh doctor` prints which context it is using.

---
(c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
