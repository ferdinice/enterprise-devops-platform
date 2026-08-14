# Monitoring and Observability

## 1. Purpose

The Enterprise DevOps Platform includes a Kubernetes-native monitoring and alerting stack based on the `kube-prometheus-stack`.

The monitoring layer provides visibility into:

* Kubernetes cluster health
* node resource utilization
* workload availability
* application and platform metrics
* alert conditions
* operational incidents

The core monitoring architecture is:

```text
Kubernetes Cluster
        |
        +-----------------------+
        |                       |
        v                       v
   Node Exporter        kube-state-metrics
        |                       |
        +-----------+-----------+
                    |
                    v
               Prometheus
                    |
          +---------+---------+
          |                   |
          v                   v
       Grafana           Alert Rules
                              |
                              v
                         Alertmanager
                              |
                              v
                            Slack
                      #devops-alerts
```

---

# 2. Technology Stack

The monitoring implementation uses:

```text
kube-prometheus-stack
├── Prometheus
├── Grafana
├── Alertmanager
├── Prometheus Operator
├── kube-state-metrics
└── Prometheus Node Exporter
```

The stack is installed using Helm from:

```text
prometheus-community/kube-prometheus-stack
```

The Helm repository is:

```text
https://prometheus-community.github.io/helm-charts
```

The Helm release name is:

```text
kube-prometheus-stack
```

and the components run inside:

```text
monitoring
```

namespace.

---

# 3. Monitoring Configuration

The main Helm configuration is stored in:

```text
platform/monitoring/values.yaml
```

Environment variables used by the installation and verification scripts are stored in:

```text
platform/monitoring/monitoring.env
```

Custom Prometheus alert rules are stored in:

```text
platform/monitoring/rules/platform-alerts.yaml
```

Operational scripts are:

```text
platform/monitoring/install.sh
platform/monitoring/verify.sh
platform/monitoring/uninstall.sh
```

---

# 4. Prometheus

Prometheus is the primary metrics collection and query engine.

It collects metrics from the Kubernetes environment and supporting exporters.

The platform exposes Prometheus through:

```text
https://prometheus.ferdeve.fit
```

The service remains a Kubernetes-managed service while external access is provided through NGINX Ingress.

The logical request path is:

```text
Engineer
   |
   v
prometheus.ferdeve.fit
   |
   v
Route 53
   |
   v
NGINX Ingress
   |
   v
Prometheus Service
   |
   v
Prometheus
```

---

# 5. Prometheus Retention

Prometheus is configured with:

```text
retention: 24h
```

This means the current implementation retains approximately 24 hours of Prometheus time-series data.

This is a deliberate portfolio and cost-control decision.

A larger production environment would normally require a longer retention strategy and potentially durable or external metrics storage.

---

# 6. kube-state-metrics

`kube-state-metrics` is enabled.

It exposes metrics derived from Kubernetes object state.

This allows Prometheus to observe information relating to resources such as:

```text
Deployments
Pods
ReplicaSets
Nodes
Namespaces
```

The custom `DeploymentUnavailable` alert relies on Kubernetes state metrics to determine whether a Deployment has unavailable replicas.

---

# 7. Node Exporter

Prometheus Node Exporter is enabled.

Node Exporter exposes operating-system and node-level metrics.

These include metrics relating to:

* CPU
* memory
* filesystem
* network
* system resources

The platform's `HighNodeCPU` alert uses metrics provided through this layer.

---

# 8. Prometheus Operator

The Prometheus Operator is enabled as part of the monitoring stack.

It manages Kubernetes-native monitoring resources including:

```text
Prometheus
Alertmanager
PrometheusRule
```

This allows monitoring configuration to be expressed through Kubernetes custom resources rather than manually maintaining individual Prometheus configuration files.

---

# 9. Grafana

Grafana provides the visualization layer.

The platform exposes Grafana at:

```text
https://grafana.ferdeve.fit
```

The request path is:

```text
Engineer
   |
   v
grafana.ferdeve.fit
   |
   v
Route 53
   |
   v
NGINX Ingress
   |
   v
Grafana Service
   |
   v
Grafana
```

Grafana uses:

```text
service:
  type: ClusterIP
```

The Grafana service therefore does not require its own AWS public LoadBalancer.

External access is handled through the shared NGINX Ingress layer.

---

# 10. Grafana Resources

Grafana currently requests:

```text
CPU:    100m
Memory: 128Mi
```

with limits of:

```text
CPU:    500m
Memory: 512Mi
```

