# Troubleshooting and Lessons Learned

## 1. Purpose

This document records significant failures encountered while building the Enterprise DevOps Platform, how they were diagnosed, and the engineering lessons taken from them.

The purpose is not to hide implementation problems.

Real DevOps work involves:

```text
Deploy
→ Observe failure
→ Isolate the failing layer
→ Verify assumptions
→ Correct configuration
→ Retest
→ Automate the lesson
```

The incidents below demonstrate that process.

---

# 2. Troubleshooting Principle

The platform is divided into layers:

```text
AWS
 |
 v
Terraform
 |
 v
KOps / Kubernetes
 |
 v
Platform Services
 |
 v
GitOps
 |
 v
Application
 |
 v
Monitoring
```

A failure should be diagnosed at the layer where it occurs.

Changing unrelated layers usually increases the problem.

---

# 3. Terraform ACM Certificate Lookup Failure

An infrastructure plan encountered an ACM lookup error similar to:

```text
reading ACM Certificates: empty result
```

This means Terraform attempted to locate a certificate matching its query but AWS returned no matching certificate.

## Lesson

Terraform data sources depend on infrastructure already existing in the expected:

* account
* region
* status
* domain

Before changing unrelated Terraform code, verify the external resource being queried actually exists.

---

# 4. SSM Connectivity Timeout

An EC2 instance reported SSM Agent communication errors similar to:

```text
Post https://ssm.eu-west-3.amazonaws.com:
dial tcp ...:443: i/o timeout
```

The important clue was not IAM first.

The request was timing out at the network layer.

## Diagnostic Thinking

```text
SSM Agent
   |
   v
HTTPS 443
   |
   X
SSM endpoint unreachable
```

Possible causes include:

* no outbound route
* NAT Gateway failure
* security/network restrictions
* DNS problems
* incorrect subnet routing

## Lesson

An AWS service connection failure is not automatically an IAM failure.

Differentiate:

```text
AccessDenied
```

from:

```text
timeout / connection failure
```

The first usually suggests permissions.

The second usually suggests networking or endpoint reachability.

---

# 5. Helm Lint Against Remote Chart Name

An attempted command used:

```bash
helm lint prometheus-community/kube-prometheus-stack \
  -f platform/monitoring/values.yaml
```

and failed because `helm lint` expected a local chart path in that usage.

The chart itself was not broken.

## Resolution

The configuration was validated through:

```bash
helm template
```

against the repository chart.

## Lesson

Understand whether a Helm command expects:

* local chart source
* packaged chart
* repository chart reference

Do not assume every Helm command treats chart references identically.

---

# 6. PrometheusRule Applied Before CRD Installation

The monitoring installer originally attempted to apply:

```text
kind: PrometheusRule
```

before the `kube-prometheus-stack` installation had created the Prometheus Operator CRDs.

Kubernetes returned:

```text
no matches for kind "PrometheusRule"
in version "monitoring.coreos.com/v1"

ensure CRDs are installed first
```

## Root Cause

The installation order was wrong.

The original flow was effectively:

```text
Apply PrometheusRule
      |
      X
CRD does not exist
      |
Install monitoring stack later
```

## Resolution

The sequence was changed to:

```text
Helm install kube-prometheus-stack
        |
        v
Wait for PrometheusRule CRD
        |
        v
Apply platform-alerts.yaml
```

The installer explicitly waits for:

```text
crd/prometheusrules.monitoring.coreos.com
```

to become established.

## Lesson

Custom Resources depend on their CustomResourceDefinitions.

Install operators and CRDs before resources that depend on them.

---

# 7. Slack Secret Accidentally Placed Inside Helm Repository Condition

An earlier version of the monitoring installer created the Slack Secret inside logic that only ran when the Helm repository did not already exist.

This meant:

```text
Helm repo already exists
        |
        v
Slack Secret creation skipped
```

## Resolution

Slack Secret creation was separated from Helm repository configuration.

