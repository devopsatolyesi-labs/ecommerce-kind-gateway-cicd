# 🏛️ DevOps Platform Mimari Tasarımı & Eğitim Notları
### Google Online Boutique — Gateway API, JCasC, Harbor & Full-Stack Observability

Bu doküman, kurumsal DevOps eğitiminde öğrencilere aktarılacak temel mimari kararları, endüstri standartlarını ve kullanılan teknolojilerin "neden" seçildiğini derinlemesine açıklar.

---

## 1. Neden Klasik Ingress Yerine Kubernetes Gateway API (Traefik v3)?

Kubernetes topluluğu, 2015 yılında tasarlanan klasik `Ingress` kaynağının modern mikroservis ihtiyaçlarına yetersiz kaldığını görerek **Kubernetes Gateway API** standardını geliştirmiştir.

```mermaid
graph TD
    subgraph Rol_1_Altyapi_Ekibi [1. Altyapı / Platform Mühendisi]
        GC[GatewayClass: Traefik Controller]
        GW[Gateway: Port 80/443, TLS, Domainler]
    end

    subgraph Rol_2_Uygulama_Gelistirici [2. Uygulama / Yazılım Ekibi]
        HR1[HTTPRoute: / (Frontend Servisi)]
        HR2[HTTPRoute: /cart (Cart Servisi)]
        HR3[HTTPRoute: /canary (v2 A/B Testi)]
    end

    GC --> GW
    GW --> HR1
    GW --> HR2
    GW --> HR3
```

### Temel Farklar & Avantajlar:
1. **Rol Ayrımı (Role-Oriented Design):**
   * Klasik Ingress'te tek bir YAML dosyası hem cluster IP'sini, hem TLS sertifikasını, hem de URL rotalarını içeriyordu. Geliştirici hata yaptığında tüm giriş kapısı çökebiliyordu.
   * Gateway API'de **Altyapı Ekibi** `Gateway` nesnesini (dinlenecek portlar, TLS ve domainler) tanımlar. **Uygulama Ekibi** ise yalnızca kendi servisine giden `HTTPRoute` nesnesini yazar.
2. **Yerel Trafik Bölme (Traffic Splitting & Canary):**
   * Klasik Ingress'te Nginx annotation hileleri (`canary-weight`) gerekirken; Gateway API'de yerel olarak `%80 v1`, `%20 v2` ağırlıklı trafik yönlendirmesi yapılabilir.
3. **Çoklu Namespace Desteği (Cross-Namespace Routing):**
   * Rotalar farklı ad alanlarındaki servislere güvenli bir şekilde bağlanabilir.

---

## 2. Neden Jenkins Configuration as Code (JCasC)?

Geleneksel Jenkins kurulumlarında eklentiler elle kurulur, job'lar arayüzden tek tek tıklanarak açılır ve sunucu çöktüğünde yeniden kurmak günler alırdı.

### JCasC'in Sağladığı Yetenekler:
* **Her Şey Kod Olarak (GitOps):** Kullanıcılar (`admin`, `student`), SonarQube bağlantısı, Harbor şifresi ve Pipeline işleri tek bir `jenkins.yaml` dosyası ile tanımlanır.
* **Sıfır Felaket Riski (Disaster Recovery):** Jenkins sunucusu tamamen silinse dahi, yeni bir konteyner 10 saniye içinde tüm geçmiş konfigürasyonuyla ayağa kalkar.
* **Eğitimde Standartlaşma:** 50 öğrencinin tamamı saniyeler içinde hatasız, birebir aynı Jenkins ortamına sahip olur.

---

## 3. Neden Harbor OCI Registry?

Eğitimlerde genellikle Docker Hub kullanılır; fakat kurumsal şirketlerde kaynak kodlar ve imajlar asla halka açık depolarda tutulmaz.

### Harbor Tercih Nedenleri:
* **Özel & Yerel (Private & In-House):** Şirket ağında veya öğrenci sunucusunda bağımsız çalışır.
* **Zafiyet Tarama (Trivy Entegrasyonu):** İmaj push edildiğinde arka planda otomatik güvenlik taraması yapar.
* **Rol Tabanlı Erişim (RBAC):** Projeler bazında geliştirici ve CI/CD bot (Robot Account) izinleri ayrıştırılır.
* **Helm & OCI Desteği:** Yalnızca Docker imajlarını değil, Helm chart paketlerini de OCI formatında saklar.

---

## 4. Gözlemlenebilirlik (Observability) Mimarisi

Modern sistemlerde problem çözmek için 3 temel sinyal birlikte kullanılmalıdır:

```
                  ┌───────────────────────────────┐
                  │      GRAFANA BİRLEŞTİRİCİ     │
                  └───────┬───────────────┬───────┘
                          │               │
            ┌─────────────┴─────┐   ┌─────┴─────────────┐
            │ Prometheus (METRİK)│   │  Grafana Loki (LOG)│
            └─────────────┬─────┘   └─────┬─────────────┘
                          │               │
               ┌──────────┴───────────────┴──────────┐
               │    Online Boutique Mikroservisleri  │
               └─────────────────────────────────────┘
```

1. **Metrikler (Prometheus):** 
   * *"Sistemde ne oluyor ve hızımız ne?"*
   * Traefik üzerinden geçen saniyelik istek (RPS), HTTP hata oranları (5xx) ve gecikme (p95 latency).
2. **Loglar (Grafana Loki):**
   * *"Hatanın sebebi ve satır numarası ne?"*
   * Jenkins konsol çıktıları, Docker konteyner logları ve Linux çekirdek logları.
3. **Alarmlar (Alertmanager + Telegram):**
   * *"Bir şeyler bozulduğunda mühendisi nasıl uyandırırız?"*
   * Eşik aşıldığında Telegram veya Slack'e saniyeler içinde düşen bildirimler.
