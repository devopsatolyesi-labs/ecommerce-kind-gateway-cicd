# 📖 Google Online Boutique — Tam Kurulum & Operasyon Kılavuzu (A'dan Z'ye)
### DevOps Lab Platformu: Kubernetes Gateway API, JCasC, Harbor, Observability & Progressive Delivery

Bu doküman, eğitim platformundaki **tüm bileşenlerin sıfırdan nasıl kurulduğunu, birbirleriyle nasıl haberleştiğini, portlarını, güvenlik ayarlarını ve olası arıza durumlarında nasıl müdahale edileceğini** eksiksiz ve adım adım açıklamaktadır.

---

## 🗺️ 1. Genel Mimari & Ağ Topolojisi

Sistem, tek bir Linux sunucusu (GCP Compute Engine e2-standard-4 / 16 GB RAM / Ubuntu 24.04 LTS) üzerinde konteyner ve Kubernetes tabanlı olarak çalışır:

```mermaid
flowchart TD
    INTERNET[Kullanıcılar & Öğrenciler] -->|Cloudflare HTTPS :443| NGINX[Host Nginx Reverse Proxy]

    subgraph Host_Ports [Host Loopback Servis Portları]
        NGINX -->|student100-cockpit| COCKPIT[Cockpit Web Terminal :9090]
        NGINX -->|student100-jenkins| JENKINS[Jenkins as Code :18080]
        NGINX -->|student100-sonarqube| SONAR[SonarQube v10 :19000]
        NGINX -->|student100-harbor| HARBOR[Harbor OCI Registry :18082]
        NGINX -->|student100-prometheus| PROM[Prometheus :19090]
        NGINX -->|student100-grafana| GRAF[Grafana :13000]
        NGINX -->|student100-app1| TRAEFIK[Traefik Gateway :18081 -> NodePort 30080]
    end

    subgraph Kind_Cluster [Kind Kubernetes Kümesi]
        TRAEFIK --> GW[Gateway API / HTTPRoute]
        GW --> FE_BLUE[Frontend Blue :80]
        GW --> FE_GREEN[Frontend Green :80]
        FE_BLUE --> SERVICES[10 Backend Mikroservis<br>cart, payment, catalog, shipping vb.]
    end

    subgraph Observability_Stack [Gözlemlenebilirlik Altyapısı]
        PROM -->|Scrape 30100| TRAEFIK_METRICS[Traefik Metrics]
        PROM -->|Scrape 8080| CADVISOR[cAdvisor :8080 - 144 Container]
        PROM -->|Scrape 9100| NODE_EXP[Node Exporter :9100 - Host OS]
        LOKI[Loki :3100] <-- PROMTAIL[Promtail]
        PROMTAIL -->|Logs| LOG_SOURCES[Jenkins + Docker + Linux /var/log]
        GRAF --> PROM
        GRAF --> LOKI
        PROM --> ALERTMGR[Alertmanager :9093] --> TELEGRAM[Telegram Bot]
    end
```

---

## 📋 2. Servis Port & Erişim Fihristi

| Servis Adı | Canlı HTTPS Adresi | Dahili Host Portu | Yetkilendirme (Kullanıcı / Şifre) |
|---|---|---|---|
| **Cockpit Web Terminal** | `https://student100-cockpit.devopsatolyesi.com` | `127.0.0.1:9090` | `student` / `BilgincIT454` |
| **Jenkins as Code** | `https://student100-jenkins.devopsatolyesi.com` | `127.0.0.1:18080` | `admin` / `BilgincIT454` |
| **SonarQube v10** | `https://student100-sonarqube.devopsatolyesi.com` | `127.0.0.1:19000` | `admin` / `admin` (veya `BilgincIT454`) |
| **Harbor OCI Registry** | `https://student100-harbor.devopsatolyesi.com` | `127.0.0.1:18082` | `admin` / `BilgincIT454` (Pull: Herkese Açık) |
| **Prometheus** | `https://student100-prometheus.devopsatolyesi.com` | `127.0.0.1:19090` | Doğrudan Açık |
| **Grafana** | `https://student100-grafana.devopsatolyesi.com` | `127.0.0.1:13000` | `admin` / `BilgincIT454` |
| **Online Boutique Mağaza** | `https://student100-app1.devopsatolyesi.com` | `127.0.0.1:18081` | Herkese Açık |

