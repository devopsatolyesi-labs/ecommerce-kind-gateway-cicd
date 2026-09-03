import http from 'k6/http';
import { check, sleep } from 'k6';

// K6 Load Testing Script for Google Online Boutique via Traefik Gateway API
export const options = {
  stages: [
    { duration: '5s', target: 20 },  // Ramp up to 20 users
    { duration: '15s', target: 50 }, // Sustained peak at 50 users
    { duration: '5s', target: 0 },   // Ramp down to 0
  ],
  thresholds: {
    http_req_duration: ['p(95)<800'], // 95% of requests must complete below 800ms
    http_req_failed: ['rate<0.05'],   // Less than 5% errors
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://127.0.0.1:18081';
const HOST_HEADER = __ENV.HOST_HEADER || 'student100-app1.devopsatolyesi.com';

const params = {
  headers: {
    'Host': HOST_HEADER,
    'User-Agent': 'k6-load-test-agent',
  },
};

export default function () {
  // 1. Browse Homepage
  const resHome = http.get(`${BASE_URL}/`, params);
  check(resHome, {
    'homepage status 200': (r) => r.status === 200,
  });
  sleep(0.2);

  // 2. View Product Details
  const productIds = [
    'OLJCESPC7Z',
    '66VCHSJNUP',
    '1YMWWN1N4O',
    'L9ECAV7KIM',
    '2ZYFJ3GM2N'
  ];
  const randomProduct = productIds[Math.floor(Math.random() * productIds.length)];
  const resProduct = http.get(`${BASE_URL}/product/${randomProduct}`, params);
  check(resProduct, {
    'product page status 200': (r) => r.status === 200,
  });
  sleep(0.3);

  // 3. Check Cart
  const resCart = http.get(`${BASE_URL}/cart`, params);
  check(resCart, {
    'cart page status 200': (r) => r.status === 200,
  });
  sleep(0.2);
}
