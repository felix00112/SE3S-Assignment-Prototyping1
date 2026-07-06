import http from 'k6/http';
import { check } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

export const options = {
  vus: 20,          // number of v-users
  duration: '1m',   // test duration
};

const BASE_URL = __ENV.BASE_URL || 'http://api:8000';
const EVENT_ID = __ENV.EVENT_ID || '1';
// replace with 'const EVENT_ID = __ENV.EVENT_ID || '123';' for multiple events

export default function () {
  // Ensure a unique user per request
  const userId = uuidv4();

  const url = `${BASE_URL}/events/${EVENT_ID}/book`;

  const payload = JSON.stringify({
    user_id: userId,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const res = http.post(url, payload, params);

  check(res, {
    'status is 200 or 201': (r) => r.status === 200 || r.status === 201,
  });
}