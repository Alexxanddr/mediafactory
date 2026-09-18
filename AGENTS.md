# AGENTS.md

## Scope

These instructions apply to the entire repository. This project manages a K3s homelab with Terraform and FluxCD; Git is the source of truth. Cluster changes must be declarative and committed to the repository. Do not install resources directly with `kubectl apply`, `helm install`, or equivalent commands unless the user explicitly requests diagnostic or emergency work.

Before modifying a resource:

1. inspect the manifests for the same product and for similar products;
2. verify APIs and Helm values against the product's official sources;
3. preserve the existing naming, namespace, storage, SOPS, and monitoring conventions;
4. do not modify files or resources unrelated to the request;
5. never introduce plaintext credentials, tokens, private hostnames, or other secrets.

## Repository structure and reconciliation order

### `terraform/`

This directory contains the cluster bootstrap:

- K3s installation through the `xunleii/k3s/module` module;
- node and NFS/storage configuration;
- Flux Operator and Flux Instance installation;
- Git repository and SOPS Age key configuration;
- Metoro installation for monitoring;
- Cloudflare configuration and externally exposed services.

Format Terraform changes with `terraform fmt`. Do not add sensitive values to `.tf` files, other tracked files, or outputs that are not marked `sensitive`.

### `flux/clusters/home/`

This is the entrypoint reconciled by the Flux Instance. It contains the Flux `Kustomization` resources that define ordering and dependencies, together with bootstrap resources that must exist before the rest of the cluster, such as the Gateway API CRDs.

Current order:

1. bootstrap resources and CRDs in `clusters/home`;
2. `infrastructure`;
3. `apps`, which depends on `infrastructure`.

When a new product requires CRDs or an operator, ensure they are Ready before applying their Custom Resources. If the existing Kustomizations cannot guarantee this dependency, add a dedicated Kustomization under `flux/clusters/home/` with an explicit `dependsOn`.

### `flux/infrastructure/`

This directory contains shared infrastructure components, including:

- cert-manager;
- CloudNativePG;
- MariaDB Operator;
- the shared Redis instance;
- MetalLB;
- Traefik and Gateway API;
- NVIDIA Operator;
- shared security components.

Install operators, controllers, infrastructure Helm charts, and CRDs here. Application instances or Custom Resources managed by those operators normally belong under `flux/apps/`.

Shared namespaces are defined in `flux/infrastructure/namespace.yaml`. Reuse an existing namespace; do not create a new one without a concrete reason.

### `flux/apps/`

This directory contains applications, operator-managed database instances, and application configuration. Each product has its own `flux/apps/<product>/` directory.

Namespaces normally used in this repository:

- `multimedia-factory`: media management, acquisition, and streaming;
- `extra-tools`: utilities and user-facing observability tools;
- `home-automation`: home automation;
- `gaming`: gaming applications;
- `system-addon`: system, networking, and security components;
- `database`: databases and their Custom Resources;
- `flux-system`: Flux sources and controller resources only, when required.

Choose the namespace by comparing similar existing products. Never use the `default` namespace.

## Kubernetes manifest organization

Separate manifests by `Kind`, using filenames consistent with the repository:

- `deployment.yaml` for `Deployment`;
- `sts.yaml` for `StatefulSet`;
- `service.yaml` for `Service`;
- `httproute.enc.yaml` for an `HTTPRoute` with an encrypted hostname;
- `persistentvolume.yaml` for `PersistentVolume`;
- `persistentvolumeclaim.yaml` for `PersistentVolumeClaim`;
- `configmap.yaml` for `ConfigMap`;
- `secret.enc.yaml` for SOPS-encrypted `Secret` resources;
- `serviceaccount.yaml`, `role.yaml`, `rolebinding.yaml`, `clusterrole.yaml`, and `clusterrolebinding.yaml` for RBAC;
- `helmrepository.yaml` or `ocirepository.yaml` for the Flux source;
- `helmrelease.yaml` for `HelmRelease`.

Each product directory must contain exactly one manifest file for each Kubernetes `Kind`. This constraint applies to every Kind: all `HTTPRoute` resources belong in the single `httproute.enc.yaml`, all `Service` resources in `service.yaml`, all `Deployment` resources in `deployment.yaml`, all `Component` resources in `component.yaml`, and so on. Never create per-resource variants such as `httproute-ui.enc.yaml`, `service-api.yaml`, or `deployment-worker.yaml` when a file for that Kind already exists.

When a product needs multiple resources of the same `Kind`, put them in that Kind's single file as separate YAML documents delimited by `---`. Multiple documents in one file must still belong to the same product and Kind, such as multiple `HTTPRoute`, `Database`, `User`, or `Grant` resources. Never collect different Kinds in a generic file.

Keep names, labels, and selectors consistent. `Service.spec.selector` must exactly match the pod labels. Prefer a `ClusterIP` Service; use `NodePort` or `LoadBalancer` only when the product explicitly requires it.