These limits help prevent the monitoring dashboard from consuming uncontrolled cluster resources.

---

# 11. Grafana Persistence

Grafana persistence is currently:

```text
enabled: false
```

This means the current project does not provide durable Grafana storage.

This is acceptable for the current portfolio environment but represents a deliberate trade-off.

For a long-lived production implementation, persistent storage should be considered for Grafana state that must survive pod replacement.

---

# 12. Monitoring Ingress

Both Grafana and Prometheus use:

```text
ingressClassName: nginx
```

Therefore the existing NGINX Ingress Controller provides external routing for the monitoring stack.

The architecture avoids provisioning separate public load balancers for each monitoring service.

Conceptually:

```text
Internet
   |
   v
NGINX Ingress
   |
   +----> Grafana
   |
   +----> Prometheus
```

---

# 13. Monitoring TLS

Both public monitoring endpoints use TLS.

Grafana uses:

```text
grafana-tls
```

Prometheus uses:

```text
prometheus-tls
```

Both ingresses reference:

```text
cert-manager.io/cluster-issuer:
letsencrypt-production
```

cert-manager therefore handles certificate issuance using the existing Let's Encrypt production ClusterIssuer.

---

# 14. HTTPS Enforcement

The monitoring ingresses contain:

```text
nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

This forces HTTP requests toward HTTPS.

The external monitoring endpoints are therefore designed to operate over encrypted HTTPS connections.

---

# 15. Alertmanager

Alertmanager handles alerts generated from Prometheus alert rules.

The platform runs:

```text
1 Alertmanager replica
```

The basic alert path is:

```text
Prometheus
    |
    v
PrometheusRule
    |
    v
Alert generated
    |
    v
Alertmanager
    |
    v
Slack
```

---

# 16. Alert Grouping

Alertmanager groups alerts using:

```text
alertname
namespace
```

This helps prevent every matching alert from being treated as an unrelated notification.

The configured timings are:

```text
group_wait:      30s
group_interval:  5m
repeat_interval: 4h
```

The initial notification is therefore delayed briefly to allow related alerts to be grouped.

Repeated notifications for an unresolved alert are spaced according to the configured repeat interval.

---

# 17. Slack Integration

The default Alertmanager receiver is:

```text
slack
```

Alerts are routed to:

```text
#devops-alerts
```

The Slack message contains information including:

```text
Status
Severity
Namespace
Summary
Description
```

This provides operational context directly inside the notification.

---

# 18. Resolved Notifications

Slack configuration includes:

```text
send_resolved: true
```

Therefore Alertmanager can send both:

```text
FIRING
```

and:

```text
RESOLVED
```

notifications.

This means the notification workflow does not only report when an incident starts; it can also report when the alert condition clears.

---

# 19. Slack Webhook Security

The Slack webhook is not stored directly inside `values.yaml`.

The monitoring installation creates a Kubernetes Secret named:

```text
slack-webhook
```

Alertmanager references the webhook through:

```text
/etc/alertmanager/secrets/slack-webhook/url
```

This avoids embedding the webhook URL directly inside the Helm values file committed to Git.

---

# 20. Watchdog Handling

The standard Prometheus `Watchdog` alert is explicitly routed to:

```text
receiver: "null"
```

This prevents the continuously active Watchdog alert from generating unnecessary Slack notifications in the portfolio environment.

Other alerts continue to use the Slack receiver.

---

# Custom Platform Alerts

## 21. PrometheusRule

Custom platform alerts are defined using:

```text
kind: PrometheusRule
```

The resource is:

```text
platform-alerts
```

inside:

```text
monitoring
```

namespace.

The rules are grouped under:

```text
platform.rules
```

---

# 22. DeploymentUnavailable Alert

The first custom alert is:

```text
DeploymentUnavailable
```

Its expression checks:

```text
kube_deployment_status_replicas_unavailable > 0
```

The condition must remain true for:

```text
5 minutes
```

before the alert fires.

Severity is:

```text
warning
```

The purpose is to identify Kubernetes Deployments that cannot maintain their expected replicas.

Conceptually:

```text
Deployment
     |
     v
Unavailable replica detected
     |
     | persists for 5 minutes
     v
DeploymentUnavailable
     |
     v
Alertmanager
     |
     v
