# 🔄 Üretim Ortamında Geri Alma (Rollback) Stratejileri Laboratuvarı
### Google Online Boutique — Acil Durum Kurtarma & Felaket Senaryoları (Disaster Recovery)

Bu laboratuvar, canlıya çıkan yeni bir sürümde beklenmedik bir hata, çökme veya yüksek gecikme (latency) yaşandığında **bir önceki kararlı sürüme nasıl geri dönüleceğini (Rollback)** endüstri standardı 4 farklı yöntemle uygulamalı olarak öğretir.

---

## 🧭 4 Farklı Rollback Yöntemi Karşılaştırması

| Yöntem | Ne Zaman Tercih Edilir? | Kurtarma Süresi (RTO) | Kesinti (Downtime) | Geri Alınan Katman |
|---|---|---|---|---|
| **1. Gateway API Trafik Rollback** | Blue-Green / Canary mimarisinde | **< 1 saniye (Anında)** | **Sıfır Kesinti** | Yönlendirme (HTTPRoute) |
| **2. Kubernetes `rollout undo`** | Standart Deployment güncellemelerinde | ~10 - 20 saniye | Sıfır Kesinti (Rolling) | K8s ReplicaSet |
| **3. Harbor Registry İmaj Rollback** | İmaj bazlı sürüm sabitlemede | ~15 - 30 saniye | Sıfır Kesinti | Konteyner İmajı (`:tag`) |
| **4. GitOps / Git Revert** | Kod seviyesinde kalıcı çözümde | ~2 - 3 dakika (CI/CD süresi) | Sıfır Kesinti | Kaynak Kod (Git Commit) |

---

## 🚨 Senaryo: Canlıya Çıkan Sürümde Hata Tespiti (Incident Tatbikatı)

Farz edelim ki yeşil sürüm (`v2.0.0`) canlıya alındı fakat kullanıcılar sepet veya ödeme adımında hata almaya başladı. Sistem yöneticisi ve nöbetçi DevOps mühendisi olarak acil kurtarma operasyonunu başlatıyoruz.

---

## 🛠️ YÖNTEM 1: Gateway API ile Anında Trafik Geri Alma (En Hızlı Yöntem)

Eğer sistemde Blue-Green altyapısı kuruluysa, podları yeniden başlatmaya gerek kalmadan canlı kullanıcı trafiğini **1 saniyede** stabil mavi sürüme döndürebilirsiniz.

### 🌐 Yol A: Jenkins Üzerinden Tek Tıkla
1. Jenkins'te **`Online-Boutique-Blue-Green-Switch`** işini açın.
2. **Build with Parameters** butonuna basın.
3. Strateji olarak **`BLUE (100% Blue - Instant Rollback)`** seçin.
4. **Build** butonuna basın.
5. `https://student<ID>-app1.devopsatolyesi.com` adresini yenileyin.
   * **Sonuç:** Sitenin banner'ı yeşilden **anında masmavi `v1.0.0` sürümüne dönecek**, hatalar sıfıra inecektir.

### 💻 Yol B: Terminalden Tek Komutla (Acil Müdahale)
```bash
# Gateway rotasındaki trafiği %100 BLUE sürümüne çevirin:
kubectl patch httproute frontend-route -n default --type='json' -p='[
  {"op": "replace", "path": "/spec/rules/0/backendRefs/0/weight", "value": 100},
  {"op": "replace", "path": "/spec/rules/0/backendRefs/1/weight", "value": 0}
]'

# Doğrulama:
kubectl describe httproute frontend-route -n default | grep -A 5 "Backend Refs"
```

---

## 🛠️ YÖNTEM 2: Kubernetes Native Rollback (`kubectl rollout undo`)

Gateway API kullanılmayan klasik Kubernetes dağıtımlarında, Kubernetes'in tuttuğu geçmiş ReplicaSet revizyonları kullanılarak geri alma yapılır.

### 1. Dağıtım Geçmişini İnceleme:
```bash
kubectl rollout history deployment/frontend -n default
```
Çıktı örneği:
```text
REVISION  CHANGE-CAUSE
1         kubectl apply --filename=frontend.yaml (Stabil Mavi v1)
2         kubectl set image deployment/frontend server=frontend:v2 (Hatalı Yeşil v2)
```

### 2. Bir Önceki Revizyona Anında Geri Dönme:
```bash
# Bir önceki revizyona geri dön (Revision 1):
kubectl rollout undo deployment/frontend -n default

# İstenen belirli bir revizyona geri dönmek için:
kubectl rollout undo deployment/frontend -n default --to-revision=1
```

### 3. Geri Alma Durumunu Canlı İzleme:
```bash
kubectl rollout status deployment/frontend -n default
```
Kubernetes sırayla yeni podları sonlandırır ve eski stabil podları ayağa kaldırır (`RollingUpdate`).

---

## 🛠️ YÖNTEM 3: Harbor OCI Registry Üzerinden İmaj Etiketi ile Geri Alma

Harbor üzerinde her derleme benzersiz bir numara ile etiketlenir (`:1`, `:2`, `:3`, `:4`, vb.). Eğer son derlenen imaj (`:5`) hatalıysa, Kubernetes deployment'ı önceki stabil imaj etiketine sabitlenir.

### 1. Harbor'daki Mevcut İmajları Görme:
Tarayıcınızda açın: `https://student<ID>-harbor.devopsatolyesi.com` ➔ `ecommerce` projesi ➔ `online-boutique-frontend`.  
Burada geçmiş build etiketlerini (Örn: `1`, `2`, `3`) görebilirsiniz.

### 2. İmajı Önceki Sağlam Sürüme Sabitleme:
```bash
# Frontend konteynerinin imajını doğrudan Harbor'daki stabil sürüme çekin:
kubectl set image deployment/frontend \
  server=student100-harbor.devopsatolyesi.com/ecommerce/online-boutique-frontend:1 \
  -n default

# Podların yeni imajla başladığını doğrulayın:
kubectl get pods -l app=frontend -o jsonpath='{.items[*].spec.containers[*].image}'
```

---

## 🛠️ YÖNTEM 4: GitOps & SCM Geri Alma (Kalıcı & Denetlenebilir Çözüm)

Üretim ortamındaki acil yangın Gateway API veya `kubectl rollout undo` ile söndürüldükten sonra, kod reposundaki hatayı kalıcı olarak geri almak için **Git Revert** kullanılır:

```bash
cd ~/ecommerce-kind-gateway-cicd

# Son hatalı commit'i geri alan yeni bir ters commit oluşturun:
git revert HEAD --no-edit

# GitHub'a push edin:
git push origin main
```

* **Sonuç:** Jenkins açık olan boru hattı üzerinden temiz kodu çeker, Go testlerini çalıştırır, SonarQube'dan geçirir ve kümeye temiz versiyonu yeniden dağıtır. Bu sayede Git geçmişi bozulmaz ve yapılan geri alma işlemi denetim (audit) loglarında kayıt altına alınır.

---

## 📊 Grafana'da Rollback Etkisini Doğrulama

Rollback yapıldığı anda Grafana paneline (`https://student<ID>-grafana.devopsatolyesi.com`) bakın:

1. **HTTP Status Codes:** Fırlayan HTTP 5xx hata grafiğinin anında sıfıra düştüğünü göreceksiniz.
2. **Request Latency (p95):** Yanıt sürelerinin anında 10-20 milisaniye seviyesine gerilediğini izleyin.
3. **Deployment Annotation:** Rollback yapılan zaman damgasında dikey bir işaret belirecektir.
