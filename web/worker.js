import { handle } from './engine.js';
self.onmessage = ({ data: { id, request } }) => {
  try { self.postMessage({ id, result: JSON.parse(handle(JSON.stringify(request))) }); }
  catch (error) { self.postMessage({ id, result: { ok: false, error: `Engine failure: ${error.message}` } }); }
};
