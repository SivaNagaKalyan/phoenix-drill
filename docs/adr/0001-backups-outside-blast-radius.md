# ADR 0001: Backups live outside the blast radius

**Status:** Accepted

## Context

The drill deletes the entire cluster. Any backup stored inside the cluster (on a PersistentVolume, in an in-cluster object store, or as a VolumeSnapshot tied to the cluster) is deleted with it. That is the most common way real disaster recovery plans fail: the backup shares a failure domain with the thing it protects.

## Decision

Backups go to S3-compatible object storage that runs outside the cluster, with its own lifecycle. The cluster only holds credentials to reach it. `scripts/cluster.sh down` cannot touch it; only an explicit `scripts/vault.sh down --purge` can.

## Consequences

* Deleting the cluster is always safe with respect to backups, which is what makes a weekly destructive drill acceptable.
* The vault endpoint changes when the docker network is recreated, so the endpoint is written into a Secret at deploy time instead of being hard-coded.
* In a real cloud the same principle means a separate account or project, versioning, object lock, and cross-region replication. A single bucket in the same account is still inside the blast radius of a compromised credential.
