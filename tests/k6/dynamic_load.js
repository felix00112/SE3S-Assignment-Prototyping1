import http from 'k6/http';
import { check } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
import { baseUrl, buildDynamicOptions, eventId } from './lib/config.js';

export const options = buildDynamicOptions();

export default function () {
  const userId = uuidv4();
  const url = `${baseUrl}/events/${eventId}/book`;

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