## Adding a new product

When the user provides a repository or asks to add a product:

1. inspect its README, official documentation, container images, ports, environment variables, volumes, probes, dependencies, and supported architectures;
2. determine whether the product provides an official Helm chart, an operator, a `Deployment`, a `StatefulSet`, or another controller;
3. compare it with at least one similar existing application in this repository;
4. create `flux/apps/<product>/`;
5. add at least the workload (`Deployment`, `StatefulSet`, `HelmRelease`, or equivalent CR) and the `Service`; add an `HTTPRoute` only when the product exposes a user-facing web interface;
6. add `PersistentVolume` and `PersistentVolumeClaim` resources only when the product persists data;
7. add ConfigMaps, SOPS Secrets, RBAC, and database resources only when required;
8. configure Keel and Uptime Kuma according to the rules below;
9. update the README in the appropriate category when the product becomes a permanent part of the stack;
10. validate the complete Flux rendering before finishing.

Do not invent ports, mount paths, health endpoints, or environment variables. If the documentation is insufficient, inspect the upstream chart or manifests.

## Images and automatic updates

Use the product's published `latest` image for every new application workload. If the registry requires an explicit tag, use `:latest`; even when an omitted tag implies `latest`, prefer the explicit tag in new manifests. Set `imagePullPolicy: Always`.

Do not automatically change existing tags on databases, init containers, operators, or infrastructure components unrelated to the request. If upstream does not publish a `latest` tag or the chart does not accept it, report the limitation and use the official moving-tag equivalent only after verifying it.

Always add these Keel annotations to `metadata.annotations` on directly managed `Deployment` and `StatefulSet` resources:

```yaml
keel.sh/policy: force
keel.sh/trigger: poll
keel.sh/matchTag: "true"
```

For Helm charts, configure the `latest` image, pull policy, and annotations through values supported by the chart. Do not add values the chart does not recognize.

## Uptime Kuma monitoring

Every new service must include Uptime Kuma annotations. For directly managed workloads, follow the annotation placement used by existing manifests; for Helm charts or operators, use `podAnnotations`, `podMetadata.annotations`, or the supported equivalent.

HTTP example:

```yaml
uptime-kuma.io/enabled: "true"
uptime-kuma.io/type: "http"
uptime-kuma.io/url: "http://<service>.<namespace>.svc:<port>"
uptime-kuma.io/name: "<product-name>"
uptime-kuma.io/interval: "60"
uptime-kuma.io/retries: "3"
uptime-kuma.io/notifications: "Monitoring Bot"
uptime-kuma.io/group: "<group>"
```

Use the internal Service DNS address, not the public hostname. For non-HTTP protocols, use the type already established in the repository (`port` or `tcp`) and include `uptime-kuma.io/port`. If a healthy endpoint returns a special status code, add `uptime-kuma.io/status-codes` as shown by existing examples.

The following values are the canonical Uptime Kuma macro-groups. Select the most appropriate one for the product and use the value exactly as written, including capitalization, spaces, and `&`. Do not introduce new groups without explicit user approval:

- `Media & Streaming`;
- `Media Acquisition`;
- `Storage & Databases`;
- `Network & Connectivity`;
- `Monitoring & Observability`;
- `Security & Cluster`;
- `Utilities`.

## Internal HTTP exposure

Every new service that exposes a user-facing web interface must be exposed internally through Gateway API and an `HTTPRoute` stored in `httproute.enc.yaml`. Do not create an `HTTPRoute` merely because a Service uses HTTP: backend APIs used only by other workloads, ingestion endpoints, metrics endpoints, health endpoints, webhooks, and other machine-to-machine interfaces must remain cluster-internal unless the user explicitly requests direct access or the product requires it. When a product has separate API and UI Services, create a route only for the UI.

Follow the existing pattern:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: <product>
  namespace: <product-namespace>
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: system-addon
  hostnames:
    - <internal-hostname-encrypted-with-SOPS>
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <service>
          port: <service-port>
