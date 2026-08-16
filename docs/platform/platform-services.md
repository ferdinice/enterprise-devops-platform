# Platform Services

## 1. Purpose

The Enterprise DevOps Platform runs several shared Kubernetes services that provide application delivery, ingress routing, TLS certificate management, GitOps deployment, monitoring, visualization, and alerting.

The platform services are maintained under:

```text
platform/
├── argocd/
├── cert-manager/
├── dns/
├── ingress-nginx/
└── monitoring/
```

Each component has a specific responsibility and is managed independently through installation, verification, and removal scripts.

The platform is designed so that infrastructure is created first, followed by Kubernetes platform services, and finally application workloads.

---

## 2. Platform Architecture

The simplified runtime architecture is:

```text
                         Internet
                            |
                            v
                        Route 53
                            |
                            v
                    AWS Load Balancer
                            |
                            v
                  NGINX Ingress Controller
                            |
              +-------------+-------------+
              |             |             |
              v             v             v
             Dev         Staging         Prod
              |             |             |
              +-------------+-------------+
                            |
                            v
                  Pet Adoption Services
                            |
                            v
                  Pet Adoption Pods


     GitHub
        |
        v
      ArgoCD
        |
        v
 Kubernetes Desired State


 Kubernetes Metrics
        |
        v
    Prometheus
        |
        +----------> Grafana
        |
        v
   Alertmanager
        |
        v
      Slack
```

These services are shared by the application environments running in the Kubernetes cluster.

---

## 3. Platform Deployment Order

Platform services have dependencies and therefore should not be installed randomly.

The logical deployment sequence is:

```text
Kubernetes Cluster
        |
        v
NGINX Ingress Controller
        |
        v
cert-manager
        |
        v
DNS Configuration
        |
        v
ArgoCD
        |
        v
Application Workloads
        |
        v
Monitoring Stack
```

The repository also contains the top-level:

```text
deploy-platform.sh
destroy-platform.sh
```

These scripts provide centralized orchestration for platform lifecycle operations.

Individual components still maintain their own scripts so they can be installed, verified, or removed independently.

---

# NGINX Ingress Controller

## 4. Purpose of NGINX Ingress

Kubernetes Services provide internal service discovery, but the application requires controlled access from outside the cluster.

The NGINX Ingress Controller provides this entry point.

It watches Kubernetes Ingress resources and translates their rules into traffic-routing configuration.

The component is maintained under:

```text
platform/ingress-nginx/
```

The directory includes:

```text
ingress.env
install.sh
uninstall.sh
values.yaml
verify.sh
```

---

## 5. External Traffic Flow

Application traffic follows approximately:

```text
User
 |
 v
DNS
 |
 v
AWS Load Balancer
 |
 v
NGINX Ingress Controller
 |
 v
Ingress Rule
 |
 v
Kubernetes Service
 |
 v
Application Pod
```

The AWS Load Balancer provides the external network entry point.

NGINX then performs Layer 7 routing inside the Kubernetes platform.

---

## 6. Host-Based Routing

Separate hostnames allow the three application environments to coexist inside the same cluster.

```text
dev.petadoption.ferdeve.fit
        |
        v
pet-adoption-dev


staging.petadoption.ferdeve.fit
        |
        v
pet-adoption-staging


petadoption.ferdeve.fit
        |
        v
pet-adoption-prod
```

This gives each environment an independent endpoint while allowing them to share the platform ingress infrastructure.

---

# cert-manager

## 7. Purpose of cert-manager

cert-manager automates TLS certificate management inside Kubernetes.

The component is maintained under:

```text
platform/cert-manager/
```

Its configuration includes installation scripts, verification scripts, Helm values, issuer configuration, and certificate-related manifests.

Without cert-manager, certificates would need to be requested, stored, configured, renewed, and replaced manually.

---

## 8. Let's Encrypt Integration

The project contains both Let's Encrypt staging and production issuer configurations.