## Lesson

Avoid coupling unrelated prerequisites inside the same conditional block.

Ask:

> Should this operation happen because the condition is true, or must it happen every deployment?

---

# 8. Alertmanager Failed to Reconcile

The monitoring verification initially appeared to show Alertmanager was deployed.

Further investigation revealed:

```text
REPLICAS:    1
READY:       0
RECONCILED:  False
AVAILABLE:   False
```

No Alertmanager StatefulSet or Pod had been created.

## Root Cause

The Alertmanager configuration routed Watchdog alerts to:

```text
receiver: "null"
```

but no receiver named:

```text
null
```

was defined.

The Prometheus Operator rejected the Alertmanager configuration with an error equivalent to:

```text
undefined receiver "null" used in route
```

## Resolution

A null receiver was explicitly added:

```yaml
receivers:
  - name: slack
    ...

  - name: "null"
```

After the correction:

```text
READY:       1
RECONCILED:  True
AVAILABLE:   True
```

and the Alertmanager Pod became Running.

## Lesson

A Kubernetes Custom Resource can exist while its controller fails to reconcile it.

Do not equate:

```text
resource exists
```

with:

```text
resource is operational
```

Inspect:

* status
* conditions
* controller/operator logs
* generated workloads

---

# 9. False-Positive Alertmanager Verification

The original `verify.sh` used a check similar to:

```bash
kubectl get statefulset \
  -l app.kubernetes.io/name=alertmanager
```

The command could return a successful exit status even when no matching StatefulSet existed.

The script therefore reported:

```text
PASS: Alertmanager is deployed
```

when Alertmanager was not actually healthy.

## Resolution

Verification was strengthened to inspect the Alertmanager custom-resource status:

```text
Ready replicas
Reconciled=True
Available=True
```

## Lesson

A health check must prove the property it claims to verify.

Weak verification can be more dangerous than no verification because it creates false confidence.

---

# 10. Grafana and Prometheus Ingress False Failure

The monitoring verifier initially searched all Ingress hostnames inside the monitoring namespace.

cert-manager temporarily created ACME solver Ingresses using the same hostnames:

```text
grafana.ferdeve.fit
prometheus.ferdeve.fit
```

The resulting duplicate values caused the verifier's string comparison to fail.

It reported:

```text
FAIL: Grafana Ingress hostname is missing.
FAIL: Prometheus Ingress hostname is missing.
```

even though both real Ingress resources existed.

## Resolution

The verifier was changed to query the specific expected Ingress objects:

```text
kube-prometheus-stack-grafana
kube-prometheus-stack-prometheus
```

## Lesson

Verification should identify the exact resource being validated rather than assume every matching value belongs to the intended object.

---

# 11. TLS Certificates Initially Not Ready

Immediately after monitoring installation:

```text
grafana-tls      False
prometheus-tls   False
```

cert-manager had created ACME solver resources but certificate issuance was incomplete.

## Root Cause

The monitoring hostnames needed valid public DNS pointing to the ingress Load Balancer so Let's Encrypt HTTP validation could complete.

## Resolution

Route 53 records were created for:

```text
grafana.ferdeve.fit
prometheus.ferdeve.fit
```

After DNS propagation and ACME validation:

```text
grafana-tls      True
prometheus-tls   True
```

## Lesson

Certificate troubleshooting crosses multiple layers:

```text
Certificate
→ Challenge
→ Ingress
→ DNS
→ Load Balancer
→ Internet reachability
```

Do not repeatedly reinstall cert-manager when DNS is the actual failure.

---

# 12. Manual Slack Webhook Test Passed but Real Alerts Did Not

A manual webhook request successfully delivered:

```text
Enterprise DevOps Platform test alert

Slack integration is working successfully.
```

However, a real Prometheus alert did not initially appear.

## Diagnostic Value

The successful test proved:

```text
Slack webhook
        |
        v
Slack channel
        |
       PASS
```

