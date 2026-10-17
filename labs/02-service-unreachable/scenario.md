# Incident 02 — The Service Is Unreachable

| Level | Time | Area |
| --- | --- | --- |
| 2 / 5 | about 20 min | Networking |

## The ticket

> **From:** web team
> Requests to the in-cluster Service `web` have been failing since this morning's deployment. Both web replicas show `Running`, so on-call has paged the networking team.

## What is deployed

- Deployment `web` (2 replicas), Service `web`, and a client Pod `web-client` — all in `incident-02`

## Your mission

1. From **inside the cluster**, call the Service from `web-client` and capture the exact error.
2. Trace the request path from client to server Pods and find the **first** link that is broken.
3. Make the smallest change that restores the path.

## Done when

- A request from `web-client` to `http://web` returns an HTTP response.
- Both replicas are still serving traffic behind the Service.

## Ground rules

- Test from `web-client`, not from your laptop.
- Record evidence before changing any resource.
- Do not replace networking components until you have proved they are the failing layer.

## Where to start

```bash
kubectl get deployment,service,pods -n incident-02
kubectl exec -n incident-02 pod/web-client -- wget -T 3 -O- http://web
```

## When you are done

```bash
./lab.sh reset 2     # remove this incident from the cluster
```

Several incidents left running use memory. `./lab.sh reset all` removes every incident, and `./lab.sh destroy` deletes the whole cluster (`./lab.sh setup` rebuilds it).

---
(c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
