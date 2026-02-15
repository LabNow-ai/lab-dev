# logent (log-agent)

`logent` is a containerized logging control component designed to provide a unified log management layer across heterogeneous environments (bare-metal, Docker, Kubernetes).

It bundles:

- supervisord — process supervision
- logrotate — local log lifecycle management
- vector — log collection, transformation, and forwarding

## Purpose

logent serves as a log control plane inside containerized infrastructure.  
It separates application logging from log processing and routing logic.

The design goals are:

- Provide local log retention and compression
- Enable structured log collection and routing
- Maintain environment portability (VM / Docker / K8s)
- Avoid tight coupling with specific log backends

## Responsibilities

1. Local Log Lifecycle
   - Rotate logs on schedule
   - Compress and retain history
   - Prevent disk overflow

2. Log Pipeline
   - Collect from file or stdout
   - Apply transforms if required
   - Forward to one or multiple backends

3. Process Management
   - Ensure vector and auxiliary services are supervised
   - Maintain consistent runtime behavior

## Architecture Model

Application → Log file / stdout  
→ logent  
→ Backend (ClickHouse / Elasticsearch / PostgreSQL / S3 / etc.)

logent does not impose a specific storage backend.

## Deployment Modes

### Docker (Single Host)

- Mount application log directory
- Run logent container
- Configure vector sources and sinks

### Kubernetes

Two typical patterns:

- Sidecar mode (per Pod)
- DaemonSet mode (per Node)

logent can be adapted depending on cluster design.

## Why Not Rely Only on stdout?

While stdout-based logging is cloud-native friendly, certain environments require:

- Local compressed archives
- Regulatory retention
- Offline debugging capability

logent supports both file-based and stream-based workflows.

## Design Principles

- Decoupled from specific log storage
- Portable across environments
- Minimal assumptions about infrastructure
- Future-proof against backend replacement

## Notes

- Avoid embedding backend-specific logic in image name.
- Vector configuration should be externalized.
- logrotate configuration should be environment-aware.
