# MCP server consigliati per il homelab

Ricerca aggiornata al 14 ottobre 2026, basata solo su documentazione e repository upstream.

## Contesto del repository

Questo homelab usa K3s con Flux Operator/Flux Instance, GitHub come sorgente GitOps, Terraform per bootstrap e Cloudflare, Metoro per osservabilita, Homebridge per la domotica e Falco/CrowdSec per la sicurezza. Non risultano invece installazioni locali di Grafana, Prometheus o Home Assistant. Riferimenti interni: [`terraform/flux.tf`](../terraform/flux.tf), [`terraform/cloudflare.tf`](../terraform/cloudflare.tf), [`terraform/metoro.tf`](../terraform/metoro.tf), [`flux/apps/homebridge`](../flux/apps/homebridge), [`flux/apps/falco`](../flux/apps/falco) e [`flux/apps/crowdsec`](../flux/apps/crowdsec).

## Raccomandazione breve

1. **Flux Schema Catalog MCP** subito: e read-only, non richiede accesso al cluster e riduce gli errori su API, CRD e valori Helm.
2. **GitHub MCP Server** subito: permette di correlare manifest, PR, Actions e segnalazioni di sicurezza, mantenendo Git come source of truth.
3. **Flux Operator MCP** per diagnosi live, ma solo in modalita read-only e con RBAC dedicato.
4. **Trivy MCP** come controllo locale/CI di manifest, immagini e configurazioni.
5. **Cloudflare MCP** solo per consultazione o con token estremamente limitato; le modifiche devono continuare a passare da Terraform.

Grafana/Prometheus MCP hanno senso solo se Metoro espone backend compatibili o se in futuro viene aggiunto quello stack. Home Assistant MCP ha senso solo se Home Assistant sostituisce o affianca Homebridge.

## Valutazione