```text
letsencrypt-staging.yaml
letsencrypt-production.yaml
```

The staging issuer is useful when testing certificate configuration because Let's Encrypt applies stricter rate limits to production certificate requests.

Once the configuration is proven, the production issuer can be used for trusted certificates.

---

## 9. Certificate Flow

The simplified certificate flow is:

```text
Ingress
   |
   | requests certificate
   v
cert-manager
   |
   v
ClusterIssuer
   |
   v
Let's Encrypt
   |
   v
Domain Validation
   |
   v
Certificate Issued
   |
   v
Kubernetes TLS Secret
   |
   v
NGINX Ingress
   |
   v
HTTPS
```

This allows public application and platform endpoints to use encrypted HTTPS traffic.

---

# DNS

## 10. DNS Management

DNS-related automation is stored under:

```text
platform/dns/
```

The directory contains scripts such as:

```text
create-alias-record.sh
delete-alias-record.sh
verify-dns.sh
```

along with:

```text
dns.env
```

The DNS layer connects public hostnames to the AWS entry point created for the Kubernetes ingress infrastructure.

---

## 11. Why DNS Is Separate

DNS is treated separately from NGINX because the two components solve different problems.

Route 53 answers:

> Where should the client send the request?

NGINX answers:

> Once the request reaches the Kubernetes platform, which service should receive it?

The flow is therefore:

```text
Hostname
   |
   v
Route 53
   |
   v
AWS Load Balancer
   |
   v
NGINX
   |
   v
Kubernetes Service
```

---

# ArgoCD

## 12. Purpose of ArgoCD

ArgoCD provides Continuous Delivery through the GitOps model.

It is maintained under:

```text
platform/argocd/
```

The ArgoCD platform directory contains installation, configuration, verification, and removal logic.

Application definitions themselves are maintained separately under:

```text
gitops/applications/
```

This distinction is important.

```text
platform/argocd/
```

installs and manages the **ArgoCD platform**.

```text
gitops/applications/
```

defines **what ArgoCD should deploy**.

They are related, but they are not duplicates.

---

## 13. GitOps Model

Instead of Jenkins directly deploying application manifests into Kubernetes, Git acts as the desired-state source.

The deployment relationship is:

```text
Jenkins
   |
   | updates image tag
   v
Git Repository
   |
   | watched by
   v
ArgoCD
   |
   | reconciles
   v
Kubernetes
```

This separates CI from CD.

Jenkins is responsible for producing and validating the artifact.

ArgoCD is responsible for reconciling the desired application state into Kubernetes.

---

## 14. ArgoCD Applications

The consolidated repository contains separate ArgoCD Application resources:

```text
gitops/applications/
├── pet-adoption-dev.yaml
├── pet-adoption-staging.yaml
└── pet-adoption-prod.yaml
```

Each points to a different Kustomize overlay.

```text
DEV
gitops/pet-adoption/overlays/dev

STAGING
gitops/pet-adoption/overlays/staging

PRODUCTION
gitops/pet-adoption/overlays/prod
```

This provides independent desired state for each environment.

---

## 15. Environment Synchronization Strategy

Development and Staging use automated synchronization.

This allows ArgoCD to reconcile changes automatically when their desired state changes in Git.

Production is intentionally more controlled.

The production Application does not use the same automatic synchronization policy as Development and Staging.

This creates an additional deployment-control boundary before production changes are applied.

---

# Application Environments

## 16. Environment Model

The Pet Adoption application uses three environments:

```text
Development
Staging
Production
```

Each environment has its own Kubernetes namespace:

```text
pet-adoption-dev
pet-adoption-staging
pet-adoption-prod
```

and its own Kustomize overlay.

---

## 17. Build Once, Promote the Same Artifact

One of the most important design principles in the platform is that Production should not receive a newly rebuilt version of the application.

The intended flow is:

