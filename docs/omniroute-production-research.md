# OmniRoute: note per il deployment production su Kubernetes

Ricerca svolta il 2026-10-19 esclusivamente su fonti upstream (repository,
documentazione e workflow di release). I riferimenti sono fissati al ramo
`release/v3.8.52`, salvo la pagina delle release.

## Raccomandazione sintetica

Installare OmniRoute come **singola replica** con immagine versionata (e,
idealmente, digest), PVC `ReadWriteOnce` su `/app/data`, Redis interno non
esposto, autenticazione obbligatoria e TLS sull'Ingress. Questa topologia non è
HA: l'upstream avverte che più repliche contro lo stesso SQLite possono
corrompere il database e che ogni restart interrompe SSE e sessioni.

## Immagini e release

- Immagine ufficiale: `diegosouzapw/omniroute` (pubblicata anche su GHCR dal
  workflow upstream), multi-arch `linux/amd64` e `linux/arm64`.
- Per GitOps usare `:<X.Y.Z>` o, meglio, il digest. `latest` è un puntatore
  stabile ma mutabile; `next` e `main` non sono canali production.
- Le varianti `:<version>-web` includono Chromium/Playwright e servono soltanto
  per `gemini-web`, `claude-web` e `claude-turnstile`; l'immagine normale è più
  piccola e va preferita negli altri casi.
- Al momento della ricerca GitHub mostra `v3.8.51` come ultima release formale,
  mentre il ramo pre-release è `release/v3.8.52`: non va distribuita una tag
  `3.8.52` finché non risulta pubblicata. Verificare tag e digest prima del merge.