```

The hostname is sensitive and must remain encrypted with SOPS. Do not create a Kubernetes Ingress in parallel, and disable the ingress bundled with Helm charts. Do not add external Cloudflare/Tunnel exposure unless the user explicitly requests it.

## Secrets and SOPS

- Every tracked Secret must be named `secret.enc.yaml` or otherwise end in `.enc.yaml`.
- Follow the rules in `.sops.yaml`; never manually modify `ENC[...]` payloads, MACs, or Age blocks.
- Create and modify secrets with `sops`, leaving `data` and `stringData` encrypted.
- Never write passwords, tokens, credential-bearing URIs, or private keys in `AGENTS.md`, ordinary manifests, comments, Terraform output, or documentation.
- Reuse `secretKeyRef` and `envFrom` instead of copying credentials into workloads.
- Run the available pre-commit and Gitleaks checks before finishing.

## Persistent storage

For local application storage, follow the existing products:

- PV with `persistentVolumeReclaimPolicy: Retain`;
- `storageClassName: local-path`;
- application path under `/var/lib/rancher/k3s/storage/<product>/`, except existing media data under `/mnt/md0/MediaFactory`;
- `nodeAffinity` targeting `k3s-server` for `local` volumes;
- PVC explicitly bound with `volumeName` when using a static PV;
- mount path taken from upstream documentation.

Do not create storage for truly stateless workloads. Never delete or rename existing PVs or PVCs without explicit authorization: losing or detaching data is a destructive operation.

## Shared databases

Do not create new MariaDB, PostgreSQL, or Redis instances for an individual application. Always reuse the existing services and operators.

### Redis

Redis is a single shared instance installed under `flux/infrastructure/redis/`. There are no application CRDs to add, and you must not create another Redis `Deployment`, `StatefulSet`, `HelmRelease`, `Service`, PV, or PVC.

Use a URI in this format:

```text
redis://:${REDIS_PASSWORD}@redis-master.database.svc.cluster.local:6379/<db-index>
```

The authoritative password is stored in the SOPS Secret `redis-auth` in the `database` namespace; never copy it as plaintext. Put the final URI in the application's encrypted Secret, or construct it from Secret references when the workload supports that. Redis uses numeric logical databases: inspect the indexes already in use and assign a free one. If the application only accepts database `0`, check for possible key collisions.

### PostgreSQL

PostgreSQL is managed by CloudNativePG under `flux/apps/postgresql/`.

For a new application:

1. add an entry to `spec.managed.roles` in `flux/apps/postgresql/cluster.yaml`;
2. set at least `login: true`, minimal privileges, and a dedicated `passwordSecret.name`;
3. add a `kind: Database` resource to `flux/apps/postgresql/database.yaml`, with its owner matching the role and `cluster.name: postgres`;
4. add `kubernetes.io/basic-auth` credentials to `flux/apps/postgresql/secret.enc.yaml` through SOPS;
5. point the application at the appropriate cluster Service, normally `postgres-rw.database.svc.cluster.local:5432`.

Do not create a second PostgreSQL `Cluster` unless explicitly requested.

### MariaDB

MariaDB is managed by MariaDB Operator under `flux/apps/mariadb/`.

For a new application, following the existing resources as a reference:

1. add a `kind: Database` to `database.yaml` with `mariaDbRef.name: mariadb`;
2. add a `kind: User` to `users.yaml` with a dedicated `passwordSecretKeyRef`;
3. add a `kind: Grant` to `grants.yaml`, scoped to the application's database;
4. add the new key/password to `secret.enc.yaml` through SOPS;
5. use the `mariadb.database.svc.cluster.local:3306` Service.

Do not create a second `MariaDB` resource, an application-specific MariaDB pod, or separate database storage unless explicitly requested.

## Helm charts and operators

For a Helm-based product, preserve the same file separation:

- source in `helmrepository.yaml` or `ocirepository.yaml` in the `flux-system` namespace;
- release in `helmrelease.yaml` in the product namespace;
- `Service`, `HTTPRoute`, PV/PVC, and Secret resources in separate files when the chart does not manage them correctly.

Prefer official charts and repositories. Configure intervals and remediation consistently with existing releases. Disable bundled ingress and databases when this repository already provides Gateway API and shared databases. Never install a PostgreSQL, MariaDB, or Redis subchart.

When introducing an operator:

- install the operator and CRDs in the `infrastructure` layer or through a dedicated bootstrap Kustomization;
- place the product's Custom Resources in `apps`;
- declare the order with `dependsOn` and health checks instead of relying on eventual retries.

## Required validation

Run the relevant checks before considering a change complete:

```bash
git diff --check
pre-commit run --all-files
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
flux build kustomization infrastructure \
  --path flux/infrastructure \
  --kustomization-file flux/clusters/home/infrastructure.yaml \
  --dry-run
flux build kustomization apps \
  --path flux/apps \
  --kustomization-file flux/clusters/home/apps.yaml \
  --dry-run
```

Run `helm template` or `helm show values` for new or modified releases. Use `kubectl apply --dry-run=server` only when the cluster is available and without mutating its state. If a check is unavailable or fails because of an external dependency, report it clearly.

## Final checklist for a new HTTP application

- `flux/apps/<product>/` directory created;
- correct workload added (`Deployment`, `StatefulSet`, `HelmRelease`, or CR);
- application image uses `latest` and pull policy `Always`;
- internal `Service` matches labels and ports;
- `httproute.enc.yaml` points to `traefik-gateway`;
- hostname encrypted with SOPS;
- Keel annotations present;
- Uptime Kuma annotations present with the correct internal URL;
- persistent storage added only when necessary;
- Secrets encrypted and no sensitive values stored as plaintext;
- shared database reused according to the rules above;
- chart-bundled ingress and databases disabled;
- Flux rendering and security checks completed;
- README updated when the product becomes a permanent part of the stack.
