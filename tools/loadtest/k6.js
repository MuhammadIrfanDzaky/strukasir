// Load test kasir. HOST = nama domain server (default app.localhost untuk uji lokal).
// Satu iterasi = satu transaksi kasir: simpan order (1–3 item) + bayar tunai; 10% juga muat menu.
import http from 'k6/http';
import { check } from 'k6';

const tenants = JSON.parse(open('/scripts/tokens.json'));
const BASE = `https://${__ENV.HOST || 'app.localhost'}/api/v1`;
const RATE = Number(__ENV.RATE || 5);

export const options = {
  insecureSkipTLSVerify: true,
  scenarios: {
    kasir: {
      executor: 'constant-arrival-rate',
      rate: RATE, timeUnit: '1s', duration: __ENV.DURATION || '60s',
      preAllocatedVUs: Math.max(20, RATE * 4), maxVUs: Math.max(100, RATE * 10),
    },
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
  thresholds: { 'http_req_duration{ep:save}': ['p(95)<60000'], 'http_req_duration{ep:pay}': ['p(95)<60000'], http_req_failed: ['rate<1'] },
};

const uuid = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
  const r = (Math.random() * 16) | 0;
  return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
});

export default function () {
  const t = tenants[Math.floor(Math.random() * tenants.length)];
  const headers = { Authorization: `Bearer ${t.token}`, Accept: 'application/json', 'Content-Type': 'application/json' };

  if (Math.random() < 0.1) {
    check(http.get(`${BASE}/menu`, { headers, tags: { ep: 'menu' } }), { 'menu 200': (r) => r.status === 200 });
  }

  const items = [];
  let total = 0;
  const count = 1 + Math.floor(Math.random() * 3);
  for (let i = 0; i < count; i++) {
    const p = t.products[Math.floor(Math.random() * t.products.length)];
    const qty = 1 + Math.floor(Math.random() * 2);
    items.push({ id: uuid(), product_id: p.id, qty, modifier_ids: [] });
    total += p.price * qty;
  }

  const id = uuid();
  const save = http.put(`${BASE}/orders/${id}`, JSON.stringify({ items, expected_total: total }), { headers, tags: { ep: 'save' } });
  if (!check(save, { 'save 200': (r) => r.status === 200 })) return;

  const pay = http.post(`${BASE}/orders/${id}/pay`, JSON.stringify({
    expected_total: total,
    payments: [{ id: uuid(), method: 'cash', amount: total, tendered: total }],
  }), { headers, tags: { ep: 'pay' } });
  check(pay, { 'pay 200': (r) => r.status === 200 });
}