Slack
```

---

# 23. HighNodeCPU Alert

The second custom rule is:

```text
HighNodeCPU
```

The rule calculates CPU utilization from:

```text
node_cpu_seconds_total
```

and triggers when CPU utilization exceeds:

```text
85%
```

for:

```text
5 minutes
```

Severity is:

```text
warning
```

This prevents a short CPU spike from immediately generating an operational alert.

The condition must persist before Alertmanager receives the alert.

---

# Monitoring Installation

## 24. Installation Preconditions

Before installing monitoring, `install.sh` checks that required commands are available:

```text
helm
kubectl
```

It also verifies connectivity to the Kubernetes cluster.

---

# 25. Ingress Dependency

The installer verifies that the configured NGINX IngressClass exists before proceeding.

The expected class is:

```text
nginx
```

If the ingress layer is unavailable, monitoring installation does not blindly continue.

---

# 26. Certificate Dependency

The installer checks the configured ClusterIssuer:

```text
letsencrypt-production
```

and verifies that it is ready.

This protects the deployment from progressing into HTTPS configuration when the certificate infrastructure is not operational.

---

# 27. Namespace Creation

The installer ensures the namespace:

```text
monitoring
```

exists.

The operation is designed to be repeatable rather than assuming a completely empty cluster.

---

# 28. Slack Secret Creation

During installation, the Slack webhook is converted into the Kubernetes Secret:

```text
slack-webhook
```

The installer then confirms that the Secret is present before proceeding.

---

# 29. Helm Repository

The installer checks for the Prometheus Community Helm repository.

If necessary, it adds the repository and then performs:

```text
helm repo update
```

This ensures the chart repository metadata is available before installation.

---

# 30. Helm Rendering Validation

Before installing the monitoring release, the script performs Helm rendering checks using:

```text
helm template
```

This provides an early validation layer.

The purpose is to catch invalid chart configuration before modifying the Kubernetes cluster.

The flow is:

```text
values.yaml
    |
    v
helm template
    |
 PASS?
 /   \
NO   YES
|     |
X     v
Stop Install
```

---

# 31. Helm Deployment

After validation, monitoring is deployed using:

```text
helm upgrade --install
```

This allows the same installation workflow to support both initial installation and subsequent configuration updates.

---

# 32. PrometheusRule CRD

The installer waits for:

```text
prometheusrules.monitoring.coreos.com
```

to become established.

Only after the CRD is available does the installer apply:

```text
platform-alerts.yaml
```

This prevents the custom PrometheusRule from being submitted before Kubernetes understands that resource type.

---

# Monitoring Verification

## 33. Verification Script

Monitoring verification is performed through:

```text
platform/monitoring/verify.sh
```

The verification script does not rely on a single check.

It performs multiple checks and tracks failures before returning the final result.

---

# 34. Helm Release Verification

The script checks the Helm release:

```text
kube-prometheus-stack
```

to confirm that the release exists in the expected namespace.

---

# 35. Pod Verification

The script inspects monitoring namespace pods.

It checks whether the expected pods exist and whether they are ready.

This provides runtime validation beyond simply confirming that Helm accepted the installation.

---

# 36. Prometheus Verification

The verification process confirms that the Prometheus custom resource exists.

This demonstrates that the Prometheus Operator successfully created the expected monitoring resource.

---

# 37. Grafana Verification

The script locates the Grafana service using Kubernetes labels and confirms that the service exists.

---

# 38. Ingress Verification

The script verifies the expected ingress hostnames for:

```text
kube-prometheus-stack-grafana
```

and:

```text
kube-prometheus-stack-prometheus
```

against the configured external hostnames.

This helps detect routing configuration mistakes.

---

# 39. TLS Secret Verification

The script checks that:

```text
grafana-tls
prometheus-tls
```

exist.

This verifies that the expected TLS Secrets have been created for the monitoring endpoints.

The top-level platform deployment additionally waits for the corresponding cert-manager Certificate resources to reach `Ready`.

---

# 40. kube-state-metrics Verification

The verification script confirms that the kube-state-metrics Deployment exists.

This matters because Kubernetes object-state alerts depend on the metrics it exposes.

---

# 41. Node Exporter Verification

The script confirms the Prometheus Node Exporter DaemonSet exists.

Running Node Exporter as a DaemonSet allows node-level metrics collection across Kubernetes worker nodes.

---

# 42. Alertmanager Verification

The script checks the Alertmanager custom resource and inspects its readiness-related status.

This provides stronger verification than simply checking whether an Alertmanager object exists.

---

# 43. Slack Secret Verification

The script verifies that:

```text
slack-webhook
```

exists inside the monitoring namespace.

This confirms that Alertmanager's external notification dependency is present.

---

# 44. Alert Rule Verification

The verification script checks for:

```text
PrometheusRule/platform-alerts
```

This confirms that the custom operational alert rules were successfully installed.

---

# 45. Verification Result

The script tracks failed checks.

If no failures are found, verification succeeds.

If one or more checks fail, the script reports the number of detected problems and returns a failure.

This allows the monitoring verification script to be used by the top-level platform deployment process.

---

# Platform Integration

## 46. Top-Level Deployment

Monitoring is integrated into:

```text
deploy-platform.sh
```

The top-level workflow now performs:

```text
Core Kubernetes Platform
        |
        v
