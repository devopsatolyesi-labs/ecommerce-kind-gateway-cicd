# 🧪 Öğrenci Uygulama Laboratuvarı & Alıştırmalar (Hands-On Labs)
### Google Online Boutique — Gateway API & CI/CD Platformu

Bu kılavuz, öğrencilerin sistem üzerinde aktif pratik yapabilmesi, senaryo bazlı sorunları çözebilmesi ve bir DevOps mühendisi gibi düşünebilmesi için hazırlanmış **5 adet uygulamalı alıştırma** içerir.

---

## 🎯 Alıştırma 1: Birim Test Hatası Enjeksiyonu (Test-Driven Failure)

### Hedef:
CI/CD boru hattının hatalı bir kodda build aşamasına geçmeden Stage 2'de güvenle durduğunu doğrulamak.

### Adımlar:
1. `src/frontend/money_test.go` dosyasını açın.
2. Bir testteki beklenen değeri kasıtlı olarak bozun:
   ```go
   // Beklenen sonucu bilerek değiştirin:
   if got != want {
       t.Errorf("Kasıtlı hata: beklenen %v, alınan %v", want, got)
   }
   ```
3. Değişikliği commitleyip Jenkins'ten **"Build Now"** butonuna basın.
4. **Gözlem:** 
   * Pipeline **Stage 2: Unit Tests** aşamasında kırmızıya dönecektir (`FAILURE`).
   * Docker imajı derlenmeyecek, Harbor'a hiçbir hatalı imaj yüklenmeyecek ve canlı ortam korunacaktır.
5. Hatayı düzeltip tekrar commit atın ve boru hattının yeşile döndüğünü görün.

---

## 🎯 Alıştırma 2: Traefik Gateway API ile Canary Dağıtım Yapma

### Hedef:
Gelen canlı trafiğin %80'ini mevcut sürüme, %20'sini yeni bir canary poduna yönlendirmek.

### Adımlar:
1. `gateway-api/03-httproute.yaml` dosyasını açın.
2. `rules` altındaki `backendRefs` kısmına ağırlık (weight) ekleyin:
   ```yaml
   rules:
     - matches:
         - path:
             type: PathPrefix
             value: /
       backendRefs:
         - name: frontend
           port: 80
           weight: 80
         - name: frontend-canary
           port: 80
           weight: 20
   ```
3. Dosyayı uygulayın:
   ```bash
   kubectl apply -f gateway-api/03-httproute.yaml
   ```
4. **Gözlem:**
   * Grafana'daki **Throughput** grafiğinde her iki servise giden trafiğin 4:1 oranında bölündüğünü izleyin.

---

## 🎯 Alıştırma 3: Canlı Telegram Alarmını Tetikleme (Yapay Hata Enjeksiyonu)

### Hedef:
Sistemde HTTP 500 hataları üreterek Prometheus'un `GatewayHighErrorRate` alarmını ateşlemesini ve Telegram'a bildirim gitmesini sağlamak.

### Adımlar:
1. Terminalden Traefik Gateway'e hızlıca arka arkaya 404 ve 500 hataları gönderecek bir döngü başlatın:
   ```bash
   for i in {1..200}; do
     curl -s -o /dev/null -H "Host: student100-app1.devopsatolyesi.com" "http://127.0.0.1:18081/force-error-endpoint"
     sleep 0.1
   done
   ```
2. Tarayıcınızda açın: `https://student<ID>-prometheus.devopsatolyesi.com/alerts`
3. **Gözlem:**
   * `GatewayHighErrorRate` kuralı önce **PENDING**, 2 dakika sonra ise **FIRING** durumuna geçecektir.
   * Telefonunuzdaki Telegram botundan **🚨 [FIRING] GatewayHighErrorRate** bildirimini okuyun.

---

## 🎯 Alıştırma 4: Grafana Loki ile LogQL Arama & Hata Tespiti

### Hedef:
Grafana Explore sekmesinde LogQL kullanarak konteyner logları arasında arama yapmak.

### Adımlar:
1. Grafana menüsünden pusula simgesine (**Explore**) tıklayın.
2. Sol üstteki veri kaynağını **Loki** olarak seçin.
3. Arama kutusuna şu LogQL sorgularını yazıp **Run query** deyin:
   * **Tüm Docker logları:** `{job="docker"}`
   * **İçinde "error" veya "fail" geçen loglar:** `{job="docker"} |= "error"`
   * **Sadece Jenkins derleme çıktıları:** `{job="jenkins"}`
4. **Gözlem:**
   * Hatalı isteklerin log kayıtlarını zaman damgasıyla inceleyin ve **Live** butonuna basarak logların terminal gibi canlı akmasını izleyin.

---

## 🎯 Alıştırma 5: Grafana Snapshot Oluşturup Ekiple Paylaşma

### Hedef:
Gözlemlediğiniz bir anomali grafiğini dondurarak kopyalanabilir bir link üretmek.

### Adımlar:
1. Grafana Dashboard'da sağ üstteki **Share** simgesine tıklayın.
2. **Snapshot** sekmesine geçin.
3. **Expire:** `1 Hour` seçin ve **Local Snapshot** butonuna basın.
4. Üretilen bağlantı linkini gizli sekmede açın.
5. **Gözlem:** Veritabanına gerek kalmadan grafiğin dondurulmuş halini inceleyin.

---

## 🎯 Alıştırma 6: Kubernetes Gateway API ile Blue-Green Dağıtımı & Anında Geri Alma

### Hedef:
Traefik Gateway API üzerinden canlı trafiği tek tıkla kesintisiz olarak Mavi (`v1.0.0`) ve Yeşil (`v2.0.0`) sürümler arasında taşımak.

### Adımlar:
1. Jenkins'te **`Online-Boutique-Blue-Green-Switch`** işini açın.
2. **Build with Parameters** ➔ **`GREEN (100% Green - Cutover to New Version)`** seçip çalıştırın.
3. `https://student100-app1.devopsatolyesi.com` sayfasını yenileyin.
4. **Gözlem:**
   * Sayfa başlığı ve teması masmavi `v1.0.0` halinden, zümrüt yeşili `v2.0.0` yeni nesil temaya anında dönecektir.
   * Grafana Dashboard'da geçiş anında mor bir **Deployment Annotation** belirecektir.
5. Detaylı yönergeler için [docs/BLUE_GREEN_LAB.md](file:///Users/hakan/devops-workspace/ecommerce-kind-gateway-cicd/docs/BLUE_GREEN_LAB.md) kılavuzuna bakın.
