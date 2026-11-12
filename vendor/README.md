# Vendored snapshots

`eu-ec-detect-community/` and `eu-wazuh-detections/` are snapshots of the companion repositories at the time this installer was published. They are included so `./install.sh` and a Docker build can run without reaching the network, including when those repositories are still private.

They are licensed under Apache-2.0, Copyright 2026 EmpowerU LLC.

When the companion repositories move forward, refresh these trees and record the source commit in `SNAPSHOT.txt`.
