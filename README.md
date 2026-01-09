# K3s Homelab Infrastructure

A production-grade home media server and automation platform built with Infrastructure as Code principles, leveraging Kubernetes, GitOps, and modern DevOps practices.


![](diagrams/media-stack.drawio.png)

## 🎯 Project Overview

This repository demonstrates a complete infrastructure-as-code implementation for a self-hosted media server environment. It showcases automated provisioning, declarative configuration management, and GitOps workflows using industry-standard tools.

## 🏗️ Architecture

### Infrastructure Layer
- **K3s Cluster**: Lightweight Kubernetes distribution optimized for edge computing
- **Terraform**: Infrastructure provisioning and configuration management
- **DAS - JBOD (MergerFS) Storage**: Centralized persistent storage for media and application data
- **MetalLB**: Bare-metal load balancer for service exposure
- **Traefik**: Cloud-native ingress controller with automatic HTTPS

### GitOps Layer
- **FluxCD**: Continuous delivery and automated deployments
- **GitHub App Authentication**: Secure repository access
- **SOPS + Age**: Encrypted secrets management
- **Gateway API**: Next-generation ingress specification

## 🚀 Deployed Services

## Infrastructure & Networking

- <img src="https://artifacthub.io/image/77a66245-d325-4c09-815f-75344b3eb82c@3x" width="16" height="16" alt="cert-manager"> **[cert-manager](https://cert-manager.io/)**: X.509 certificate management for Kubernetes
- <img src="https://uptime.kuma.pet/img/icon.svg" width="16" height="16" alt="uptime-kuma"> **[uptime-kuma](https://github.com/louislam/uptime-kuma)**: Self-hosted uptime monitoring tool
- <img src="https://upload.wikimedia.org/wikipedia/commons/1/17/Flux_color_logo.png" width="16" height="16" alt="flux"> **[flux](https://fluxcd.io/)**: GitOps continuous delivery for Kubernetes
- <img src="https://github.com/homebridge/branding/raw/latest/logos/homebridge-color-round.svg" width="16" height="16" alt="homebridge"> **[homebridge](https://homebridge.io/)**: HomeKit support for smart home devices
- <img src="https://www.miamammausalinux.org/wp-content/uploads/2019/11/logo_coredns-1.png" width="16" height="16" alt="coredns"> **[coredns](https://coredns.io)**:  Core DNS service
- <img src="https://raw.githubusercontent.com/kubernetes/kubernetes/master/logo/logo.svg" width="16" height="16" alt="metrics-server"> **[metrics-server](https://github.com/kubernetes-sigs/metrics-server)**: Kubernetes resource metrics aggregator
- <img src="https://metoro.io/static/images/Metoro_16_9.svg" width="16" height="16" alt="metoro">  **[metoro-exporter](https://metoro.io/)**: Platform for Observability
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cloudflare.svg" width="16" height="16" alt="cloudflared"> **[cloudflared](https://github.com/cloudflare/cloudflared)**: Cloudflare Tunnel client
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/duplicati.svg" width="16" height="16" alt="duplicati"> **[duplicati](https://www.duplicati.com/)**: Encrypted backup solution
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/metallb.svg" width="32" height="16" alt="metallb"> **[metallb](https://metallb.universe.tf/)**: Load balancer for bare metal Kubernetes
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/traefik.svg" width="32" height="16" alt="traefik"> **[traefik](https://traefik.io/)**: Cloud-native reverse proxy and load balancer

## Media Management

- <img src="https://raw.githubusercontent.com/morpheus65535/bazarr/master/frontend/public/images/logo128.png" width="16" height="16" alt="bazarr"> **[bazarr](https://www.bazarr.media/)**: Subtitle management for Sonarr and Radarr
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/fileflows.svg" width="16" height="16" alt="fileflows"> **[fileflows](https://fileflows.com/)**: File processing and automation workflows
- <img src="https://raw.githubusercontent.com/FlareSolverr/FlareSolverr/master/resources/flaresolverr_logo.svg" width="16" height="16" alt="flaresolverr"> **[flaresolverr](https://github.com/FlareSolverr/FlareSolverr)**: Proxy server to bypass Cloudflare protection
- <img src="https://avatars.githubusercontent.com/u/122929872?v=4" width="16" height="16" alt="homepage"> **[homepage](https://gethomepage.dev/)**: Customizable application dashboard
- <img src="https://raw.githubusercontent.com/Fallenbagel/jellyseerr/develop/public/logo_full.svg" width="32" height="16" alt="jellyseerr"> **[jellyseerr](https://github.com/Fallenbagel/jellyseerr)**: Media request management for Jellyfin/Plex
- <img src="https://play-lh.googleusercontent.com/QO403y5ms9nf7AS8n1rAc8K2k1dXqYjUBOyAaJMvR33a71vH6IYplZPdcJGw2YRRmo8" width="16" height="16" alt="plex"> **[PlexTraktSync](https://github.com/Taxel/PlexTraktSync)**: Sync Plex views to Trakt.tv
- <img src="https://images.seeklogo.com/logo-png/45/2/plex-tv-logo-png_seeklogo-450440.png" width="16" height="16" alt="plex"> **[plex-media-server](https://www.plex.tv/)**: Media server and streaming platform
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/profilarr.svg" width="16" height="16" alt="plex"> **[profilarr](https://github.com/Dictionarry-Hub/profilarr)**: Profile management for Sonarr/Radarr
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/prowlarr.svg" width="16" height="16" alt="prowlarr"> **[prowlarr](https://prowlarr.com/)**: Indexer manager for *arr applications
- <img src="https://raw.githubusercontent.com/qbittorrent/qBittorrent/master/src/icons/qbittorrent-tray.svg" width="16" height="16" alt="qbittorrent"> **[qbittorrent](https://www.qbittorrent.org/)**: BitTorrent client
- <img src="https://radarr.video/img/logo.png" width="16" height="16" alt="radarr"> **[radarr](https://radarr.video/)**: Movie collection manager
- <img src="https://sonarr.tv/img/logo.png" width="16" height="16" alt="sonarr"> **[sonarr](https://sonarr.tv/)**: TV series collection manager
- <img src="https://sonarr.tv/img/logo.png" width="16" height="16" alt="sonarr - animeworld"> **[sonarr-animeworld](https://github.com/MainKronos/Sonarr-AnimeDownloader)**: TV series collection manager specific for anime
- <img src="https://tautulli.com/images/logo.png" width="16" height="16" alt="tautulli"> **[tautulli](https://tautulli.com/)**: Plex analytics and monitoring

## Gaming
- <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/romm.svg" width="16" height="16" alt="RomM"> **[RomM](https://romm.app)**: Rom Manager and Player 
- <img src="https://github.com/Maikboarder/Playerr/blob/master/frontend/public/favicon.png?raw=true" width="16" height="16" alt="Playerr"> **[Playerr](https://github.com/Maikboarder/Playerr)**: Arr Stack for gaming


## Utilities

- 🐇 **[speedtest-tracker](https://github.com/alexjustesen/speedtest-tracker)**: Network speed monitoring and tracking
- <img src="https://img.icons8.com/ios_filled/512/spotify.png" width="16" height="16" alt="your_spotify"> **[Your Spotify](https://github.com/Yooooomi/your_spotify)**: Self hosted Spotify tracking dashboard
## 📋 Key Features

### Infrastructure as Code
- Fully automated cluster provisioning
- Remote execution for initial setup
- Version-controlled infrastructure state

### GitOps Workflow
- Automated deployments via FluxCD
- Git as single source of truth
- Encrypted secrets in repository
- Self-healing cluster state

### Security Best Practices
- SSH key-based authentication
- Encrypted secrets management (SOPS + Age)
- GitHub App authentication (no personal tokens)
- SELinux context management
- Least privilege access patterns

### Scalability & Reliability
- Managed Kubernetes fields (labels, taints)
- Automated backup schedules
- Health monitoring and analytics



## 🔐 Security Considerations

This is a homelab environment with appropriate security measures:
- Private network deployment
- Encrypted secrets in repository
- No hardcoded credentials
- SSH key authentication
- SELinux enforcement
- Regular automated backups


## 🤝 Contributing

This is a personal homelab project showcasing infrastructure skills. Feel free to use it as inspiration for your own setup!

## 📄 License

MIT License - feel free to use and adapt for your own projects.

---

**Note**: This repository demonstrates production-ready practices in a homelab context. Sensitive values are managed via environment variables and encrypted secrets, never committed in plain text.
