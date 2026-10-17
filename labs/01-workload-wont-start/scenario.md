# Incident 01 — The Workload Won't Start

| Level | Time | Area |
| --- | --- | --- |
| 1 / 5 | about 15 min | Workloads |

## The ticket

> **From:** release manager
> After this afternoon's release, `report-api` never becomes Ready. I think the cluster is under resource pressure — we should add nodes before the evening reports run.

Nobody has collected any capacity data yet. Treat the ticket as a theory, not a fact.

## What is deployed

- Deployment `report-api` (1 replica) in namespace `incident-01`
- The Pod that Deployment manages
- No Service, no database, no client Pod

## Your mission

1. Find the **earliest** point at which the workload fails.
2. Collect evidence for or against the "resource pressure" theory.
3. Restore the workload **without changing node capacity**.
4. Prove it works. `./lab.sh validate 1` inspects the running container, not just the Deployment's status.

## Done when

- `report-api` shows 1/1 Ready.
- You can state the root cause and show the single strongest piece of evidence.

## Ground rules

- Investigate before you change anything; write your hypothesis in `learner-notes.md` first.
- No unrelated edits. Do not scale or resize anything.
- Hints are free: `./lab.sh hint 1 1`.

## Where to start

```bash
kubectl get deployment,pods -n incident-01
kubectl describe pod -n incident-01 -l app=report-api
kubectl get events -n incident-01 --sort-by=.lastTimestamp
```

## When you are done

```bash
./lab.sh reset 1     # remove this incident from the cluster
```

Several incidents left running use memory. `./lab.sh reset all` removes every incident, and `./lab.sh destroy` deletes the whole cluster (`./lab.sh setup` rebuilds it).

---
(c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
