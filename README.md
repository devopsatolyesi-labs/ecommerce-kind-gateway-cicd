# Google Online Boutique — Cloud-Native CI/CD & Traefik v3 Gateway API Platform

Bu proje, Google Cloud'un 10 mikroservisten oluşan **Online Boutique** referans e-ticaret mimarisini temel alan; klasik Nginx Ingress yerine yeni nesil **Kubernetes Gateway API (Traefik v3)** ile dış dünyaya açılan, uçtan uca **Jenkins**, **SonarQube**, **Trivy** ve **Harbor** entegrasyonuna sahip kurumsal bir DevOps & DevSecOps teslimat platformudur.

---

## 🏛️ Mimari ve Bileşenler

```mermaid
flowchart TD
    subgraph SCM [Kaynak Kod & Sürüm Kontrolü]
        GIT[Git Repository / GitHub]
    end

    subgraph CI_CD [Sürekli Entegrasyon & Güvenlik Hattı (Jenkins)]
        STAGE1[1. SCM Checkout]
        STAGE2[2. Go Unit Tests & Coverage]
        STAGE3[3. SonarQube Quality Gate]
        STAGE4[4. Multi-Stage Docker Build]
        STAGE5[5. Trivy CVE Security Scan]
        STAGE6[6. Harbor Registry Push]
    end

    subgraph K8S [Kubernetes / Kind Kümesi]
        subgraph GATEWAY [Traefik v3 Gateway API Katmanı]
            GC[GatewayClass: traefik]
            GW[Gateway: boutique-gateway]
            ROUTE[HTTPRoute: frontend-route]
        end

        subgraph MICROSERVICES [Online Boutique Servisleri]
            FRONTEND[Frontend Web Service]
            CART[Cart Service - Redis]
            CATALOG[Product Catalog Service]
            CURRENCY[Currency Service]
            PAYMENT[Payment Service]
            SHIPPING[Shipping Service]
            CHECKOUT[Checkout Service]
            EMAIL[Email Service]
            RECOM[Recommendation Service]
            AD[Ad Service]
        end
    end

    GIT --> STAGE1 --> STAGE2 --> STAGE3 --> STAGE4 --> STAGE5 --> STAGE6
    STAGE6 -->|Deploy| K8S

    CLIENT[Kullanıcı / Tarayıcı] -->|ecommerce.devopsatolyesi.com| GW
    GW --> ROUTE --> FRONTEND
    FRONTEND --> CART & CATALOG & CURRENCY & CHECKOUT & SHIPPING & RECOM & AD
```

---

## 🌟 Neden Kubernetes Gateway API & Traefik v3?

Geleneksel `Ingress (networking.k8s.io/v1)` kaynakları sınırlı özellik setine sahiptir ve yönlendirme (routing), başlık manipülasyonu, yetkilendirme gibi gelişmiş ihtiyaçlar için controller'a özel karmaşık annotation'lara bağımlıdır.

**Kubernetes Gateway API (`gateway.networking.k8s.io/v1`)** ise Kubernetes SIG-Network tarafından tasarlanan yeni nesil standarttır:
* **Rol Tabanlı Ayrım:** Altyapı ekipleri `GatewayClass` ve `Gateway` tanımlarken; uygulama ekipleri bağımsız olarak `HTTPRoute`, `GRPCRoute` veya `TCPRoute` yönetebilir.
* **Traefik v3 Entegrasyonu:** Traefik v3, Gateway API spesifikasyonunu yerel (native) olarak destekler; zengin dahili web arayüzü (Dashboard), otomatik yönlendirme ve Prometheus metrikleri sunar.
* **Standart Taşınabilirlik:** Vendor-lockin olmaksızın farklı bulut sağlayıcıları ve gateway controller'ları arasında aynı route tanımları çalışır.

---

## 🚀 Hızlı Başlangıç & Adım Adım Kurulum

### 1. Ön Koşullar
* Çalışan bir Kubernetes kümesi (`kind`, `k3s`, `minikube` veya `EKS/GKE`)
* `kubectl` (v1.28+)
* `helm` (v3.12+)
* `curl` ve `jq`