| Server | Stato | Valore per questo homelab | Configurazione consigliata |
|---|---|---|---|
| [Flux Schema Catalog MCP](https://fluxcd.io/blog/2026/07/flux-schema-validation/) | Ufficiale del team Flux Operator; giovane, pubblico e read-only | **Molto alto.** Schemi Kubernetes/CRD e documentazione ottimizzata per agenti, senza credenziali cluster | Collegare `https://schemas.fluxoperator.dev/mcp`; nessuna installazione in K3s |
| [GitHub MCP Server](https://github.com/github/github-mcp-server) | Ufficiale GitHub, maturo | **Molto alto.** Repository, PR, Actions, Code Scanning e Secret Scanning completano il flusso GitOps | Avvio locale/OAuth, `--read-only`, allowlist `repos,actions,code_security,secret_protection`; abilitare scritture solo per un workflow esplicito. Il server supporta sia toolset allowlist sia read-only ([fonte](https://github.com/github/github-mcp-server#tool-configuration)) |
| [Flux Operator MCP](https://fluxoperator.dev/mcp-server/) | Vendor-led e mantenuto dai core maintainer Flux, ma non e un componente core CNCF Flux | **Alto.** E gia allineato al Flux Operator presente nel repo; legge stato, eventi, log, dipendenze e documentazione Flux | Eseguirlo localmente con kubeconfig dedicato, `--read-only`, secret masking e RBAC minimo. In read-only disabilita reconcile/suspend/resume/apply/delete ([configurazione](https://fluxoperator.dev/docs/mcp/config/)) |
| [Trivy MCP](https://github.com/aquasecurity/trivy-mcp) | Ufficiale Aqua/Trivy; plugin MCP ancora giovane | **Alto per sicurezza.** Scansiona filesystem, repository, immagini e misconfiguration ([fonte](https://github.com/aquasecurity/trivy-mcp#features)) | Eseguirlo localmente o in CI sul checkout; non serve un ServiceAccount cluster-wide |
| [Cloudflare API MCP](https://github.com/cloudflare/mcp) | Ufficiale Cloudflare, attivamente mantenuto | **Medio.** Utile per inventario e diagnosi di DNS, Tunnel e Access, ma si sovrappone al Terraform del repo | Usare il server remoto ufficiale con OAuth o token ristretto alle sole letture necessarie. Evitare modifiche dirette: produrrebbero drift rispetto a Terraform |
| [Terraform MCP Server](https://developer.hashicorp.com/terraform/mcp-server) | Ufficiale HashiCorp, stabile | **Medio.** Ottimo per consultare Registry, provider e moduli aggiornati; meno utile per operare sul Terraform locale | Avvio locale via stdio; lasciare disabilitate le operazioni Terraform. HashiCorp raccomanda loopback/stdio e credenziali minime ([sicurezza](https://developer.hashicorp.com/terraform/mcp-server/deploy)) |
| [Grafana MCP](https://github.com/grafana/mcp-grafana) | Ufficiale Grafana Labs, maturo | **Condizionale.** Molto valido per dashboard, alert e datasource, ma Grafana non e presente nel repo | Aggiungerlo solo con un endpoint Grafana reale; service account read-only e toolset minimi. Supporta token da file, autenticazione del chiamante e TLS per trasporti di rete ([fonte](https://github.com/grafana/mcp-grafana#usage)) |
| [Prometheus MCP](https://github.com/prometheus/prometheus-mcp) | Repository ufficiale Prometheus; progetto relativamente giovane | **Condizionale.** Query PromQL, metadata e runbook; ridondante con Grafana MCP se Prometheus e gia un datasource Grafana | Preferire il toolset core e accesso read-only; proteggere l'endpoint HTTP, che puo inoltrare `Authorization` al backend ([fonte](https://github.com/prometheus/prometheus-mcp#security-and-authentication)) |
| [Home Assistant MCP integrato](https://www.home-assistant.io/integrations/mcp_server/) | Ufficiale Home Assistant, quality scale Silver | **Condizionale.** E la scelta corretta se viene installato Home Assistant; non si applica direttamente a Homebridge | OAuth e solo entita esplicitamente esposte; iniziare senza controllo attivo. L'integrazione usa `/api/mcp` e permette di limitare API ed entita ([fonte upstream](https://github.com/home-assistant/home-assistant.io/blob/current/source/_integrations/mcp_server.markdown)) |
| [Kubernetes MCP Server](https://github.com/containers/kubernetes-mcp-server) | Community/vendor-backed nell'organizzazione `containers`; non ufficiale Kubernetes/CNCF | **Basso/medio.** Completo per Kubernetes e Helm, ma largamente ridondante con Flux Operator MCP e piu facile da usare fuori dal modello GitOps | Se adottato: `read_only = true`, deny esplicito di `Secret`, solo toolset necessari e ServiceAccount namespaced ([configurazione](https://github.com/containers/kubernetes-mcp-server#configuration-options)) |

## Architettura e guardrail

- Eseguire i server MCP **sulla workstation via stdio** quando possibile. Non c'e vantaggio nel renderli servizi permanenti del cluster se il solo client e l'assistente locale.
- Per Kubernetes usare un ServiceAccount dedicato con `get`, `list` e `watch` solo sui namespace e Kind necessari. Negare sempre `Secret`; il masking dell'output non sostituisce RBAC.
- Non concedere `create`, `patch`, `delete`, `reconcile`, `suspend` o `resume` ai server cluster-aware. Le modifiche devono diventare commit Git e passare da Flux.
- Per GitHub preferire OAuth o una GitHub App limitata a questo repository; partire in read-only e senza i toolset `git`/governance.
- Per Cloudflare non riutilizzare il token Terraform. Creare un'identita separata, inizialmente read-only e limitata all'account/zona necessari.
- Non esporre MCP via `HTTPRoute` pubblico. Se un trasporto HTTP e indispensabile, usare TLS, autenticazione del chiamante e policy di rete; non pubblicarlo tramite il Tunnel Cloudflare per comodita.
- Tenere Trivy nel percorso repo/CI. Falco e CrowdSec osservano il runtime, ma non risulta un MCP ufficiale Falco equivalente; un wrapper community con accesso ai log runtime aumenterebbe la superficie senza un vantaggio chiaro.

## Ordine di adozione proposto

1. Collegare Flux Schema Catalog MCP e GitHub MCP in read-only.
2. Provare Flux Operator MCP localmente con un kubeconfig read-only e verificare che `Secret` non sia leggibile.
3. Integrare Trivy MCP nel flusso di revisione locale; mantenere i gate CI/pre-commit esistenti come autorita.
4. Valutare Cloudflare MCP solo dopo avere definito un token diagnostico separato.
5. Rivalutare Grafana/Prometheus o Home Assistant MCP quando quei prodotti esisteranno davvero nello stack.

Questa sequenza migliora soprattutto qualita dei manifest e diagnosi, senza trasformare l'agente in un secondo control plane e senza violare il principio GitOps del repository.