Therefore troubleshooting moved upstream:

```text
Prometheus
→ Alertmanager
→ Slack
```

Further investigation exposed the broken Alertmanager reconciliation described earlier.

## Lesson

Test integrations layer by layer.

A successful endpoint test narrows the fault domain.

---

# 13. Controlled Deployment Failure Did Not Initially Produce Unavailable Replica

A disposable Deployment was changed to reference an invalid image.

The new Pod entered:

```text
ImagePullBackOff
```

but the Deployment still showed:

```text
READY:     1/1
AVAILABLE: 1
```

## Why

Kubernetes RollingUpdate preserved the old healthy Pod while the replacement failed.

Therefore:

```text
kube_deployment_status_replicas_unavailable
```

did not immediately become greater than zero.

## Resolution

The disposable Deployment was scaled to zero and back to one while still referencing the invalid image.

This removed the old healthy replica and created a genuine unavailable Deployment.

The result became:

```text
Desired=1
Available=0
Unavailable=1
```

## Lesson

A failed rollout is not necessarily the same thing as application unavailability.

Kubernetes rolling updates are intentionally designed to preserve service availability where possible.

---

# 14. Prometheus Alert Lifecycle

Once the test Deployment became genuinely unavailable, the custom alert entered:

```text
PENDING
```

because the rule required:

```yaml
for: 5m
```

After the condition persisted for five minutes, it became:

```text
FIRING
```

## Lesson

The `for` duration reduces alert noise.

A transient problem should not necessarily page an engineer immediately.

---

# 15. Successful End-to-End Alert Test

After Alertmanager was corrected, Slack received:

```text
[FIRING] DeploymentUnavailable
```

with:

```text
Severity: warning
Namespace: default
The disposable monitoring test Deployment used the `default` namespace during alert validation. The final Pet Adoption architecture uses dedicated `pet-adoption-dev`, `pet-adoption-staging`, and `pet-adoption-prod` namespaces.
```

After the Deployment recovered, Slack later received:

```text
[RESOLVED] DeploymentUnavailable
```

## Proven Flow

```text
Kubernetes failure
       |
       v
kube-state-metrics
       |
       v
Prometheus
       |
       v
PrometheusRule
       |
       v
Alertmanager
       |
       v
Slack FIRING
       |
       v
Recovery
       |
       v
Slack RESOLVED
```

## Lesson

Installing monitoring software is not enough.

A real operational test should prove the complete signal path.

---

# 16. Built-In Monitoring Noise

Once Alertmanager began working, Slack also received built-in alerts including:

```text
KubePodNotReady
KubeDeploymentReplicasMismatch
TargetDown
KubeControllerManagerDown
KubeSchedulerDown
KubeProxyInstanceUnreachable
```

Some reflect characteristics of the KOps lab environment rather than immediate user-facing outages.

## Lesson

Alerting requires tuning.

More alerts do not automatically mean better observability.

A mature monitoring implementation must distinguish:

```text
useful actionable signal
```

from:

```text
expected or non-actionable noise
```

---

# 17. GitOps Repository Duplication

The platform originally used a separate:

```text
enterprise-gitops
```

repository.

This worked technically but created a weaker portfolio presentation because infrastructure and desired-state configuration were split across too many repositories.

## Resolution

GitOps configuration was consolidated into:

```text
enterprise-devops-platform/gitops/
```

The Jenkins pipeline was updated from:

```text
enterprise-gitops.git
```

to:

```text
enterprise-devops-platform.git
```

and the target path became:

