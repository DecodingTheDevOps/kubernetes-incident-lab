./lab.sh validate 1

Checks: the ConfigMap exists with a 'mode' key, the Deployment is fully rolled out (1 updated, 1 ready),
and inside the running container REPORT_MODE is set and /etc/report-settings/mode is present.
Node capacity is not part of the check because it was never the problem to solve.

Copyright (c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