Fonti: [Docker Guide: image tags e canali](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docs/guides/DOCKER_GUIDE.md#image-tags), [workflow di pubblicazione](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/.github/workflows/docker-publish.yml), [releases](https://github.com/diegosouzapw/OmniRoute/releases).

## Architettura e persistenza

- L'app è un singolo processo Node/Next.js e usa SQLite per dati applicativi;
  `/app/data` contiene database, migrazioni, audit trail e credenziali provider
  cifrate. Richiede quindi un PVC persistente scrivibile dall'utente non-root
  UID/GID 1000.
- Redis è il backend di rate limiting/cache (`REDIS_URL=redis://redis:6379`).
  Senza Redis il rate limiter degrada a memoria locale. Redis non richiede una
  porta pubblica e nel compose upstream persiste `/data`.
- La topologia stock è single-writer/single-replica. Non usare rolling update
  con due pod contemporanei sul medesimo PVC: scegliere `Recreate`, oppure una
  strategia equivalente che garantisca `maxSurge: 0` e assenza di writer
  concorrenti.
- Le auto-backup SQLite sono abilitate per default, ma non sostituiscono snapshot
  e restore testati del PVC. Durante un restart si perdono connessioni SSE e
  stato in memoria.

Fonti: [Self-host guide: dati e backup](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docs/getting-started/SELF_HOST_GUIDE.md#data-backups-and-resets), [Docker Guide: availability](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docs/guides/DOCKER_GUIDE.md#availability-default-sqlite-is-single-replica), [self-host compose](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docker-compose.selfhost.yml).

## Porte e probe

| Porta | Funzione | Esposizione consigliata |
| --- | --- | --- |
| `20128` | dashboard e proxy LLM `/v1` | Service/Ingress |
| `20129` | API server-to-server | solo cluster, se realmente necessaria |
| `20132` | WebSocket live della dashboard | solo cluster/Ingress, se necessario |
| `6379` | Redis | solo Service interno |

- Readiness: HTTP `GET /healthz` sulla porta 20128.
- Liveness: preferire TCP 20128; in alternativa HTTP `GET /livez` con timeout
  non aggressivo. Entrambi gli endpoint HTTP condividono l'event loop con il
  workload, quindi CPU/compressione possono ritardare la risposta.
- Non usare `/api/monitoring/health` come liveness: è un deep check (DB e
  monitoring) destinato a diagnostica/blackbox.
- Prevedere uno `startupProbe` tollerante: la guida self-host considera fino a
  circa 300 secondi per la disponibilità iniziale.

Fonte: [Docker Guide: healthcheck e probe orchestrator](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docs/guides/DOCKER_GUIDE.md#reverse-proxy-on-a-subpath-traefik--nginx), [Self-host guide: verifica e porte](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docs/getting-started/SELF_HOST_GUIDE.md#step-3--verify-30-s).

## Configurazione e secret

Impostazioni production minime:

- `DATA_DIR=/app/data`
- `REDIS_URL=redis://<service-redis>:6379`
- `REQUIRE_API_KEY=true`
- `NEXT_PUBLIC_BASE_URL=https://<host>` e `AUTH_COOKIE_SECURE=true` dietro TLS
- `OMNIROUTE_WS_BRIDGE_SECRET`: random forte; upstream lo dichiara obbligatorio
  in production
- `JWT_SECRET`: almeno 32 caratteri
- `API_KEY_SECRET`: almeno 16 caratteri
- `STORAGE_ENCRYPTION_KEY`: raccomandata per cifratura a riposo
- `MACHINE_ID_SALT`: secret stabile raccomandato nei deployment gestiti

Conservare i quattro secret in un Secret/SOPS, non in chiaro nei manifest.
Anche le API key dei provider vanno gestite nel dashboard e persistono cifrate
nel data directory. L'upstream raccomanda volumi secret read-only; il container
ufficiale gira già come utente `node` non-root.

Per un hostname pubblico configurare esplicitamente l'origine; abilitare
`OMNIROUTE_TRUST_PROXY` soltanto se si vuole davvero derivarla dagli header
forwarded del proxy fidato. Non esporre mai il proxy `/v1` senza auth: chiunque
potrebbe consumare quote/crediti dei provider.

Fonti: [Docker Guide: variabili critiche](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docs/guides/DOCKER_GUIDE.md#critical-environment-variables), [Security policy: secret e hardening Docker](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/SECURITY.md#required-environment-variables), [.env self-host](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/.env.selfhost.example), [Dockerfile runner](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/Dockerfile#L224-L294).

## Risorse e caveat operativi

- Il default immagine (`OMNIROUTE_MEMORY_MB=1024`) è adatto soltanto a dashboard
  e chat leggere. La guida upstream indica circa 8 GiB di heap e almeno 10 GiB
  di memoria container per un coding agent, e 10–12 GiB di heap / 12–16 GiB di
  container per due contesti lunghi concorrenti. I buffer nativi restano fuori
  dall'heap V8.
- Per un'installazione iniziale prudente, allocare una sola replica e dimensionare
  in base all'uso previsto; evitare di aumentare la concorrenza heavyweight
  senza misure reali di RSS/OOM.
- `runner-web` aggiunge superficie e consumo per Chromium; usarlo solo quando
  richiesto.
- Il server può installare/eseguire componenti tramite npm a runtime e non si
  presta automaticamente a un filesystem interamente read-only senza verificare
  i percorsi scrivibili. Limitare privilegi/capability, usare seccomp di default
  e consentire la scrittura solo dove testato (`/app/data` ed eventuali tmp).
- Le guardrail di prompt injection sono euristiche, fail-open e possono essere
  disattivate per richiesta: non considerarle un confine di sicurezza.
- Prima di un upgrade: snapshot del PVC, aggiornamento intenzionale della
  versione/digest, rollout `Recreate`, controllo migrazioni e test di restore.
- Dare al pod una finestra di arresto ampia: l'upstream usa 40 secondi in
  Compose e, nella guida Kubernetes, propone 90 secondi con un `preStop` di 15
  secondi per drenare le richieste/SSE (il timeout applicativo predefinito è 30
  secondi).

Fonti: [Docker Guide: runtime RAM](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/docs/guides/DOCKER_GUIDE.md#runtime-ram-for-coding-agents), [Dockerfile](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/Dockerfile), [Security policy: guardrail](https://github.com/diegosouzapw/OmniRoute/blob/release/v3.8.52/SECURITY.md#prompt-injection-guard).

## Decisioni suggerite per questo repository

1. Usare una `StatefulSet` a replica 1 oppure un `Deployment` con strategia
   `Recreate`; il secondo è più semplice se non serve un'identità stabile.
2. PVC RWO per `/app/data`; Redis dedicato in-cluster con PVC proprio, senza
   Ingress/LoadBalancer.
3. Esporre solo 20128 tramite il reverse proxy/Ingress esistente; aggiungere
   20132 soltanto se il dashboard live lo richiede e il proxy supporta upgrade
   WebSocket. Non esporre 20129 senza un caso d'uso.
4. Pin esatto più digest, Renovate/aggiornamento controllato, PodDisruptionBudget
   coerente con una replica (sapendo che non crea HA).
5. NetworkPolicy egress verso DNS e API provider consentite; ingress solo dal
   controller Ingress e dai client interni autorizzati.
6. Conservare i secret in SOPS e iniziare con `REQUIRE_API_KEY=true`; completare
   onboarding/password prima di considerare il servizio pronto all'uso.