```text
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

## Lesson

Repository boundaries should serve operational and governance needs.

For this portfolio, consolidating platform infrastructure and GitOps configuration made the project easier to understand while keeping application source separate.

---

# 18. Dev, Staging and Production Were Initially Missing

The original GitOps model effectively deployed a single application environment.

That meant a successful CI build could become the live application without demonstrating a controlled pre-production promotion process.

## Resolution

The platform added:

```text
pet-adoption-dev
pet-adoption-staging
pet-adoption-prod
```

namespaces and matching Kustomize overlays.

ArgoCD now has three Application definitions.

## Lesson

Continuous Delivery should not automatically mean:

```text
build successful
→ production
```

Environment promotion provides additional validation boundaries.

---

# 19. Build Once, Promote Many

The initial environment discussion raised the risk of independently rebuilding the application for Dev, Staging and Production.

That model was rejected.

## Implemented Strategy

```text
Jenkins builds image once
        |
        v
DEV
        |
        v
STAGING
        |
        v
PROD
```

The exact same immutable ECR image tag is promoted.

## Lesson

Testing one binary and deploying another weakens confidence in pre-production testing.

Promote the tested artifact rather than rebuild it.

---

# 20. Repository Scaffold Became Redundant

The repository initially contained placeholder directories such as:

```text
docker/
kubernetes/
jenkins/
linux-notes/
monitoring/
terraform/environments/
```

As the platform evolved, real implementations moved elsewhere.

For example:

```text
monitoring/
```

was superseded by:

```text
platform/monitoring/
```

and:

```text
kubernetes/
```

was superseded by:

```text
gitops/
```

## Resolution

Obsolete placeholder folders and unnecessary `.gitkeep` files were removed.

## Lesson

A repository should reflect the current architecture.

Old scaffold left behind creates confusion and weakens presentation quality.

---

# 21. Accidental Duplicate ArgoCD Directory

An unintended nested directory appeared:

```text
platform/argocd/platform/argocd/
```

containing duplicated ArgoCD files.

It was not referenced by the project.

## Resolution

The duplicate directory was removed after verifying the real configuration remained under:

```text
platform/argocd/
```

## Lesson

Before committing, inspect:

```bash
git status
```

Unexpected untracked directories often expose accidental command or path mistakes.

---

# 22. Redundant Alertmanager Configuration

A standalone:

```text
platform/monitoring/alertmanager-config.yaml
```

existed even though Alertmanager configuration had moved into:

```text
platform/monitoring/values.yaml
```

No project component referenced the standalone file.

## Resolution

The obsolete file was removed.

## Lesson

Duplicate configuration creates uncertainty over which file is authoritative.

Maintain one clear source of truth.

---

# 23. Terraform Network Backend File Organization

The network module had an empty:

```text
terraform/network/backend.tf
```

while the S3 backend configuration lived inside:

```text
provider.tf
```

The configuration worked, but the structure was inconsistent with the other Terraform modules.

## Resolution

The Terraform/backend block was moved to:

```text
backend.tf
```

while:

```text
provider.tf
```

was left responsible for AWS provider configuration.

## Lesson

Consistency matters even when code is functionally correct.

Predictable structure reduces cognitive load during troubleshooting and code review.

---

# 24. AWS Cost Investigation

The project AWS Budget showed actual spend that initially appeared inconsistent with current resource checks.

Current EC2, NAT Gateway, load balancer and other queries returned no active resources, while historical billing showed usage.

Billing details revealed cost contributors such as:

```text
NAT Gateway
EC2
Elastic Load Balancing
EBS
Route 53
Public IPv4 addresses
```

The NAT Gateway was particularly significant because charges included:

```text
hourly runtime
+
data processing
```

## Lesson

AWS billing is historical.

Current-resource queries answer:

> What exists now?

Cost Explorer answers:

> What was consumed during the billing period?

Those are different questions.

---

# 25. Budget Forecast Was Not Current Burn Rate

The AWS Budget displayed:

```text
ActualSpend: 12.125 USD
ForecastedSpend: 46.003 USD
```

while resource checks showed the expensive infrastructure had already been destroyed.

## Lesson

Budget forecasts extrapolate prior spending patterns and may not immediately reflect a newly destroyed environment.

Do not confuse forecast with guaranteed end-of-month cost.

---

# 26. Terraform State Protection

A local:

```text
terraform/backend/terraform.tfstate
```

file remained on the workstation.

A Git check confirmed it was not tracked and was ignored through:

```text
*.tfstate
```

## Lesson

Never assume sensitive/generated files are excluded.

Verify using:

```bash
git ls-files <file>
git check-ignore -v <file>
```

---

# 27. Shell Executed Documentation Text

Documentation text was accidentally pasted directly into Git Bash.

Bash attempted to execute sentences and Markdown as commands, producing errors such as:

```text
command not found
```

## Lesson

Use:

```bash
code filename.md
```

to edit documentation.

Use the terminal only for actual shell commands.

A path or Markdown document pasted directly into Bash is not interpreted as documentation.

---

# 28. YAML Executed as Bash

A Kubernetes Kustomization file path was entered directly into the terminal:

```text
gitops/pet-adoption/overlays/dev/kustomization.yaml
```

Bash attempted to execute the YAML and returned messages such as:

```text
apiVersion:: command not found
kind:: command not found
```

## Lesson

To inspect a YAML file, use:

```bash
cat file.yaml
```

or:

```bash
code file.yaml
```

Do not execute configuration files unless they are actually executable scripts.

---

# 29. Verification Philosophy

Several of the project's most useful improvements came from strengthening verification.

The general rule became:

```text
Installation success
       !=
