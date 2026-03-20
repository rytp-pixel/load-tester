import http from "k6/http";
import { check, sleep } from "k6";
import { Counter, Rate } from "k6/metrics";

const DEFAULT_TIMEOUT = "30s";
const DEFAULT_SLEEP_SECONDS = 0;

const endpointFailures = new Counter("endpoint_failures");
const checkFailures = new Counter("check_failures");
const successfulChecks = new Rate("successful_checks");

function parseConfig() {
  const configPath = __ENV.CONFIG_PATH || "./k6/config.json";
  const raw = open(configPath);
  const parsed = JSON.parse(raw);
  return parsed;
}

const cfg = parseConfig();

if (!cfg.endpoints || !Array.isArray(cfg.endpoints) || cfg.endpoints.length === 0) {
  throw new Error("Config must include at least one endpoint in `endpoints`.");
}

function buildOptions(config) {
  const options = {
    discardResponseBodies: config.discardResponseBodies === true,
    thresholds: config.thresholds || {
      http_req_failed: ["rate<0.02"],
      http_req_duration: ["p(95)<1000", "p(99)<2000"],
    },
  };

  if (Array.isArray(config.stages) && config.stages.length > 0) {
    options.stages = config.stages;
  } else if (config.vus && config.duration) {
    options.vus = config.vus;
    options.duration = config.duration;
  } else {
    options.stages = [
      { duration: "30s", target: 10 },
      { duration: "1m", target: 50 },
      { duration: "30s", target: 0 },
    ];
  }

  if (config.summaryTrendStats) {
    options.summaryTrendStats = config.summaryTrendStats;
  }

  return options;
}

export const options = buildOptions(cfg);

function normalizeUrl(baseUrl, endpointUrl) {
  if (!endpointUrl) {
    return baseUrl;
  }
  if (endpointUrl.startsWith("http://") || endpointUrl.startsWith("https://")) {
    return endpointUrl;
  }
  const left = (baseUrl || "").replace(/\/+$/, "");
  const right = endpointUrl.startsWith("/") ? endpointUrl : `/${endpointUrl}`;
  return `${left}${right}`;
}

function pickEndpoint(endpoints) {
  const totalWeight = endpoints.reduce((sum, item) => sum + (item.weight || 1), 0);
  const random = Math.random() * totalWeight;
  let acc = 0;
  for (const endpoint of endpoints) {
    acc += endpoint.weight || 1;
    if (random <= acc) {
      return endpoint;
    }
  }
  return endpoints[endpoints.length - 1];
}

function asBody(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value === "string") {
    return value;
  }
  return JSON.stringify(value);
}

export default function () {
  const endpoint = pickEndpoint(cfg.endpoints);
  const url = normalizeUrl(cfg.baseUrl, endpoint.url);
  const method = (endpoint.method || "GET").toUpperCase();
  const body = asBody(endpoint.body);
  const headers = { ...(cfg.headers || {}), ...(endpoint.headers || {}) };
  const expectedStatus = endpoint.expectedStatus || [200];
  const timeout = endpoint.timeout || cfg.timeout || DEFAULT_TIMEOUT;

  const response = http.request(method, url, body, {
    headers,
    timeout,
    tags: {
      endpoint_name: endpoint.name || endpoint.url || "unnamed",
      endpoint_method: method,
    },
  });

  const ok = check(response, {
    "status is expected": (r) => expectedStatus.includes(r.status),
  });

  successfulChecks.add(ok);
  if (!ok) {
    checkFailures.add(1);
    endpointFailures.add(1, { endpoint_name: endpoint.name || endpoint.url || "unnamed" });
  }

  sleep(endpoint.sleepSeconds ?? cfg.sleepSeconds ?? DEFAULT_SLEEP_SECONDS);
}

