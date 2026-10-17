# How to work an incident (the method behind the lab)

Every incident can be solved with the same loop. Practise the loop, not the answers.

1. **State the symptom in one sentence.** What does the user or the system do that is wrong? Not "the Pod is broken": "requests to /checkout time out."
2. **Find the first layer that is wrong.** Walk the path: object exists? -> controller created children? -> Pod scheduled? -> container started? -> process healthy? -> Service has endpoints? -> traffic arrives?
3. **Read evidence in this order:** `kubectl get` (state) -> `kubectl describe` (events, conditions) -> `kubectl logs` and `--previous` -> the *owner chain* (Deployment -> ReplicaSet -> Pod) -> the objects those messages name (quota, limit range, secret, role).
4. **Form one hypothesis, change one thing, observe.** Two simultaneous changes teach nothing.
5. **Expect more than one cause.** When a fix produces a new, different symptom, you have not failed: you removed the first layer. Levels 3-5 are built like this.
6. **Fix the cause, not the evidence.** Deleting the probe, raising the quota or granting cluster-admin makes the symptom go away and the risk stay. The validators reject those.
7. **Write it down.** The learner notes and the post-mortem template (Pro) are part of the skill.

## Time boxes

Level 1-2: 10-20 min. Level 3: 25-35. Level 4-5: 35-45. After the time box, take hint 1, not the solution.

---
(c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
