# Troubleshooting the lab itself

Start with `./lab.sh doctor`. It checks Docker, `kubectl`, `kind`, memory and the cluster.

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| `Cannot connect to the Docker daemon` | Docker is not running | Start Docker Desktop / Colima / the Docker service |
| Windows: anything not working | Windows needs WSL2 and Docker Desktop set up first | Follow `docs/windows-setup.md` and run the lab from an Ubuntu terminal |
| `setup` hangs on image pulls | Slow or blocked registry access | Retry; images are listed in `platform/images.txt` and can be pulled manually, then `kind load docker-image` |
| `setup` warns that an image is "not in the kind nodes" | The image could not be loaded or pulled (no internet, or a registry limit) | Connect to the internet and run `./lab.sh setup` again; it only fetches what is missing. `./lab.sh doctor` shows what is still missing and `.lab/images.log` has the details |
| Pods Pending with `Insufficient memory` on every incident | Docker has too little memory | Give Docker at least 4 GB |
| `kubectl` talks to the wrong cluster | Using your own terminal without flags | Use `./lab.sh shell`, or pass `--kubeconfig .lab/kubeconfig --context kind-incident-lab` |
| Validation fails straight after your fix | Rollout still in progress | Wait for `kubectl rollout status`, then validate again; validators retry for a while |
| Incident 29 reset is slow | The namespace is Terminating by design | Wait; `reset` strips the lab's finalizers |
| Incident 31 start takes minutes | The slow rollout is the incident | Expected: 3-4 minutes |
| Apple silicon / ARM | None expected | The images used are multi-arch |

The cluster is slow, pods stay Pending, or Docker runs out of memory: too many incidents are probably still running. Run `./lab.sh reset all` (removes every incident, keeps the cluster).

To start completely fresh: `./lab.sh destroy && ./lab.sh setup`.

---
(c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