```text
Source Code
    |
    v
Jenkins Build
    |
    v
Container Image
    |
    v
ECR
    |
    v
Development
    |
    v
Staging
    |
    v
Production
```

The same immutable ECR image tag is promoted between environments.

For example:

```text
build-2-4dad0b1
```

can move through:

```text
DEV
  ↓
STAGING
  ↓
PRODUCTION
```

without rebuilding the application.

This reduces the risk of Production running an artifact different from the one tested in Staging.

---

## 18. Promotion Scripts

Environment promotion is supported by:

```text
scripts/promote-to-staging.sh
scripts/promote-to-prod.sh
```

The staging promotion takes the image version already running in Development and updates Staging to reference that version.

Production promotion takes the image version already approved in Staging and updates Production.

The production promotion process requires explicit confirmation before modifying the production desired state.

This creates a controlled progression rather than sending every successful CI build directly to Production.

---

# Monitoring

## 19. Monitoring Stack

The monitoring platform is maintained under:

```text
platform/monitoring/
```

The stack is based on `kube-prometheus-stack` and includes:

* Prometheus
* Grafana
* Alertmanager
* kube-state-metrics
* node-exporter
* Prometheus Operator

The monitoring installation has its own:

```text
install.sh
uninstall.sh
verify.sh
values.yaml
monitoring.env
```

Custom alert rules are stored under:

```text
platform/monitoring/rules/
```

---

## 20. Prometheus

Prometheus collects and stores metrics from the Kubernetes environment.

Metrics include information about:

* Pods
* Deployments
* nodes
* CPU
* memory
* Kubernetes object state
* monitored targets

Prometheus therefore provides the metrics foundation for the observability stack.

---

## 21. kube-state-metrics

kube-state-metrics exposes metrics describing Kubernetes object state.

Examples include:

```text
Desired replicas
Available replicas
Pod status
Deployment status
Node status
```

This allows Prometheus to detect situations where Kubernetes objects are not reaching their expected state.

---

## 22. node-exporter

node-exporter provides host-level metrics from Kubernetes nodes.

Examples include:

* CPU usage
* memory usage
* filesystem information
* network metrics
* operating-system statistics

This complements Kubernetes object metrics with infrastructure-level visibility.

---

# Grafana

## 23. Grafana

Grafana provides visualization for metrics stored in Prometheus.

Instead of relying entirely on raw PromQL queries, dashboards provide a graphical representation of cluster health and resource usage.

The Grafana deployment was verified as part of the monitoring implementation.

The platform exposes Grafana through an HTTPS ingress endpoint.

```text
grafana.ferdeve.fit
```

TLS is provided through cert-manager.

---

# Alertmanager

## 24. Alertmanager

Alertmanager receives alerts generated by Prometheus rules and determines how those alerts should be delivered.

The platform integrates Alertmanager with Slack.

The notification flow is:

```text
Metric
  |
  v
Prometheus
  |
  v
Alert Rule
  |
  v
Alertmanager
  |
  v
Slack
  |
  v
#devops-alerts
```

---

## 25. Alert Lifecycle

Alertmanager sends both firing and resolved notifications.

During validation, the monitoring system successfully generated alerts including:

```text
KubePodNotReady
KubeDeploymentReplicasMismatch
DeploymentUnavailable
```

After the deliberately unhealthy test workload was removed or recovered, corresponding resolved notifications were delivered.

This demonstrated the complete alert lifecycle:

```text
Problem introduced
      |
      v
Metric changes
      |
      v
Prometheus rule fires
      |
      v
Alertmanager
      |
      v
Slack FIRING notification
      |
      v
Problem corrected
      |
      v
Prometheus condition clears
      |
      v
Slack RESOLVED notification
```

This verifies more than simply installing Alertmanager: it demonstrates that the monitoring and notification chain works end to end.

---

## 26. Watchdog Handling

The standard Prometheus monitoring stack includes a continuously firing Watchdog alert.