---

## 🛠️ 3. Adım Adım Kurulum Kılavuzu

### 3.1. Sunucu Hazırlığı & Temel Paketler
Ubuntu 24.04 üzerinde Docker, Nginx, jq, curl ve git kurulur:
```bash
sudo apt-get update && sudo apt-get install -y docker.io nginx curl jq git unzip
sudo systemctl enable --now docker nginx
sudo usermod -aG docker student
```

### 3.2. Kind Kümesi & Traefik v3 Gateway API Kurulumu
1. **Kind Kümesi:** 30080 (HTTP), 30443 (HTTPS) ve 30100 (Metrikler) port eşlemeleriyle ayağa kaldırılır:
   ```bash
   cat << 'EOF' > /tmp/kind-config.yaml
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   name: ecommerce-kind-cluster
   nodes:
   - role: control-plane
     extraPortMappings:
     - containerPort: 30080
       hostPort: 18081
     - containerPort: 30100
       hostPort: 30100
   EOF
   kind create cluster --config /tmp/kind-config.yaml
   ```
2. **Gateway API CRD'leri:**
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
   ```
3. **Traefik v3 Helm Kurulumu:**
   `traefik/traefik-values.yaml` üzerinden Traefik Gateway Controller olarak kurulur ve metrikleri NodePort 30100 ile açılır.

### 3.3. Harbor OCI Registry v2.12 Kurulumu
1. `/opt/harbor/harbor.yml` dosyasında `hostname: student100-harbor.devopsatolyesi.com` ve `http.port: 18082` ayarlanır (`https` Nginx'e bırakılır).
2. `./install.sh` çalıştırılarak konteynerler ayağa kaldırılır.
3. Otomatik olarak public `ecommerce` projesi açılır:
   ```bash
   curl -u admin:BilgincIT454 -X POST http://127.0.0.1:18082/api/v2.0/projects \
     -H "Content-Type: application/json" \
     -d '{"project_name": "ecommerce", "metadata": {"public": "true"}}'
   ```

### 3.4. SonarQube v10 Kurulumu
1. Konteyner başlatma:
   ```bash
   docker run -d --name training-sonarqube \
     -p 127.0.0.1:19000:9000 \
     -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
     --restart always \
     sonarqube:10-community
   ```
2. Analiz belirteci (token) oluşturma:
   ```bash
   curl -u admin:admin -X POST "http://127.0.0.1:19000/api/user_tokens/generate?name=jenkins-pipeline"
   ```

### 3.5. Jenkins as Code (JCasC) Kurulumu
1. Dockerfile (`jenkins-as-code/Dockerfile`) ile Docker CLI, kubectl, Helm ve SonarScanner içeren özel imaj derlenir:
   ```bash
   docker build -t ecommerce-jenkins:latest jenkins-as-code/
   ```
2. Docker socket ve kubeconfig bağlanarak Jenkins çalıştırılır:
   ```bash
   docker run -d --name training-jenkins \
     -p 127.0.0.1:18080:8080 \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v /var/jenkins_home:/var/jenkins_home \
     -e CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs/jenkins.yaml \
     ecommerce-jenkins:latest
   ```
3. `jenkins-as-code/jenkins.yaml` dosyası ile 2 adet boru hattı (CI/CD ve Blue-Green Switch) otomatik olarak oluşturulur.

### 3.6. Tam Teşekküllü Gözlemlenebilirlik (Monitoring Stack)
`monitoring/docker-compose.yaml` ile tek komutla ayağa kaldırılır:
```bash
cd monitoring && docker compose up -d
```
* **Prometheus (`19090`):** 4 hedefi düzenli tarar (`prometheus`, `node-exporter`, `cadvisor`, `traefik-gateway-api:30100`).
* **Loki (`3100`) & Promtail:** Jenkins derleme loglarını (`/var/jenkins_home/jobs/**/builds/**/log`), Docker loglarını (`/var/lib/docker/containers/*/*-json.log`) ve `/var/log/*log` dosyalarını toplar.
* **Alertmanager (`9093`):** Hata oranları fırladığında Telegram botuna anında HTML bildirim basar.
* **Grafana (`13000`):** Otomatik olarak 2 kurumsal dashboard ile açılır.

---

## 🔄 4. CI/CD Boru Hattı Adımları (Jenkinsfile)

1. **Stage 1: Checkout SCM:** GitHub deposundan en güncel kodun klonlanması.
2. **Stage 2: Multi-Microservice Unit Tests:** `golang:alpine` konteyneri içinde `frontend`, `productcatalogservice` ve `shippingservice` mikroservislerinin birim testlerinin çalıştırılması.
3. **Stage 3: SonarQube Code Quality Gate:** Statik kod analizi, kod kokuları (code smells) ve güvenlik açıklarının taranması.
4. **Stage 4: Docker Multi-Stage Build:** `online-boutique-frontend` imajının optimize derlenmesi.
5. **Stage 5: Container Security Scan (Trivy):** Konteyner imajının CVE güvenlik açıklarına karşı taranması.
6. **Stage 6: Harbor Registry Push & Kind Load:** İmajın Harbor deposuna push edilmesi ve Kind kümesine yüklenmesi.
7. **Stage 7: Deploy to Kubernetes (Gateway API):** 11 mikroservisin Kind kümesine dağıtılması.
8. **Stage 8: Automated Smoke Test:** Gateway API üzerinden canlı HTTP 200 testi.
9. **Stage 9: Automated Load & Performance Test (K6):** 50 eşzamanlı sanal kullanıcı (VU) ile sisteme yük bindirilerek Grafana'da metriklerin canlandırılması.

---

## 🔵🟢 5. Blue-Green Dağıtım & Rollback Operasyonu

Trafik geçişleri `Online-Boutique-Blue-Green-Switch` Jenkins işi üzerinden tek tıkla yapılır:

* **Cutover (Yeşile Geçiş):** `STRATEGY = GREEN` seçildiğinde Traefik Gateway API `HTTPRoute` ağırlığı `%100 Green / %0 Blue` yapılır. Mağaza görseli Cymbal Modern Shops temasına döner.
* **Instant Rollback (Geri Alma):** `STRATEGY = BLUE` seçildiğinde **1 saniyeden kısa sürede** trafik Mavi stabil sürüme geri çekilir.
* **Canary Test:** `STRATEGY = CANARY` seçilerek `%80 Mavi / %20 Yeşil` ağırlıklı dağıtım test edilir.
* **Alternatif Kurtarma Yöntemleri:** `kubectl rollout undo`, Harbor imaj etiketi sabitleme ve `git revert` adımları için [docs/ROLLBACK_STRATEGIES_LAB.md](ROLLBACK_STRATEGIES_LAB.md) kılavuzuna bakın.

---

## 🚨 6. Sık Karşılaşılan Sorunlar & Hızlı Kurtarma (Troubleshooting)

### Soru 1: SonarQube 401 Unauthorized verirse ne yapmalıyım?
1. `curl -u admin:admin -X POST 'http://127.0.0.1:19000/api/user_tokens/generate?name=jenkins-pipeline'` ile yeni bir token alın.
2. `jenkins-as-code/jenkins.yaml` dosyasındaki `sonar-token` alanını güncelleyin ve JCasC reload yapın.

### Soru 2: Grafana'da Traefik veya Konteyner verileri görünmüyor?
1. `curl http://127.0.0.1:30100/metrics | head` komutunu çalıştırın.
2. Prometheus arayüzünde (`https://student100-prometheus.devopsatolyesi.com/targets`) `cadvisor` ve `traefik` hedeflerinin yeşil (**UP**) olduğunu doğrulayın.

### Soru 3: Podlar ayağa kalkmıyor veya CrashLoopBackOff veriyor?
1. `kubectl get pods -n default` ile durumları listeleyin.
2. `kubectl logs <pod-name> -n default` ile eksik ortam değişkenlerini kontrol edin.