NGINX / DNS / TLS
        |
        v
ArgoCD
        |
        v
Monitoring Installation
        |
        v
Grafana + Prometheus DNS
        |
        v
TLS Certificate Readiness
        |
        v
Monitoring Verification
        |
        v
Platform Deployment Complete
```

Monitoring therefore no longer requires a separate manual installation after the main platform deployment.

---

# 47. Platform Destruction

Monitoring is also integrated into:

```text
destroy-platform.sh
```

During teardown, monitoring-related DNS records are removed and the monitoring stack is uninstalled before the underlying Kubernetes platform is destroyed.

The relevant lifecycle is:

```text
Grafana DNS
      |
      v
Prometheus DNS
      |
      v
Monitoring Stack
      |
      v
Remaining Platform Services
      |
      v
KOps Cluster
```

This creates a cleaner reverse dependency teardown.

---

# Resource Strategy

## 48. Prometheus Resources

Prometheus requests:

```text
CPU:    200m
Memory: 512Mi
```

with limits of:

```text
CPU:    1000m
Memory: 1Gi
```

This places boundaries around Prometheus resource consumption in the portfolio cluster.

---

# 49. Cost and Durability Trade-Offs

The current monitoring implementation deliberately favors a portfolio/lab operating model.

Important decisions include:

```text
Prometheus retention: 24 hours
Grafana persistence:  disabled
Alertmanager replicas: 1
```

These choices reduce resource usage and complexity.

They also mean the current implementation should not be presented as a highly available, long-retention enterprise observability platform.

A larger production implementation could introduce:

* persistent storage
* longer metrics retention
* highly available Alertmanager
* highly available Prometheus
* remote metrics storage
* backup strategy
* stronger monitoring access controls

The current implementation demonstrates the architecture and operational workflow while controlling infrastructure cost.

---

# 50. Failure Scenarios

### Prometheus unavailable

Metrics collection, alert evaluation, and Prometheus querying are affected.

Existing application workloads continue running independently.

### Grafana unavailable

Dashboards become unavailable, but Prometheus can continue collecting metrics.

### Alertmanager unavailable

Prometheus can continue evaluating rules, but Slack alert delivery is affected.

### Slack unavailable

Monitoring continues internally, but engineers may not receive Slack notifications.

### Node Exporter unavailable

Node-level visibility becomes incomplete.

### kube-state-metrics unavailable

Kubernetes object-state visibility becomes incomplete and rules depending on those metrics may stop evaluating correctly.

---

# 51. Monitoring Responsibility Separation

Each component has a distinct role:

```text
Node Exporter
    = node metrics

kube-state-metrics
    = Kubernetes object-state metrics

Prometheus
    = collection, storage, querying and rule evaluation

Grafana
    = visualization

Alertmanager
    = alert grouping and routing

Slack
    = engineer notification
```

This separation makes troubleshooting easier because each layer has a clear responsibility.

---

# 52. Observability Summary

The Enterprise DevOps Platform monitoring implementation provides:

* Kubernetes-native monitoring
* Prometheus metrics collection
* node-level metrics
* Kubernetes object-state metrics
* Grafana visualization
* custom Prometheus alert rules
* Alertmanager routing
* Slack notifications
* resolved-alert notifications
* NGINX-based ingress
* HTTPS through cert-manager
* installation precondition checks
* Helm rendering validation
* runtime verification
* automated top-level deployment
* automated teardown integration

The resulting flow is:

```text
Infrastructure + Kubernetes + Application
                 |
                 v
              Metrics
                 |
                 v
             Prometheus
              /      \
             /        \
            v          v
        Grafana     Alert Rules
                       |
                       v
                  Alertmanager
                       |
                       v
                     Slack
```

This gives the platform visibility across infrastructure and Kubernetes workload health while maintaining a clear separation between metrics collection, visualization, alert evaluation, and notification.