The platform routes Watchdog to a null receiver instead of sending constant Slack notifications.

This prevents expected Watchdog behaviour from creating unnecessary notification noise while retaining meaningful operational alerts.

---

# Verification

## 27. Component Verification

Platform components have verification scripts.

Examples include:

```text
platform/ingress-nginx/verify.sh
platform/cert-manager/verify.sh
platform/dns/verify-dns.sh
platform/argocd/verify.sh
platform/monitoring/verify.sh
```

This is preferable to assuming that a successful installation command means a component is actually operational.

Verification checks operational state after installation.

---

## 28. Why Verification Matters

A Helm installation can succeed while the deployed application is unhealthy.

For example:

```text
Helm install succeeds
        |
        X
Pod cannot start
```

or:

```text
Ingress exists
      |
      X
DNS points to wrong endpoint
```

or:

```text
Alertmanager Pod runs
        |
        X
Slack notification fails
```

Therefore the platform validates components after deployment.

The monitoring stack was ultimately verified with all monitoring checks passing.

---

# Platform Lifecycle

## 29. Deployment

The top-level platform deployment process coordinates the installation of the required services after the Kubernetes cluster is available.

Conceptually:

```text
Infrastructure
      |
      v
Kubernetes
      |
      v
Ingress
      |
      v
TLS
      |
      v
DNS
      |
      v
ArgoCD
      |
      v
Applications
      |
      v
Monitoring
```

Each layer depends on a healthy foundation beneath it.

---

## 30. Destruction

The platform also supports controlled teardown.

The objective is to avoid leaving unnecessary AWS resources running after testing.

This is particularly important because resources such as:

* Load Balancers
* NAT Gateway
* EC2 instances
* EBS volumes
* public IPv4 addresses

can continue generating charges even when the application is not actively being used.

---

# Failure Boundaries

## 31. NGINX Failure

If the ingress controller becomes unavailable, externally initiated application traffic may fail even if the application Pods themselves remain healthy.

This demonstrates the difference between:

```text
Application health
```

and:

```text
Application reachability
```

---

## 32. DNS Failure

If Route 53 is configured incorrectly, users may not reach the correct AWS endpoint even though Kubernetes and the application are healthy.

DNS therefore sits outside the application runtime but remains part of the end-to-end service path.

---

## 33. Certificate Failure

If certificate issuance fails, the application may remain technically reachable but trusted HTTPS access can fail.

Troubleshooting would include checking:

* Certificate
* CertificateRequest
* Challenge
* Order
* ClusterIssuer
* DNS resolution
* Ingress configuration

---

## 34. ArgoCD Failure

If ArgoCD becomes unavailable, existing application Pods do not automatically disappear.

The workloads already running in Kubernetes can continue operating.

However, GitOps reconciliation stops until ArgoCD is restored.

This distinction is important:

```text
ArgoCD controls deployment state.

ArgoCD is not in the user request path.
```

An ArgoCD outage therefore affects deployment operations rather than directly proxying production application traffic.

---

## 35. Monitoring Failure

If Prometheus, Grafana, or Alertmanager fails, the Pet Adoption application may continue serving users.

However, operational visibility is degraded.

This can result in:

* missing metrics
* unavailable dashboards
* missed alerts
* slower incident detection

Observability components therefore improve operational reliability even though they are not directly responsible for serving application requests.

---

# Platform Summary

## 36. Responsibility Model

Each platform component has a clearly defined responsibility:

```text
Route 53
    → public DNS resolution

NGINX Ingress
    → external traffic routing

cert-manager
    → TLS certificate automation

ArgoCD
    → GitOps continuous delivery

Prometheus
    → metric collection and alert evaluation

Grafana
    → metric visualization

Alertmanager
    → alert routing and Slack notifications

kube-state-metrics
    → Kubernetes object-state metrics

node-exporter
    → node operating-system metrics
```

Together these components transform the Kubernetes cluster from a basic container runtime into an operational DevOps application platform.