### 2. Traefik v3 ve Gateway API Kurulumu
Kubernetes Gateway API resmi standart CRD'lerini ve Traefik v3 controller'ını tek komutla kurun:

```bash
chmod +x scripts/*.sh
./scripts/setup-traefik-gateway.sh
```

Kurulumu doğrulayın:
```bash
kubectl get gatewayclasses,gateways -A
```

Çıktıda `traefik` sınıfının ve `boutique-gateway` kaynağının hazır (`Programmed=True`) olduğunu teyit edin.

### 3. Online Boutique Mikroservislerini Dağıtma
Tüm mikroservisleri ve Gateway API `HTTPRoute` kuralını uygulayın:

```bash
./scripts/deploy-boutique.sh
```

Dağıtım durumunu izleyin:
```bash
kubectl get pods -w
kubectl get httproutes
```

### 4. Doğrulama ve Sağlık Testi
Sistemin tüm bileşenlerini otomatik olarak test edin:

```bash
./scripts/validate.sh
```

---

## 🛡️ CI/CD & DevSecOps Pipeline (Jenkinsfile)

Proje kök dizinindeki `Jenkinsfile`, kurumsal ölçekte bir DevSecOps boru hattı uygular:

1. **Unit Tests & Code Coverage:** Go birim testleri koşturulur ve `coverage.out` üretilir.
2. **SonarQube Quality Gate:** Statik kod analizi yapılır. Kod kokuları, güvenlik açıkları veya zafiyetler tanımlı eşikleri aşarsa boru hattı durdurulur (`waitForQualityGate()`).
3. **Multi-Stage Docker Build:** Uygulama minimal ve güçlendirilmiş (hardened) imaj olarak derlenir.
4. **Trivy Container Security Gate:** Derlenen imaj `HIGH` ve `CRITICAL` seviyesindeki CVE'ler için taranır. Kritik zafiyet tespit edilirse dağıtım engellenir.
5. **Harbor Registry Push:** İmaj güvenli özel imaj deposuna (`harbor.devopsatolyesi.com`) etiketlenerek aktarılır.
6. **Zero-Downtime Rollout:** Kubernetes kümesine güncel imajla kesintisiz güncelleme başlatılır.

---

## 🔧 Dizin Yapısı

```text
.
├── gateway-api/
│   ├── 01-gateway-class.yaml     # Traefik v3 GatewayClass tanımı
│   ├── 02-gateway.yaml           # HTTP & HTTPS dinleyici tanımları
│   └── 03-httproute.yaml         # Frontend yönlendirme kuralları
├── traefik/
│   └── traefik-values.yaml       # Traefik v3 resmi Helm konfigürasyonu
├── scripts/
│   ├── setup-traefik-gateway.sh  # Gateway API ve Traefik kurulum betiği
│   ├── deploy-boutique.sh        # Uygulama ve HTTPRoute dağıtım betiği
│   └── validate.sh               # Otomatik sağlık ve doğrulama denetimi
├── src/                          # 10 Mikroservisin kaynak kodları (Go, Python, Node, C#)
├── release/                      # Kubernetes temel çalışma manifestoları
├── Jenkinsfile                   # Enterprise Declarative CI/CD hattı
├── sonar-project.properties      # SonarQube analiz konfigürasyonu
└── trivy.yaml                    # Trivy güvenlik kapısı kuralları
```

---

## 🌐 Alan Adı ve Erişim

Traefik Gateway API üzerinden yayınlanan adresler:
* **Canlı E-Ticaret Arayüzü:** `https://ecommerce.devopsatolyesi.com` veya `http://localhost:8080`
* **Traefik Web Dashboard:** `http://localhost:9000/dashboard/`

---

## 📞 Destek ve Katkı
Bu proje DevOps Atölyesi Eğitim Programı kapsamında hazırlanmıştır. Sorularınız ve katkılarınız için pull request açabilir veya eğitmeninizle iletişime geçebilirsiniz.
