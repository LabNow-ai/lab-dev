# Docker Clash Transparent Egress Gateway

This project provides a Dockerized Clash instance configured as a **Transparent Egress Gateway**. It addresses the challenge of selectively routing traffic from specific Docker/Kubernetes workloads through a proxy, rather than forcing all traffic on the host or all workloads through it. This approach is more aligned with modern service mesh and enterprise gateway designs.

## I. Overall Architecture

The recommended architecture is a **Transparent Egress Gateway**.

```text
                        Internet
                            │
                ┌─────────────────────┐
                │  Proxy Provider(s)  │
                └─────────────────────┘
                            │
                     Clash Meta Gateway
                  (Rule Engine + DNS + TProxy)
                            ▲
                            │
                nftables / Policy Routing
                            ▲
                            │
                    Linux Host Network
                            ▲
                            │
      ┌─────────────────────┴─────────────────────┐
      │                                           │
 docker bridge: net-proxy                  docker default
      │                                           │
      │                                           │
 OpenClaw                                    PostgreSQL
 Browser                                     Redis
 AI Agent                                    MinIO
 Playwright                                  ElasticSearch
```

**Key Points:**

*   **Host Traffic**: The host's own traffic **will not** pass through Clash.
*   **Targeted Proxying**: Only containers connected to the `net-proxy` Docker bridge will have their traffic routed through Clash.

## II. Traffic Flow

**For containers on `net-proxy` (e.g., OpenClaw):**

```text
OpenClaw
↓
eth0
↓
docker bridge(net-proxy)
↓
Host nftables
↓
TPROXY
↓
Clash Container
↓
Rule Engine
↓
DIRECT
或
Proxy
↓
Internet
```

**For Host traffic (e.g., Host curl):**

```text
Host curl
↓
eth0
↓
Internet
```

Host traffic will **not** enter Clash.

## III. Why Not TUN?

TUN (Tunnel) mode modifies the **default route of the entire network namespace**. This means all traffic within that namespace is routed through the TUN device. This approach is generally not suitable for server environments where only a subset of containers needs proxying, as it affects the entire host or container's network stack.

## IV. Host Responsibilities

The host's role is minimal and focused on traffic redirection:

*   **Matching**: Identify traffic originating from the `net-proxy` interface (e.g., `iifname=docker-net-proxy`).
*   **Forwarding**: Transparently forward this matched traffic using TPROXY to Clash's designated port (e.g., `7890`).
*   **Restoration**: The host does not concern itself with the ultimate destination (e.g., `google`, `github`, `chatgpt`); it only knows to send the traffic to Clash.

## V. Clash Responsibilities

Clash is solely responsible for the **rule engine** and proxy logic. For example:

```yaml
DOMAIN-SUFFIX,openai.com,Proxy
DOMAIN-SUFFIX,github.com,DIRECT
GEOIP,CN,DIRECT
MATCH,Proxy
```

All business logic related to traffic routing (Proxy or Direct) resides within Clash. The host remains unaware of these specific rules.

## VI. DNS

It is recommended that all containers on the `net-proxy` network use Clash's DNS server (e.g., `172.30.0.2`). This ensures consistent DNS resolution and allows Clash's Fake-IP and rule engine to function correctly:

```text
Container
↓
Fake-IP
↓
Rule
↓
Proxy/DIRECT
```

This approach prevents DNS pollution on the host.

## VII. Docker Compose Integration

For any container requiring proxying, simply add it to the `net-proxy` network in your `docker-compose.yml`:

```yaml
services:
  openclaw:
    networks:
      - default
      - net-proxy
```

This eliminates the need for `HTTP_PROXY`, `SOCKS_PROXY`, or `ALL_PROXY` environment variables within the application containers.

## VIII. Gateway Container Enhancements

LabNow's Clash image should be enhanced with Gateway capabilities. The `entrypoint` script should perform the following steps:

1.  Start Clash.
2.  Install `nftables`.
3.  Enable IP forwarding.
4.  Enable masquerading.
5.  Wait for the Docker Bridge to be ready.

This keeps the user's `docker-compose.yml` concise.

## IX. Applicability to Kubernetes

This architecture is **highly applicable to Kubernetes, and even more naturally so**.

In Kubernetes, all traffic from a Pod naturally flows through the CNI (Container Network Interface) on the Node. Therefore, there's no need for Docker Bridge specific configurations.

For example:

```text
Pod
↓
Calico
↓
Node
↓
TPROXY
↓
Clash
↓
Internet
```

This allows for policy-based routing. For instance, by labeling a Namespace (e.g., `metadata: labels: proxy: enabled`), NetworkPolicy or CNI can direct traffic from these Pods to the Gateway.

Alternatively, a DaemonSet can deploy Clash on each Node, similar to an Istio Sidecar, but with a single Gateway per Node, rather than per Pod, to optimize resource usage.

## X. Sidecar vs. Node Gateway

**Avoid a Sidecar approach** where each Pod has its own Clash instance. This leads to significant resource waste (e.g., 100 Pods = 100 Clash instances).

Instead, a **Node-level Gateway** is recommended:

```text
Node A
↓
Clash
↓
20 Pods

Node B
↓
Clash
↓
18 Pods
```

This resembles an Istio Egress Gateway, providing a centralized proxy for multiple Pods on a Node.

## XI. Long-term Evolution for LabNow

For LabNow as an AI Agent platform, it's recommended to define this component not merely as "Clash" but as a more generic **Egress Gateway**. Its overall responsibilities can be broken down as follows:

```
                LabNow Egress Gateway
┌──────────────────────────────────────────────┐
│ DNS（Fake-IP、DoH、DoQ）                     │
├──────────────────────────────────────────────┤
│ Transparent Proxy（TPROXY / REDIRECT）       │
├──────────────────────────────────────────────┤
│ Rule Engine（Clash Meta）                    │
├──────────────────────────────────────────────┤
│ Proxy Provider（订阅、健康检查、负载均衡）     │
├──────────────────────────────────────────────┤
│ Egress Policy（按 Namespace、Tenant、App）   │
├──────────────────────────────────────────────┤
│ Metrics（Prometheus）、Audit、Tracing        │
└──────────────────────────────────────────────┘
```

This elevates its positioning from a "proxy tool" to a **unified Egress Gateway for AI workloads**. This architecture is consistent with the design principles of Istio Egress Gateway, Cilium Egress Gateway, and Calico Egress Gateway, making it suitable for both standalone Docker and seamless migration to Kubernetes without modifying application code in business containers or Pods.