Operational success
```

Examples:

```text
Helm release exists
       !=
all Pods healthy

Certificate object exists
       !=
certificate Ready

Alertmanager object exists
       !=
Alertmanager reconciled

Ingress object exists
       !=
correct public routing

Webhook works manually
       !=
Prometheus-to-Slack path works
```

---

# 30. Troubleshooting Workflow

The preferred troubleshooting process is:

```text
1. Reproduce the problem
2. Read the exact error
3. Identify the failing layer
4. Inspect actual resource state
5. Inspect controller/service logs
6. Test the smallest dependency
7. Change one thing
8. Retest
9. Strengthen verification
10. Document the lesson
```

This reduces random configuration changes.

---

# 31. Useful Kubernetes Commands

Common diagnostic commands include:

```bash
kubectl get pods -A
kubectl get deployments -A
kubectl get ingress -A
kubectl get certificate -A
kubectl describe <resource>
kubectl logs <pod>
kubectl get events -A
```

For ArgoCD:

```bash
kubectl get applications -n argocd
```

For monitoring:

```bash
kubectl get prometheus -n monitoring
kubectl get alertmanager -n monitoring
kubectl get prometheusrule -n monitoring
```

---

# 32. Useful AWS Checks

Useful AWS resource checks include:

```text
EC2 instances
NAT Gateways
Load Balancers
EBS volumes
Elastic/Public IPs
RDS
```

Use AWS CLI queries against the correct:

```text
account
region
profile
```

before drawing conclusions.

---

# 33. Core Lessons

The project reinforced several practical DevOps principles:

* verify assumptions with commands
* read error messages carefully
* distinguish networking from permissions
* install CRDs before dependent custom resources
* do not trust weak health checks
* validate real alert delivery
* preserve immutable artifacts
* separate CI from CD
* promote instead of rebuilding
* keep Git as desired-state source
* clean obsolete repository structure
* understand cloud cost drivers
* destroy temporary infrastructure
* document failures as well as successes

---

# 34. Summary

The strongest parts of the platform were not created because every deployment worked on the first attempt.

They were created because failures exposed weak assumptions.

Examples include:

```text
Broken CRD ordering
→ better installation sequencing

False Alertmanager PASS
→ stronger verification

Missing Slack alerts
→ reconciliation debugging

Duplicate ingress results
→ resource-specific checks

Single environment
→ Dev/Staging/Prod model

Multiple repositories
→ cleaner portfolio architecture

Unexpected AWS spend
→ cost-aware lifecycle
```

Troubleshooting therefore became part of the platform design rather than an activity performed only after something failed.
