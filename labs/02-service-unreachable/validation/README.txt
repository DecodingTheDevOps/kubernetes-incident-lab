./lab.sh validate 2

Checks: Deployment web still has 2 ready replicas, the Service still selects app=web, the EndpointSlice
has at least 2 ready endpoints on port 80, and wget from web-client to http://web succeeds.

Copyright (c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