The platform provides:

* secure HTTPS access
* environment-based routing
* GitOps deployment
* controlled artifact promotion
* infrastructure monitoring
* application-state monitoring
* dashboards
* automated alerting
* repeatable verification
* controlled teardown

This platform layer sits between the underlying AWS/Kubernetes infrastructure and the Pet Adoption application delivery workflow.




LOGINS

# Platform Access and Credential Retrieval

## ArgoCD

URL:

```text
https://argocd.ferdeve.fit
```

Default administrator username:

```text
admin
```

Retrieve the initial administrator password:

```bash
kubectl get secret argocd-initial-admin-secret \
  --namespace argocd \
  --output jsonpath="{.data.password}" | base64 -d

echo
```

The returned value is used with the `admin` username.

The password must never be committed to Git or stored in project documentation.

---

## Grafana

URL:

```text
https://grafana.ferdeve.fit
```

Administrator username:

```text
admin
```

Retrieve the administrator password:

```bash
kubectl get secret kube-prometheus-stack-grafana \
  --namespace monitoring \
  --output jsonpath="{.data.admin-password}" | base64 -d

echo
```

Use the returned password with the `admin` username.

The generated password must not be committed to Git.

---

## Prometheus

URL:

```text
https://prometheus.ferdeve.fit
```

The current lab implementation does not configure application-level authentication for the Prometheus web interface.

Therefore no Prometheus username or password is retrieved from Kubernetes.

Prometheus is exposed through the NGINX Ingress Controller using HTTPS/TLS.

Public Prometheus access without authentication is acceptable only for the current portfolio/lab validation and is recorded as a production-hardening item.

A production implementation should restrict Prometheus access using mechanisms such as private networking, VPN/access proxy, authentication at the ingress layer, or another approved identity-aware access mechanism.

---

## Jenkins

Jenkins is accessed using the administrator account created during initial configuration.

For a newly provisioned Jenkins server, the initial administrator password is stored at:

```text
/var/lib/jenkins/secrets/initialAdminPassword
```

### Method 1 — AWS Systems Manager Session Manager

```bash
aws ssm start-session \
  --target <JENKINS_INSTANCE_ID> \
  --region eu-west-3 \
  --profile personal-devops
```

Then:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### Method 2 — AWS Console

Navigate to:

```text
EC2
→ Instances
→ Jenkins instance
→ Connect
→ Session Manager
→ Connect
```

Then execute:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### Method 3 — AWS Systems Manager Run Command

Retrieve the instance dynamically from Terraform:

```bash
cd terraform/compute

INSTANCE_ID=$(terraform output -raw jenkins_instance_id)
```

Then execute:

```bash
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo cat /var/lib/jenkins/secrets/initialAdminPassword"]' \
  --region eu-west-3 \
  --profile personal-devops \
  --query "Command.CommandId" \
  --output text)

sleep 5

AWS_PAGER="" aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --region eu-west-3 \
  --profile personal-devops \
  --query "[Status,StandardOutputContent,StandardErrorContent]" \
  --output text
```

The initial password is intended for first-time Jenkins setup. After setup, the administrator credentials created during the Jenkins configuration process should be used.

---

## SonarQube

SonarQube administrator credentials are established during initial SonarQube configuration.

Jenkins does not store the SonarQube administrator password.

Instead, Jenkins authenticates using a SonarQube authentication token.

To generate a token:

```text
SonarQube
→ User Profile
→ My Account
→ Security
→ Generate Token
```

Example token name:

```text
jenkins-pet-adoption
```

Copy the token immediately after generation.

Store it in Jenkins:

```text
Manage Jenkins
→ Credentials
→ System
→ Global credentials
→ Add Credentials
```

Configure:

```text
Kind: Secret text
Secret: <SONARQUBE_TOKEN>
ID: sonarqube-token
```

The actual token must never be committed to Git or written into project documentation.